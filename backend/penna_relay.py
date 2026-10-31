"""Penna 一键接力后端。标准输出为逐行 JSON，供桌面进度面板读取。"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import time
import urllib.parse
import urllib.request
import uuid

from PIL import Image, ImageDraw, ImageFont
from gpu_mode import Controller, COMFY, controller_lock
from runtime_config import CONFIG

TEMPLATE = CONFIG.workflow
OUTPUT = CONFIG.output


def emit(stage, message, **data):
    print(json.dumps({"stage": stage, "message": message, **data}, ensure_ascii=False), flush=True)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(path)


def content_hash(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def validate_workflow(workflow):
    required = {'1': 'UNETLoader', '2': 'ModelSamplingAuraFlow', '5': 'CLIPTextEncode', '6': 'CLIPTextEncode', '8': 'KSampler', '11': 'SaveImage'}
    if not isinstance(workflow, dict) or any(not isinstance(n, dict) or not isinstance(n.get('inputs'), dict) for n in workflow.values()):
        raise ValueError('需要 Penna 专用 API 工作流，请选择随包提供的 moss-api.json。')
    for key, kind in required.items():
        if workflow.get(key, {}).get('class_type') != kind:
            raise ValueError(f'工作流节点 {key} 必须为 {kind}；请使用 Penna 专用模板。')


def prepare(snapshot, root=OUTPUT):
    width, height = snapshot["width"], snapshot["height"]
    if any(not isinstance(v, int) or not 64 <= v <= 4096 or v % 16 for v in (width, height)):
        raise ValueError("画布宽高应为 64–4096 之间的 16 的倍数。")
    layout = json.loads(json.dumps(snapshot["layout"]))
    if not isinstance(layout.get("items"), list) or not isinstance(layout.get("summary"), dict):
        raise ValueError("当前页面缺少有效的 MOSS 分镜。")
    settings = snapshot.get("settings", {})
    steps, seed = int(settings.get("steps", 50)), int(settings.get("seed", 42))
    strength, cfg = float(settings.get("strength", .85)), float(settings.get("cfg", 3))
    if not 1 <= steps <= 100 or not 0 <= seed < 2**53 or not 0 <= strength <= 2 or not 0 <= cfg <= 20:
        raise ValueError("步数、种子、LoRA 强度或 CFG 超出了允许范围。")
    lora = str(settings.get("lora", "moss_Lineart.safetensors"))
    selected=settings.get('loras',[{'name':lora,'strength':strength}])
    if not isinstance(selected,list) or len(selected)>32:
        raise ValueError('LoRA 列表无效，一次最多选择 32 个。')
    loras=[]
    for entry in selected:
        if not isinstance(entry,dict) or not isinstance(entry.get('name'),str) or not entry['name'].strip():
            raise ValueError('LoRA 文件名无效。')
        weight=float(entry.get('strength',.85))
        if not math.isfinite(weight) or not 0<=weight<=2:
            raise ValueError('每个 LoRA 的强度应为 0–2。')
        if any(item['name']==entry['name'] for item in loras):
            raise ValueError('同一个 LoRA 不可重复选择。')
        if weight:loras.append({'name':entry['name'],'strength':weight})
    lora=loras[0]['name'] if loras else ''
    strength=loras[0]['strength'] if loras else 0
    dialogues = []
    artwork = []
    for item in layout["items"]:
        if item.get("label") == "text":
            text = str(item.get("text", "")).strip()
            if text:
                box = list(item.get("bbox", []))
                if len(box) != 4 or not all(isinstance(v, (int, float)) and math.isfinite(v) for v in box):
                    raise ValueError("气泡坐标无效，请检查文字框。")
                if layout.get("bbox_format") == "yxyx":
                    box = [box[1], box[0], box[3], box[2]]
                if layout.get("bbox_coord_space") == "abs_centralized":
                    box = [box[0]+width//2, box[1]+height//2, box[2]+width//2, box[3]+height//2]
                box = [max(0, min(width if i % 2 == 0 else height, int(v))) for i, v in enumerate(box)]
                if box[2]-box[0] < 20 or box[3]-box[1] < 20:
                    raise ValueError("文字框太小，至少需要 20×20 像素。请在画布上放大文字框。")
                dialogues.append({"text": text, "box": box, "kind": settings.get("bubble", "oval")})
        else:
            artwork.append(item)
    if not artwork and not str(layout["summary"].get("caption", "")).strip():
        raise ValueError("请先在画布中写好画面描述。")
    layout["items"] = artwork
    # Agent 也可能把台词重复写入整体描述或人物 caption；仅删除文字节点还不够。
    def without_dialogue(value):
        if isinstance(value, dict): return {k:without_dialogue(v) for k,v in value.items()}
        if isinstance(value, list): return [without_dialogue(v) for v in value]
        if isinstance(value, str):
            for dialogue in dialogues:
                value=value.replace(dialogue['text'], '')
            # 去掉原稿里“气泡盖住肩膀”等绘画指令，避免模型额外画出第二个空气泡。
            value=re.sub(r'\b(?:a|an|the)\s+(?:\w+\s+){0,4}(?:speech\s+bubble|speech\s+balloon)[^.;\n]*(?:[.;]|$)', '', value, flags=re.I)
            value=re.sub(r'\bDialogue(?:,\s*in\s+order)?\s*:\s*[\\"“”\s]*', '', value, flags=re.I)
            return value
        return value
    layout=without_dialogue(layout)
    layout["summary"]["caption"] = (str(layout["summary"].get("caption", "")) +
        "\nArtwork only. No text, no lettering, no speech bubbles. All dialogue is added separately by software.")
    prompt = json.dumps(layout, ensure_ascii=False)
    params = {"prompt": prompt, "width": width, "height": height, "seed": seed,
              "steps": steps, "cfg": cfg, "lora_name": lora, "lora_strength": strength, "shift": 5}
    token = re.compile(r"^\s*\{\{\s*([a-zA-Z0-9_.-]+)(?::([^}]*))?\s*\}\}\s*$")
    def fill(value):
        if isinstance(value, dict): return {k: fill(v) for k, v in value.items()}
        if isinstance(value, list): return [fill(v) for v in value]
        match = token.fullmatch(value) if isinstance(value, str) else None
        if match:
            key, default = match.groups()
            if key in params: return params[key]
            if default is None: raise ValueError(f"工作流有未识别的占位符：{key}")
            default = default.strip()
            if re.fullmatch(r"-?\d+", default): return int(default)
            if re.fullmatch(r"-?\d+\.\d+", default): return float(default)
            if default.lower() in ("true", "false"): return default.lower() == "true"
            return default
        return value
    workflow = json.loads(TEMPLATE.read_text(encoding="utf-8-sig"))
    validate_workflow(workflow)
    # 模板自带的模型 LoRA 链由面板选择替代，避免默认 LoRA 重复或在未勾选时加载。
    old_chain = set()
    link = workflow['2']['inputs']['model']
    while isinstance(link, list) and len(link) == 2 and link[0] != '1':
        node_id = link[0]
        node = workflow.get(node_id, {})
        if node_id in old_chain or node.get('class_type') != 'LoraLoaderModelOnly':
            raise ValueError('工作流的模型 LoRA 链格式不兼容，请检查模型连接。')
        old_chain.add(node_id)
        link = node.get('inputs', {}).get('model')
    if link != ['1', 0]:
        raise ValueError('工作流模型连接未指向基础模型，请检查模型连接。')
    for node_id in old_chain: workflow.pop(node_id)
    workflow['2']['inputs']['model'] = ['1', 0]
    def references_removed(value):
        if isinstance(value, list):
            if len(value) == 2 and isinstance(value[0], str) and isinstance(value[1], int) and value[0] in old_chain:
                return True
            return any(references_removed(v) for v in value)
        return isinstance(value, dict) and any(references_removed(v) for v in value.values())
    if references_removed(workflow):
        raise ValueError('模板中的 LoRA 节点还连接到其他位置，无法安全替换。')
    workflow = fill(workflow)
    previous='1'
    for i,entry in enumerate(loras):
        node_id='12' if i==0 else f'relay_lora_{i+1}'
        workflow[node_id]={'class_type':'LoraLoaderModelOnly','inputs':{
            'model':[previous,0],'lora_name':entry['name'],'strength_model':entry['strength']}}
        previous=node_id
    workflow['2']['inputs']['model']=[previous,0]
    job_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    job = root / job_id
    job.mkdir(parents=True, exist_ok=False)
    workflow["11"]["inputs"]["filename_prefix"] = f"moss/penna-relay/{job_id}"
    workflow["6"]["inputs"]["text"] = "text, lettering, speech bubble, watermark, caption, subtitles"
    source = snapshot.get("source", snapshot["layout"])
    page = {"title": snapshot.get("title", "当前分镜"), "width": width, "height": height,
            "source": source, "source_hash": content_hash(source),
            "context": snapshot.get("context", {}), "original_layout": snapshot["layout"],
            "settings": params | {"loras":loras,"bubble":settings.get('bubble','oval')}, "dialogues": dialogues}
    write_json(job / "snapshot.json", snapshot)
    write_json(job / "page.json", page)
    write_json(job / "workflow.json", workflow)
    write_json(job / "manifest.json", {"status": "saved", "job_id": job_id, "seed": seed,
        "lora": lora, "lora_strength": strength, "loras":loras, "steps": steps, "prompt": prompt,
        "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(), "started_at": time.time(),
        "source_hash": page["source_hash"], "context": page["context"], "snapshot_hash": content_hash(snapshot)})
    return job


def compose(job):
    page = json.loads((job / "page.json").read_text(encoding="utf-8"))
    image = Image.open(job / "raw.png").convert("RGB")
    if image.size != (page["width"], page["height"]):
        raise ValueError("生成图片尺寸与已保存的分镜不符。")
    d = ImageDraw.Draw(image)
    font_path = next((p for p in [CONFIG.bundle / "font/LXGW975YuanSC-500W.ttf", Path(r"C:\Windows\Fonts\simhei.ttf"), Path(r"C:\Windows\Fonts\msyh.ttc")] if p.is_file()), None)
    if page["dialogues"] and font_path is None:
        raise RuntimeError("没有找到中文字体，原始图片已保留。")
    # 延续 page3_compose.py 的椭圆/云朵/锯齿和自适应竖排，改成局部画布，避免跨框溢出。
    for bubble in page["dialogues"]:
        x1, y1, x2, y2 = bubble["box"]
        bw, bh = x2-x1, y2-y1
        cx, cy, rx, ry = (x1+x2)/2, (y1+y2)/2, bw/2, bh/2
        kind = bubble["kind"]
        if kind == "spiky":
            points = [(cx+rx*(1 if i%2==0 else .87)*math.cos(i*math.pi/12),
                       cy+ry*(1 if i%2==0 else .87)*math.sin(i*math.pi/12)) for i in range(24)]
            d.polygon(points, fill="white", outline="black", width=2)
        elif kind == "cloud":
            for i in range(12):
                a = i*math.pi/6; r = min(rx, ry)*.2
                bx, by = cx+rx*.8*math.cos(a), cy+ry*.8*math.sin(a)
                d.ellipse((bx-r, by-r, bx+r, by+r), fill="white", outline="black", width=2)
            d.ellipse((x1+rx*.1, y1+ry*.1, x2-rx*.1, y2-ry*.1), fill="white")
        else:
            d.ellipse((x1, y1, x2, y2), fill="white", outline="black", width=2)
            # 尾巴朝下，限制在文字框内，不覆盖框外人物。
            d.polygon([(cx+rx*.35, cy+ry*.8), (cx+rx*.55, y2-1), (cx+rx*.1, cy+ry*.94)], fill="white", outline="black", width=2)
        text = bubble["text"]
        vertical = bh > bw * 1.25
        fitted = None
        for size in range(min(48, max(bw, bh)//3), 5, -1):
            font = ImageFont.truetype(str(font_path), size)
            gap = max(1, round(size*1.2))
            if vertical:
                limit = max(1, int(bh*.68)//gap)
                columns = [line[i:i+limit] for line in text.splitlines() for i in range(0, len(line), limit)]
                if len(columns)*gap <= bw*.68:
                    fitted=(font, columns, gap); break
            else:
                lines=[]; line=""
                for ch in text:
                    if ch == "\n" or (line and d.textlength(line+ch, font=font)>bw*.68):
                        lines.append(line);line=""
                    if ch != "\n": line+=ch
                if line:lines.append(line)
                # 中文句末标点不能单独挤到下一行，宁可略微缩小字号。
                if len(lines)*gap <= bh*.68 and not any(line and line[0] in '。，！？、；：）》」』”’' for line in lines[1:]):
                    fitted=(font, lines, gap); break
        if fitted is None:
            raise ValueError("台词太长，无法放进文字框。请放大文字框或缩短台词；原始图片已保存。")
        font, lines, gap = fitted
        if vertical:
            x = cx+(len(lines)-1)*gap/2
            for line in lines:
                y = cy-len(line)*gap/2
                for ch in line:
                    d.text((x, y), ch, fill="black", font=font, anchor="mt");y+=gap
                x-=gap
        else:
            y=cy-len(lines)*gap/2
            for line in lines:
                d.text((cx, y), line, fill="black", font=font, anchor="mt");y+=gap
        bubble["font_size"] = font.size
        bubble["lines"] = lines
    path = job / "page.png"
    image.save(path)
    write_json(job / "page.json", page)
    return path


def queued_prompt_ids(controller):
    queue = controller.api(COMFY, "/queue")
    return {entry.get("prompt_id") if isinstance(entry, dict) else entry[1]
            for key in ("queue_running", "queue_pending") for entry in queue.get(key, [])}


def run(job, controller=None, timeout=1800, manage_gpu=True, event_callback=None):
    """Render one saved job. Batch callers own the GPU lifecycle and event stream."""
    job = Path(job)
    c = controller or Controller()
    manifest = json.loads((job / "manifest.json").read_text(encoding="utf-8"))
    start = time.monotonic()
    def stage(name, message, **data):
        manifest.update(status=name, updated_at=time.time(), **data)
        write_json(job / "manifest.json", manifest)
        (event_callback or emit)(name, message, job_dir=str(job), **data)
    if manifest.get("status") == "done" and (job / "page.png").is_file():
        (event_callback or emit)("done", "该页已经完成，已跳过生成。", job_dir=str(job), image=str(job / "page.png"))
        return job / "page.png"
    image_phase = False
    try:
        if not (job / "raw.png").is_file():
            prompt_id = manifest.get("prompt_id")
            if manage_gpu:
                if queued_prompt_ids(c) - ({prompt_id} if prompt_id else set()):
                    c.assert_comfy_idle()
                stage("switching", "分镜已保存，正在释放大模型显存…")
                c.adopt_configured_server()
                image_phase = True
                c.image()
            resumed = bool(prompt_id)
            if not prompt_id:
                c.assert_comfy_idle()
                workflow = json.loads((job / "workflow.json").read_text(encoding="utf-8"))
                # Save submission intent before sending. An interrupted HTTP response is
                # ambiguous, so resume must never silently submit a second GPU task.
                if manifest.get("submission_started"):
                    raise RuntimeError("上次提交结果未知，请检查 ComfyUI；为避免重复任务，不会自动重新提交。")
                stage("submitting", "正在提交已保存的分镜…", submission_started=True)
                response = c.api(COMFY, "/prompt", {"prompt": workflow, "client_id": "penna-relay"}, timeout=30)
                prompt_id = response["prompt_id"]
            stage("rendering", "ComfyUI 正在生成，通常需要 1–2 分钟…", prompt_id=prompt_id)
            deadline = time.monotonic() + timeout
            while True:
                history = c.api(COMFY, f"/history/{prompt_id}").get(prompt_id)
                if history is not None: break
                if resumed and prompt_id not in queued_prompt_ids(c):
                    raise RuntimeError("上次任务的历史已丢失，请检查 ComfyUI，避免重复提交。")
                if time.monotonic() >= deadline:
                    raise TimeoutError("出图等待超时。任务记录已保留，请先查看 ComfyUI 状态。")
                time.sleep(1)
            write_json(job / "comfy-history.json", history)
            if history.get("status", {}).get("status_str") == "error":
                raise RuntimeError("ComfyUI 生成失败，详细错误已保存到 comfy-history.json。")
            images = [im for out in history.get("outputs", {}).values() for im in out.get("images", []) if im.get("type") == "output"]
            if not images:raise RuntimeError("ComfyUI 没有返回可保存的图片。")
            params=urllib.parse.urlencode({k:images[0].get(k, "") for k in ("filename", "subfolder", "type")})
            with urllib.request.urlopen(COMFY+"/view?"+params, timeout=60) as r:
                raw=r.read()
            temp=job / "raw.download"
            temp.write_bytes(raw)
            with Image.open(temp) as image:image.verify()
            temp.replace(job / "raw.png")
        stage("composing", "画面已生成，正在排入台词气泡…")
        path=compose(job)
        if manage_gpu:
            stage("restoring", "漫画页已保存，正在恢复对话模型…", image=str(path))
            c.chat();image_phase=False
        stage("done", "接力完成，可以继续与 Agent 对话。" if manage_gpu else "漫画页已完成。",
              image=str(path), elapsed_seconds=round(time.monotonic()-start, 2))
        return path
    except Exception as exc:
        restore_error=None
        if manage_gpu and image_phase:
            try:c.chat()
            except Exception as restore:restore_error=str(restore)
        stage("error", str(exc), error=str(exc), restore_error=restore_error,
              image=str(job / "page.png") if (job / "page.png").is_file() else None)
        raise


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--snapshot")
    inputs.add_argument("--resume")
    inputs.add_argument("--batch")
    inputs.add_argument("--resume-batch")
    parser.add_argument("--prepare-only", action="store_true")
    args=parser.parse_args()
    batch_dir = Path(args.resume_batch).resolve() if args.resume_batch else None
    try:
        with controller_lock():
            if args.batch or args.resume_batch:
                from penna_batch import prepare_batch, run_batch
                if args.batch:
                    request = json.loads(Path(args.batch).read_text(encoding="utf-8-sig"))
                    batch_dir = prepare_batch(request)
                    write_json(CONFIG.home/'relay-settings.json', request.get('settings', {}))
                else:
                    batch_dir = Path(args.resume_batch).resolve()
                if not args.prepare_only:
                    run_batch(batch_dir)
                else:
                    from penna_batch import load_batch, batch_event
                    batch_event(batch_dir, load_batch(batch_dir), "saved", "批次快照已全部保存。")
            elif args.resume:
                job=Path(args.resume).resolve()
                if OUTPUT.resolve() not in job.parents:
                    raise ValueError("只能恢复 penna-relay 输出目录中的任务。")
            elif args.snapshot:
                snapshot=json.loads(Path(args.snapshot).read_text(encoding="utf-8-sig"))
                job=prepare(snapshot)
                write_json(CONFIG.home/'relay-settings.json',snapshot.get('settings',{}))
                emit("saved", "当前分镜和生图参数已保存。", job_dir=str(job))
            if not (args.batch or args.resume_batch) and not args.prepare_only:run(job)
        return 0
    except Exception as exc:
        if not getattr(exc, "emitted", False):
            if args.batch or args.resume_batch:
                emit("error", str(exc), batch_dir=str(batch_dir) if batch_dir else None,
                     page_index=None, page_total=0, job_dir=None, image=None, pages=[])
            else:
                emit("error", str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
