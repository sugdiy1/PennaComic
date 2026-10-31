"""Persisted, sequential Penna batches. CLI entry point lives in penna_relay.py.

Public page_index values are 1-based. Every event contains the complete pages
summary, and only a whole-batch terminal event uses ``done`` or ``error``.
The CLI holds controller_lock for the entire prepare/run operation.
"""
import copy
import json
from pathlib import Path
import time
import uuid

import penna_relay as relay


class BatchError(RuntimeError):
    """A failure already reported as a terminal batch event."""
    emitted = True


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def batch_event(batch_dir, batch, stage, message, page=None, **extra):
    batch["updated_at"] = time.time()
    relay.write_json(batch_dir / "batch.json", batch)
    event = {"stage": stage, "message": message, "batch_dir": str(batch_dir),
             "page_index": page["number"] if page else None,
             "page_total": batch.get("page_total",len(batch["pages"])), "job_dir": page["job_dir"] if page else None,
             "image": page.get("image") if page else None,
             "pages": copy.deepcopy(batch["pages"]), **extra}
    with (batch_dir / "events.ndjson").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event, ensure_ascii=False) + "\n")
    relay.emit(**event)


def prepare_batch(request, root=None):
    """Save every immutable snapshot before the caller can enter GPU image mode."""
    if not isinstance(request, dict) or not isinstance(request.get("pages"), list) or not request["pages"]:
        raise ValueError("批次需要至少一页有效快照。")
    settings = request.get("settings", {})
    if not isinstance(settings, dict) or not isinstance(request.get("skip_completed", True), bool):
        raise ValueError("批次设置或 skip_completed 无效。")
    base_seed = int(settings.get("seed", request["pages"][0].get("settings", {}).get("seed", 42)))
    if not 0 <= base_seed <= 2**53 - len(request["pages"]):
        raise ValueError("批次种子超出了允许范围。")
    snapshots = []
    for index, original in enumerate(request["pages"]):
        if not isinstance(original, dict):
            raise ValueError("批次中的页面必须为快照对象。")
        snapshot = copy.deepcopy(original)
        snapshot["settings"] = {**snapshot.get("settings", {}), **settings, "seed": base_seed + index}
        if not isinstance(snapshot.get("context", {}), dict):
            raise ValueError("页面 context 必须为对象。")
        snapshots.append(snapshot)
    root = Path(root) if root is not None else relay.OUTPUT
    batch_id = time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    batch_dir = (root / "batches" / batch_id).resolve()
    batch_dir.mkdir(parents=True, exist_ok=False)
    batch = {"version": 1, "batch_id": batch_id, "title": request.get("title", "漫画批次"),
             "status": "saving", "created_at": time.time(), "settings": settings,
             "skip_completed": request.get("skip_completed", True), "page_total":len(snapshots), "pages": []}
    # Full input survives even a later page's preparation/validation failure.
    relay.write_json(batch_dir / "request.json", request)
    relay.write_json(batch_dir / "snapshots.json", snapshots)
    relay.write_json(batch_dir / "batch.json", batch)
    try:
        for index, snapshot in enumerate(snapshots, 1):
            job = relay.prepare(snapshot, root=batch_dir / f"page-{index:03d}")
            page = {"number": index, "title": snapshot.get("title", f"第 {index} 页"),
                    "job_dir": str(job), "status": "saved", "image": None,
                    "context": snapshot.get("context", {}),
                    "source_hash": relay.content_hash(snapshot.get("source", snapshot["layout"])),
                    "snapshot_hash": relay.content_hash(snapshot), "error": None, "versions": []}
            page["versions"].append(str(job))
            batch["pages"].append(page)
        batch["status"] = "saved"
        for page in batch["pages"]:
            batch_event(batch_dir, batch, "page_saved", "页面快照和工作流已保存。", page)
        return batch_dir
    except Exception as exc:
        batch.update(status="error", error=str(exc))
        batch_event(batch_dir, batch, "error", str(exc))
        raise BatchError(str(exc)) from exc


def load_batch(batch_dir):
    """Validate all persisted paths and snapshot identities before touching GPU."""
    batch_dir = Path(batch_dir).resolve()
    allowed = (relay.OUTPUT / "batches").resolve()
    if allowed not in batch_dir.parents:
        raise ValueError("只能恢复 penna-relay/batches 输出目录中的批次。")
    batch = read_json(batch_dir / "batch.json")
    if batch.get("version") != 1 or not batch.get("pages"):
        raise ValueError("批次记录无效或没有可恢复页面。")
    snapshots=read_json(batch_dir / "snapshots.json")
    if not isinstance(snapshots,list) or len(batch['pages'])!=len(snapshots) or batch.get('page_total',len(snapshots))!=len(snapshots):
        raise ValueError("批次页面保存未完成，请修正无效页后新建批次；不能省略缺页后继续导出。")
    seen = set()
    for index, page in enumerate(batch["pages"], 1):
        job = Path(page["job_dir"]).resolve()
        if batch_dir not in job.parents or job in seen or page.get("number") != index:
            raise ValueError("页面任务路径或页序不属于指定批次。")
        seen.add(job)
        for filename in ("snapshot.json", "page.json", "workflow.json", "manifest.json", "raw.png", "page.png"):
            if job not in (job / filename).resolve().parents:
                raise ValueError("页面文件不能指向批次目录以外。")
        snapshot = read_json(job / "snapshot.json")
        original = read_json(job / "page.json")
        manifest = read_json(job / "manifest.json")
        source_hash = relay.content_hash(snapshot.get("source", snapshot["layout"]))
        if (snapshot != snapshots[index - 1]
                or relay.content_hash(snapshot) != page.get("snapshot_hash")
                or relay.content_hash(snapshot) != manifest.get("snapshot_hash")
                or source_hash != page.get("source_hash")
                or original.get("original_layout") != snapshot["layout"]
                or original.get("source") != snapshot.get("source", snapshot["layout"])
                or original.get("context", {}) != snapshot.get("context", {})
                or page.get("context", {}) != snapshot.get("context", {})
                or original.get("width") != snapshot["width"] or original.get("height") != snapshot["height"]):
            raise ValueError("已保存的页面快照发生变化；请新建批次保留旧版本。")
        page["job_dir"] = str(job)
        page["image"] = str(job / "page.png") if (job / "page.png").is_file() else None
        # A process can stop after the page manifest was committed but before
        # the batch manifest was updated. Recover the completed page here.
        if manifest.get("status") == "done" and page["image"]:
            page.update(status="done", error=None)
        elif manifest.get("status") == "error":
            page.update(status="error", error=manifest.get("error"))
    return batch


def run_batch(batch_dir, controller=None, timeout=1800):
    """Run pages serially, reusing one image-mode interval and one safe restore."""
    batch_dir = Path(batch_dir).resolve()
    batch = load_batch(batch_dir)
    c = controller or relay.Controller()
    work = []
    for page in batch["pages"]:
        redo = False
        redo_message = "重做已保存为独立新版本。"
        if page["status"] == "done" and page["image"]:
            if batch.get("skip_completed", True):
                batch_event(batch_dir, batch, "page_done", "页面已完成，跳过生成。", page, skipped=True)
                continue
            redo = True
        elif page["status"] == "error":
            job = Path(page["job_dir"])
            manifest = read_json(job / "manifest.json")
            prompt_id = manifest.get("prompt_id")
            if prompt_id and not (job / "raw.png").exists():
                history = c.api(relay.COMFY, f"/history/{prompt_id}").get(prompt_id)
                # Only a confirmed terminal failure may be resubmitted as a
                # new version. Missing history or queued work stays untouched.
                if (history is not None and history.get("status", {}).get("status_str") == "error"
                        and prompt_id not in relay.queued_prompt_ids(c)):
                    redo = True
                    redo_message = "失败任务已结束，重试已保存为独立新版本。"
        if redo:
            # Explicit re-render and confirmed failed-task retries create new
            # versions, preserving every old file and the original seed.
            old_job = Path(page["job_dir"])
            job = relay.prepare(read_json(old_job / "snapshot.json"), root=old_job.parent)
            page["versions"].append(str(job))
            page.update(job_dir=str(job), status="saved", image=None, error=None)
            batch_event(batch_dir, batch, "page_saved", redo_message, page)
        work.append(page)
    failure = None
    restore_error = None
    image_phase = bool(batch.get("gpu_restore_pending"))
    try:
        if work:
            owned_ids = {read_json(Path(page["job_dir"]) / "manifest.json").get("prompt_id") for page in work}
            if relay.queued_prompt_ids(c) - owned_ids:
                c.assert_comfy_idle()
            batch.update(status="rendering", error=None, restore_error=None)
            batch_event(batch_dir, batch, "switching", "全部分镜已保存，正在释放大模型显存…")
            c.adopt_configured_server()
            image_phase = True
            batch["gpu_restore_pending"] = True
            relay.write_json(batch_dir / "batch.json", batch)
            c.image()
        for page in work:
            def on_stage(stage, message, **data):
                event = "page_error" if stage == "error" else "page_done" if stage == "done" else "page_rendering"
                page.update(status="error" if stage == "error" else "done" if stage == "done" else "rendering")
                if "image" in data: page["image"] = data["image"]
                if "error" in data: page["error"] = data["error"]
                if stage == "done": page["error"] = None
                batch_event(batch_dir, batch, event, message, page, **{
                    k: v for k, v in data.items() if k not in ("job_dir", "image")})
            try:
                relay.run(Path(page["job_dir"]), c, timeout=timeout, manage_gpu=False, event_callback=on_stage)
            except Exception as exc:
                failure = str(exc)
                # A timed-out or externally queued GPU job cannot overlap with
                # the next page. Preserve remaining saved pages for resume.
                try:
                    c.assert_comfy_idle()
                except Exception:
                    break
    except Exception as exc:
        failure = str(exc)
    finally:
        if image_phase:
            batch_event(batch_dir, batch, "restoring", "正在安全恢复对话模型…")
            try:
                # Controller.chat also checks the queue; never unload models
                # or start the LLM while ComfyUI has running/pending work.
                c.assert_comfy_idle()
                c.chat()
                batch["gpu_restore_pending"] = False
            except Exception as exc:
                restore_error = str(exc)
    incomplete = [page for page in batch["pages"] if page["status"] != "done"]
    if failure or restore_error or incomplete:
        message = failure or ("恢复对话模型失败：" + restore_error if restore_error else "部分页面未完成。")
        batch.update(status="error", error=message, restore_error=restore_error)
        batch_event(batch_dir, batch, "error", message, restore_error=restore_error)
        raise BatchError(message)
    batch.update(status="done", error=None, restore_error=None)
    batch_event(batch_dir, batch, "done", "全部漫画页已保存，可以继续对话。")
    return batch
