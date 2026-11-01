"""Native Qwen 2.1 reference editing, shared by single-page and batch relay."""
import hashlib
import json
from pathlib import Path
import urllib.request
import uuid
from PIL import Image

DEFAULT_PROMPT = '只修正漫画中不自然的手指、手臂连接和肢体遮挡。保留人物身份、服装、动作、分格、气泡位置及全部原有中文台词，不增删或改写文字，保持原画风。'


def options(settings, width, height):
    mode = settings.get('render_mode', 'generate')
    if mode not in ('generate', 'generate_edit', 'edit_only'):
        raise ValueError('未知的出图模式。')
    if mode == 'generate':
        return {'render_mode': mode}, None
    prompt = settings.get('edit_prompt', DEFAULT_PROMPT)
    if mode != 'generate' and (not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 12000):
        raise ValueError('请填写有效的修改要求（最多 12000 字）。')
    steps = settings.get('edit_steps', 25)
    if not isinstance(steps, int) or not 1 <= steps <= 100:
        raise ValueError('修改步数应为 1–100。')
    reference = None
    if mode != 'generate' and (width % 32 or height % 32):
        raise ValueError('Qwen 修改要求画布宽高为 32 的倍数，避免尺寸被自动取整。')
    if mode == 'edit_only':
        reference = Path(str(settings.get('reference_image', '')))
        if not reference.is_file() or reference.stat().st_size > 32 * 1024**2:
            raise ValueError('请选择有效的漫画图片（不超过 32MB）。')
        with Image.open(reference) as image:
            image.verify()
        with Image.open(reference) as image:
            if image.format != 'PNG' or image.size != (width, height):
                raise ValueError('请选择与当前画布尺寸一致的 PNG 漫画页。')
    return {'render_mode': mode, 'edit_prompt': prompt, 'edit_steps': steps}, reference


def attach(workflow, config, seed, prefix):
    mode = config['render_mode']
    if mode == 'generate':
        return workflow
    if mode == 'edit_only':
        workflow = {'qwen_reference': {'class_type': 'LoadImage', 'inputs': {'image': 'penna-reference-pending.png'}}}
        reference = ['qwen_reference', 0]
    else:
        reference = ['9', 0]
        workflow['moss_reference'] = {'class_type': 'SaveImage', 'inputs': {'images': reference, 'filename_prefix': prefix + '-moss'}}
    workflow.update({
        'qwen_unet': {'class_type':'UNETLoader','inputs':{'unet_name':'qwen-image-2.1-UC-int8_convrot.safetensors','weight_dtype':'default'}},
        'qwen_clip': {'class_type':'CLIPLoader','inputs':{'clip_name':'qwen3vl_8b_int8_convrot.safetensors','type':'qwen_image','device':'default'}},
        'qwen_vae': {'class_type':'VAELoader','inputs':{'vae_name':'qwen_image_2.1_vae_bf16.safetensors'}},
        'qwen_encode': {'class_type':'TextEncodeQwenImage21','inputs':{'clip':['qwen_clip',0],'vae':['qwen_vae',0],'images.image_1':reference,'prompt':config['edit_prompt'],'negative_prompt':'','resolution':0}},
        'qwen_cache': {'class_type':'QwenImage21Cache','inputs':{'model':['qwen_unet',0],'device':'cpu','dtype':'default'}},
        'qwen_sampler': {'class_type':'KSampler','inputs':{'model':['qwen_cache',0],'positive':['qwen_encode',0],'negative':['qwen_encode',1],'latent_image':['qwen_encode',2],'seed':seed,'steps':config['edit_steps'],'cfg':1.0,'sampler_name':'euler','scheduler':'simple','denoise':1.0}},
        'qwen_decode': {'class_type':'VAEDecode','inputs':{'samples':['qwen_sampler',0],'vae':['qwen_vae',0]}},
        '11': {'class_type':'SaveImage','inputs':{'images':['qwen_decode',0],'filename_prefix':prefix+'-edited'}},
    })
    return workflow


def upload_reference(job, url):
    data = (job/'reference.png').read_bytes()
    name = 'penna-' + hashlib.sha256(data).hexdigest() + '.png'
    boundary = 'penna' + uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\nContent-Type: image/png\r\n\r\n'.encode() + data + f'\r\n--{boundary}--\r\n'.encode())
    req = urllib.request.Request(url+'/upload/image', data=body, headers={'Content-Type':'multipart/form-data; boundary='+boundary})
    with urllib.request.urlopen(req, timeout=60) as response:
        result = json.load(response)
    folder = result.get('subfolder', '')
    return (folder+'/' if folder else '') + result['name']
