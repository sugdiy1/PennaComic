"""Render selected Penna boxes independently, then composite using real masks."""
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import re
import time
import uuid

from PIL import Image, ImageDraw

import penna_relay as relay
from render_cancel import RenderCancelled, RenderCancelToken


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def auto_indices(boxes):
    """Named panel backgrounds win over nested people/object/detail boxes."""
    groups = {}
    for index, box in enumerate(boxes):
        if not isinstance(box, dict) or box.get('label') in ('text', 'character'):
            continue
        match = re.match(r'^(第[\d一二三四五六七八九十]+格|panel\s*\d+)(?:$|[\s·:：-])', str(box.get('name', '')), re.I)
        if not match:
            continue
        rect = box.get('box', [])
        if len(rect) != 4:
            continue
        area = max(0, rect[2] - rect[0]) * max(0, rect[3] - rect[1])
        key = match.group(1).lower()
        if key not in groups or area > groups[key][0]:
            groups[key] = (area, index)
    return sorted(value[1] for value in groups.values())


def rectangle(box, width, height):
    rect = box.get('box')
    if (not isinstance(rect, list) or len(rect) != 4
            or any(type(v) is not int for v in rect)):
        raise ValueError('漫画格必须使用整数像素 box:[left,top,right,bottom]。')
    l, t, r, b = rect
    if (not 16 <= r-l <= 4096 or not 16 <= b-t <= 4096
            or r <= 0 or b <= 0 or l >= width or t >= height):
        raise ValueError('漫画格没有有效面积、太窄或完全位于画布外。')
    return rect


def shape(box):
    value = box.get('shape')
    if value is None or value in ('rect', 'ellipse'):
        return value
    if not isinstance(value, list) or not 3 <= len(value) <= 16:
        raise ValueError('漫画格形状应为 ellipse、rect 或 3–16 个归一化顶点。')
    for point in value:
        if (not isinstance(point, list) or len(point) != 2
                or any(not isinstance(n, (int, float)) or isinstance(n, bool)
                       or not math.isfinite(n) or not 0 <= n <= 1 for n in point)):
            raise ValueError('多边形顶点必须是相对本框 0–1 的坐标。')
    area = abs(sum(value[i][0]*value[(i+1) % len(value)][1] - value[(i+1) % len(value)][0]*value[i][1]
                   for i in range(len(value)))) / 2
    if area < .001:
        raise ValueError('漫画格多边形面积过小。')
    return value


def overlap(a, b):
    l, t = max(a[0], b[0]), max(a[1], b[1])
    r, bottom = min(a[2], b[2]), min(a[3], b[3])
    return max(0, r-l) * max(0, bottom-t)


def plan(snapshot):
    width, height = snapshot['width'], snapshot['height']
    if any(type(n) is not int or not 64 <= n <= 4096 or n % 16 for n in (width, height)):
        raise ValueError('画布宽高应为 64–4096 之间的 16 的倍数。')
    source = snapshot.get('source', {})
    boxes = source.get('boxes') if isinstance(source, dict) else None
    if not isinstance(boxes, list):
        raise ValueError('逐格拼接需要 Penna 画板原始 boxes 数据。')
    settings = snapshot.get('settings', {})
    if type(settings.get('panel_edit', False)) is not bool:
        raise ValueError('逐格 Qwen 修改开关必须为布尔值。')
    selected = settings.get('panel_indices', auto_indices(boxes))
    if (not isinstance(selected, list) or not 1 <= len(selected) <= 32
            or any(type(i) is not int or not 0 <= i < len(boxes) for i in selected)
            or len(set(selected)) != len(selected)):
        raise ValueError('请勾选 1–32 个作为漫画格的方框，人物框和台词框不用勾选。')
    resolution = settings.get('panel_resolution', 768)
    if type(resolution) is not int or not 256 <= resolution <= 1536 or resolution % 32:
        raise ValueError('逐格分辨率应为 256–1536 之间的 32 的倍数。')
    base_seed = settings.get('seed', 42)
    if type(base_seed) is not int or not 0 <= base_seed < 2**53-len(selected):
        raise ValueError('逐格种子超出允许范围。')
    frames = []
    for index in selected:
        box = boxes[index]
        if not isinstance(box, dict) or box.get('label') == 'text' or not str(box.get('caption', '')).strip():
            raise ValueError('漫画格应有独立画面描述，台词框不能作为漫画格。')
        frames.append({'source_index': index, 'box': rectangle(box, width, height), 'shape': shape(box),
                       'name': str(box.get('name') or f'第{len(frames)+1}格'), 'caption': str(box['caption']),
                       'layer': box.get('layer', 'middle'), 'elements': []})
    seeds = settings.get('panel_seeds', {})
    if (not isinstance(seeds, dict) or any(str(i) not in {str(n) for n in selected}
            or type(value) is not int or not 0 <= value < 2**53 for i, value in seeds.items())):
        raise ValueError('单格种子必须指向已选漫画格，并使用有效的非负整数。')
    # Each detail/dialogue belongs to one frame, chosen by its largest intersection.
    for index, element in enumerate(boxes):
        if index in selected or not isinstance(element, dict):
            continue
        rect = element.get('box', [])
        if len(rect) != 4 or any(not isinstance(v, (int, float)) for v in rect):
            raise ValueError('格内元素的坐标无效。')
        areas = [overlap(rect, frame['box']) for frame in frames]
        if max(areas, default=0) > 0:
            frames[areas.index(max(areas))]['elements'].append(copy.deepcopy(element))
        elif element.get('label') == 'text' and str(element.get('text', '')).strip():
            raise ValueError('有台词框未落入所选漫画格，请先移入格内，避免台词丢失。')
    for i, frame in enumerate(frames):
        l, t, r, b = frame['box']
        scale = resolution / max(r-l, b-t)
        unit = 32 if settings.get('panel_edit', False) else 16
        w, h = [max(64, round(n*scale/unit)*unit) for n in (r-l, b-t)]
        if max((r-l)/(b-t), (b-t)/(r-l)) > 12:
            raise ValueError('漫画格长宽比过大，请调整布局后再逐格生成。')
        items = []
        for element in frame['elements']:
            x1, y1, x2, y2 = element['box']
            a, c = max(0, round((x1-l)/(r-l)*w)), max(0, round((y1-t)/(b-t)*h))
            d, e = min(w, round((x2-l)/(r-l)*w)), min(h, round((y2-t)/(b-t)*h))
            if d <= a or e <= c:
                continue
            item = {'label': element.get('label', 'object'), 'caption': str(element.get('caption', '')),
                    'bbox': [c-h//2, a-w//2, e-h//2, d-w//2]}
            if element.get('label') == 'text' and str(element.get('text', '')).strip():
                item['text'] = element['text']
            items.append(item)
        cast = source.get('cast', {})
        caption = ('ONE standalone manga panel only, one camera shot. Do not draw a page layout, '
                   'extra panels or gutters. Render only the scene and people explicitly described below. '
                   'Keep any speech bubbles and their exact supplied Chinese text inside the visible panel. '
                   + str(source.get('style', '')) + '\nSCENE: ' + frame['caption'])
        if cast:
            caption += '\nCharacter appearance references (do not add off-screen characters): ' + json.dumps(cast, ensure_ascii=False)
        if frame['shape'] not in (None, 'rect'):
            caption += '\nThis image will be clipped to an ellipse or polygon; keep faces, hands and dialogue away from the corners.'
        child = {'title': frame['name'], 'width': w, 'height': h,
                 'source': {'caption': caption, 'elements': items},
                 'layout': {'summary': {'caption': caption, 'canvas': 'single'}, 'items': items,
                            'bbox_coord_space': 'abs_centralized', 'bbox_format': 'yxyx'},
                 'context': {**snapshot.get('context', {}), 'panel_number': i+1},
                 'settings': {**settings, 'render_mode': 'generate_edit' if settings.get('panel_edit', False) else 'generate',
                              'seed': seeds.get(str(frame['source_index']), base_seed+i)}}
        frame['snapshot'] = child
    return frames


def prepare(snapshot, root):
    frames = plan(snapshot)
    job_id = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    job = Path(root) / job_id
    job.mkdir(parents=True, exist_ok=False)
    for i, frame in enumerate(frames, 1):
        child = relay.prepare(frame.pop('snapshot'), job/'panels'/f'{i:02}')
        frame['job_dir'] = str(child.resolve())
        for name in ('page.json', 'manifest.json'):
            data = read(child/name)
            data['artifact_kind'] = 'panel'
            relay.write_json(child/name, data)
        workflow = read(child/'workflow.json')
        for node in workflow.values():
            if node.get('class_type') == 'SaveImage':
                node['inputs']['filename_prefix'] = 'panel-cache'
        frame['cache_key'] = relay.content_hash(workflow)
    relay.write_json(job/'snapshot.json', snapshot)
    relay.write_json(job/'panel-plan.json', {'width': snapshot['width'], 'height': snapshot['height'], 'panels': frames})
    relay.write_json(job/'workflow.json', {'pipeline': 'panels', 'panel_count': len(frames)})
    source = snapshot.get('source', snapshot['layout'])
    relay.write_json(job/'page.json', {'title': snapshot.get('title', '逐格漫画'), 'width': snapshot['width'],
        'height': snapshot['height'], 'source': source, 'source_hash': relay.content_hash(source),
        'original_layout': snapshot['layout'], 'context': snapshot.get('context', {}),
        'settings': snapshot.get('settings', {}), 'text_mode': 'model', 'dialogues': []})
    relay.write_json(job/'manifest.json', {'status': 'saved', 'job_id': job_id, 'render_mode': 'panels',
        'text_mode': 'model', 'seed': snapshot.get('settings', {}).get('seed', 42), 'panel_count': len(frames),
        'source_hash': relay.content_hash(source), 'snapshot_hash': relay.content_hash(snapshot),
        'context': snapshot.get('context', {}), 'started_at': time.time()})
    return job


def child_path(job, frame):
    child = Path(frame['job_dir']).resolve()
    panels = (job/'panels').resolve()
    if not panels.is_relative_to(job) or not child.is_relative_to(panels):
        raise ValueError('格子任务路径不属于本页。')
    for name in ('snapshot.json', 'manifest.json', 'workflow.json', 'page.json', 'raw.png', 'page.png'):
        if not (child/name).resolve().is_relative_to(child):
            raise ValueError('格子文件不能指向任务目录外。')
    return child


def cache_paths(key):
    if not re.fullmatch(r'[a-f0-9]{64}', key):
        raise ValueError('格子缓存键无效。')
    root = relay.OUTPUT.resolve()
    cache = (root/'_panel_cache').resolve()
    if cache.parent != root:
        raise ValueError('缓存目录不能指向输出目录外。')
    return cache/(key+'.png'), cache/(key+'.json')


def cached(job, frame):
    child = child_path(job, frame)
    manifest = read(child/'manifest.json')
    if (child/'page.png').is_file() and manifest.get('status') == 'done':
        return True
    if manifest.get('prompt_id') or manifest.get('submission_started'):
        return False
    image, metadata = cache_paths(frame['cache_key'])
    if not image.is_file() or not metadata.is_file() or image.is_symlink() or metadata.is_symlink():
        return False
    data = image.read_bytes()
    try:
        record = read(metadata)
        snap = read(child/'snapshot.json')
        if record['sha256'] != hashlib.sha256(data).hexdigest():
            return False
        with Image.open(io.BytesIO(data)) as im:
            im.load()
            if im.size != (snap['width'], snap['height']):
                return False
    except (OSError, ValueError, KeyError):
        return False
    (child/'page.png').write_bytes(data)
    manifest = read(child/'manifest.json')
    manifest.update(status='done', cache_hit=True, image=str(child/'page.png'))
    relay.write_json(child/'manifest.json', manifest)
    return True


def store_cache(job, frame):
    image, metadata = cache_paths(frame['cache_key'])
    image.parent.mkdir(parents=True, exist_ok=True)
    data = (child_path(job, frame)/'page.png').read_bytes()
    if image.is_symlink() or metadata.is_symlink():
        raise ValueError('缓存文件不能为符号链接。')
    temporary = image.with_suffix('.png.tmp')
    if temporary.is_symlink():
        raise ValueError('缓存临时文件不能为符号链接。')
    temporary.write_bytes(data)
    temporary.replace(image)
    relay.write_json(metadata, {'sha256': hashlib.sha256(data).hexdigest(), 'cache_key': frame['cache_key']})


def composite(job, spec):
    page = Image.new('RGB', (spec['width'], spec['height']), 'white')
    layers = {'back': 0, 'middle': 1, 'front': 2}
    for frame in sorted(spec['panels'], key=lambda p: layers.get(p['layer'], 1)):
        l, t, r, b = frame['box'];w, h = r-l, b-t
        with Image.open(child_path(job, frame)/'page.png') as original:
            tile = original.convert('RGB').resize((w, h), Image.Resampling.LANCZOS)
        scale = 4
        mask = Image.new('L', (w*scale, h*scale), 0)
        draw = ImageDraw.Draw(mask)
        contour = frame['shape']
        if contour == 'ellipse':
            draw.ellipse((0, 0, w*scale-1, h*scale-1), fill=255)
        elif isinstance(contour, list):
            draw.polygon([(x*(w*scale-1), y*(h*scale-1)) for x, y in contour], fill=255)
        else:
            draw.rectangle((0, 0, w*scale-1, h*scale-1), fill=255)
        mask = mask.resize((w, h), Image.Resampling.LANCZOS)
        page.paste(tile, (l, t), mask)
        border = ImageDraw.Draw(page)
        if contour == 'ellipse':
            border.ellipse((l, t, r-1, b-1), outline='black', width=2)
        elif isinstance(contour, list):
            points = [(l+x*(w-1), t+y*(h-1)) for x, y in contour]
            border.line(points+[points[0]], fill='black', width=2, joint='curve')
        else:
            border.rectangle((l, t, r-1, b-1), outline='black', width=2)
    temp = job/'page.png.tmp'
    page.save(temp, format='PNG')
    temp.replace(job/'page.png')
    return job/'page.png'


def run(job, controller=None, timeout=1800, manage_gpu=True, event_callback=None, cancel_token=None):
    job = Path(job).resolve();spec = read(job/'panel-plan.json');manifest = read(job/'manifest.json')
    if manifest.get('status') == 'done' and (job/'page.png').is_file():
        (event_callback or relay.emit)('done', '逐格成品已完成，跳过生成。', job_dir=str(job), image=str(job/'page.png'))
        return job/'page.png'
    controller = controller or relay.Controller()
    cancel = cancel_token or RenderCancelToken()
    image_phase = bool(manage_gpu and manifest.get('gpu_restore_pending'))
    entered_image = False
    start = time.monotonic()

    def stage(name, message, **data):
        manifest.update(status=name, updated_at=time.time(), **data)
        relay.write_json(job/'manifest.json', manifest)
        (event_callback or relay.emit)(name, message, job_dir=str(job), **data)

    try:
        cancel.check(controller, manifest.get('prompt_id'))
        for index, frame in enumerate(spec['panels'], 1):
            cancel.check(controller, manifest.get('prompt_id'))
            if cached(job, frame):
                manifest.pop('prompt_id', None)
                stage('rendering', f'第 {index}/{len(spec["panels"])} 格已完成，复用缓存。', panel_index=index)
                continue
            child = child_path(job, frame)
            owned = read(child/'manifest.json').get('prompt_id')
            deadline = time.monotonic()+timeout
            waiting = False
            while relay.queued_prompt_ids(controller) - ({owned} if owned else set()):
                cancel.check(controller, owned)
                if not waiting:
                    stage('rendering', '正在等待其他 ComfyUI 任务完成，已保存的格子会保留。', panel_index=index)
                    waiting = True
                if time.monotonic() >= deadline:
                    raise TimeoutError('等待 ComfyUI 空闲超时；可以续跑，不会重复已完成格子。')
                time.sleep(1)
            if manage_gpu and not entered_image:
                stage('switching', '漫画格已全部保存，正在释放显存。')
                controller.adopt_configured_server();image_phase = True
                manifest['gpu_restore_pending'] = True
                relay.write_json(job/'manifest.json', manifest)
                controller.image();entered_image = True

            def progress(name, message, **data):
                # A child terminal event must not terminate the whole page stream.
                stage('rendering', f'第 {index}/{len(spec["panels"])} 格：{message}',
                      panel_index=index, **{k: v for k, v in data.items() if k in ('prompt_id',)})

            relay.run(child, controller, timeout=timeout, manage_gpu=False, event_callback=progress, cancel_token=cancel)
            store_cache(job, frame)
            manifest.pop('prompt_id', None)
        cancel.check()
        stage('composing', '正在按方框／多边形蒙版精确拼接整页，不进行程序排字。')
        output = composite(job, spec)
        if manage_gpu and image_phase:
            stage('restoring', '整页已拼接，正在恢复对话。', image=str(output))
            controller.chat();image_phase = False;manifest['gpu_restore_pending'] = False
        stage('done', '逐格生成与拼接完成。', image=str(output), elapsed_seconds=round(time.monotonic()-start, 2))
        return output
    except Exception as exc:
        restore_error = None
        if manage_gpu and image_phase:
            try:
                controller.assert_comfy_idle();controller.chat()
                manifest['gpu_restore_pending'] = False
            except Exception as restore:
                restore_error = str(restore)
        stage('cancelled' if isinstance(exc, RenderCancelled) else 'error', str(exc), error=str(exc), restore_error=restore_error)
        if isinstance(exc, RenderCancelled):
            exc.emitted = True
        raise
