"""Read-only setup checks; never submits a prompt or changes GPU mode."""
import importlib.util
import json
import urllib.request
from pathlib import Path
from runtime_config import CONFIG


def check():
    results = []
    def add(name, ok, message):
        results.append({'check': name, 'ok': bool(ok), 'message': message})
    for name in ('PIL', 'psutil'):
        add(name, importlib.util.find_spec(name) is not None, f'Python依赖 {name}')
    add('workflow', CONFIG.workflow.is_file(), str(CONFIG.workflow))
    add('chinese_font', (CONFIG.bundle / 'font/LXGW975YuanSC-500W.ttf').is_file(), '随包中文排字字体')
    try:
        graph = json.loads(CONFIG.workflow.read_text(encoding='utf-8-sig'))
        import penna_relay
        penna_relay.validate_workflow(graph)
        req = urllib.request.Request(CONFIG.comfy_url + '/object_info')
        with urllib.request.urlopen(req, timeout=8) as response:
            info = json.load(response)
        missing = sorted({n['class_type'] for n in graph.values()} - info.keys())
        add('comfy_nodes', not missing, '缺少节点：' + ', '.join(missing) if missing else '工作流节点均存在')
        for node in graph.values():
            fields = {'UNETLoader': 'unet_name', 'CLIPLoader': 'clip_name', 'VAELoader': 'vae_name'}
            field = fields.get(node['class_type'])
            if not field or node['class_type'] not in info:
                continue
            raw = node['inputs'][field]
            if raw.startswith('{{') and ':' in raw:
                raw = raw.split(':', 1)[1][:-2]
            choices = info[node['class_type']]['input']['required'][field][0]
            add(field, raw in choices, raw)
    except Exception as exc:
        add('comfy', False, str(exc))
    ancestor = CONFIG.output
    while not ancestor.exists() and ancestor.parent != ancestor:
        ancestor = ancestor.parent
    import os
    add('output', os.access(ancestor, os.W_OK), str(CONFIG.output))
    add('mode', True, CONFIG.mode + ('：由用户管理模型服务' if CONFIG.mode == 'external' else '：仅管理本程序启动的进程'))
    return results


if __name__ == '__main__':
    checks = check()
    print(json.dumps(checks, ensure_ascii=False))
    raise SystemExit(0 if all(x['ok'] for x in checks) else 1)
