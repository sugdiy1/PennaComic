"""Read-only MOSS API graph discovery, shared by import and render preparation."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re

SAVERS={'SaveImage','Save Image (LoraManager)'}
SAMPLERS={'KSampler','KSamplerAdvanced'}
LOADERS={'UNETLoader','Unet Loader (LoraManager)','UnetLoaderGGUF','CheckpointLoaderSimple'}
LORAS={'LoraLoader','LoraLoaderModelOnly','Power Lora Loader (rgthree)','Lora Loader (LoraManager)','LoRA Text Loader (LoraManager)'}
ENCODERS={'CLIPTextEncode':'text','Prompt (LoraManager)':'text'}

def is_link(v):
    return isinstance(v,list) and len(v)==2 and isinstance(v[0],str) and type(v[1]) is int

def graph_value(value):
    if isinstance(value,dict) and 'prompt' in value and isinstance(value['prompt'],dict):value=value['prompt']
    if not isinstance(value,dict) or not value or not all(isinstance(n,dict) and isinstance(n.get('class_type'),str) and isinstance(n.get('inputs'),dict) for n in value.values()):
        raise ValueError('请选择 API 格式工作流；普通界面 JSON 请先在 ComfyUI 中导出为 API 格式。')
    return value

def ancestors(graph,start):
    result=set();visiting=set()
    def visit(key):
        if key in visiting:raise ValueError('工作流存在循环连接，无法识别。')
        if key in result:return
        if key not in graph:raise ValueError('工作流引用了不存在的节点：'+str(key))
        visiting.add(key)
        for v in graph[key]['inputs'].values():
            if is_link(v):visit(v[0])
        visiting.remove(key);result.add(key)
    visit(start);return result

def model_chain(graph,sampler):
    chain=[];link=graph[sampler]['inputs'].get('model');seen=set()
    while is_link(link) and link[0] in graph:
        key=link[0]
        if key in seen:raise ValueError('模型链存在循环。')
        seen.add(key);node=graph[key];chain.append(key)
        if node['class_type'] in LOADERS:return chain,key
        link=node['inputs'].get('model')
    raise ValueError('未找到受支持的基础模型加载器；请检查模型链。')

def lora_entries(node):
    kind=node['class_type'];inputs=node['inputs'];result=[]
    def add(name,strength,clip=None,on=True):
        if not isinstance(name,str) or '{{' in name:return
        if not isinstance(strength,(int,float)) or not math.isfinite(strength):raise ValueError('LoRA 强度不是有效数字。')
        if clip is not None and (not isinstance(clip,(int,float)) or not math.isfinite(clip)):raise ValueError('LoRA CLIP 强度不是有效数字。')
        result.append({'name':name,'strength':strength,**({'clip_strength':clip} if clip is not None else {}),'enabled':bool(on and (strength!=0 or clip))})
    if kind in {'LoraLoader','LoraLoaderModelOnly'}:
        add(inputs.get('lora_name'),inputs.get('strength_model',0),inputs.get('strength_clip') if kind=='LoraLoader' else None)
    elif kind=='Power Lora Loader (rgthree)':
        for field,v in inputs.items():
            if field.startswith('lora_') and isinstance(v,dict):add(v.get('lora'),v.get('strength',0),v.get('strengthTwo'),v.get('on',True))
    elif kind in {'Lora Loader (LoraManager)','LoRA Text Loader (LoraManager)'}:
        text=inputs.get('text',inputs.get('lora_syntax',''))
        if not isinstance(text,str):raise ValueError('LoRA 管理器使用动态文本，请选择保留原工作流 LoRA。')
        for name,weight,clip in re.findall(r'<lora:([^:>]+):(-?[\d.]+)(?::(-?[\d.]+))?>',text):
            add(name,float(weight),float(clip) if clip else None)
        if text.strip() and not result:raise ValueError('无法读取 LoRA 管理器文本，请选择保留原工作流 LoRA。')
    else:raise ValueError('尚未适配的 LoRA 管理器：'+kind+'；可选择保留原工作流 LoRA。')
    return result

def inspect(graph,selection=None):
    graph=graph_value(graph);selection=selection or {};errors=[];warnings=[]
    result={'status':'needs_binding','bindings':dict(selection),'defaults':{},'loras':[],'warnings':warnings,'errors':errors}
    def choose(name,choices):
        value=selection.get(name)
        if value is not None and value not in choices:errors.append('绑定已失效，请重新选择：'+name);return None
        return value if value is not None else choices[0] if len(choices)==1 else None
    def choice(key,label=None):return {'id':key,'label':label or f'{key} · {graph[key].get("_meta",{}).get("title",graph[key]["class_type"])}'}
    outputs=[key for key,n in graph.items() if n['class_type'] in SAVERS]
    result['outputs']=[choice(key) for key in outputs];output=choose('output',outputs)
    if not output:errors.append('请选择最终出图节点；存在多个候选或没有 SaveImage。');return result
    result['bindings']['output']=output;active=ancestors(graph,output)
    samplers=[key for key in graph if key in active and graph[key]['class_type'] in SAMPLERS]
    moss=[]
    for key in samplers:
        try:
            _,root=model_chain(graph,key)
            name=str(graph[root]['inputs'].get('unet_name','')).lower()
            if 'moss' in name:moss.append(key)
        except ValueError:pass
    candidates=moss or samplers
    result['samplers']=[choice(key) for key in candidates];sampler=choose('sampler',candidates)
    if not sampler:errors.append('请选择用于 MOSS 出图的采样器。');return result
    result['bindings']['sampler']=sampler;sinputs=graph[sampler]['inputs']
    positive=sinputs.get('positive');negative=sinputs.get('negative')
    if not is_link(positive):errors.append('采样器没有连接正面条件。');return result
    positive_nodes=ancestors(graph,positive[0]);negative_nodes=ancestors(graph,negative[0]) if is_link(negative) else set()
    prompt_targets=[]
    for key in graph:
        if key not in positive_nodes:continue
        kind=graph[key]['class_type']
        if kind in ENCODERS:
            field=ENCODERS[kind]
            if key not in negative_nodes and field in graph[key]['inputs']:prompt_targets.append(key+'.'+field)
    if not prompt_targets:
        for key in graph:
            if key in positive_nodes and key not in negative_nodes:
                for field in ('text','prompt','value'):
                    if field in graph[key]['inputs'] and isinstance(graph[key]['inputs'][field],str):prompt_targets.append(key+'.'+field)
    result['positives']=[choice(key,key+' · '+graph[key.rsplit('.',1)[0]]['class_type']) for key in prompt_targets]
    target=choose('positive',prompt_targets)
    if not target:errors.append('请选择正面提示词入口；不会猜测修改负面提示词。');return result
    result['bindings']['positive']=target
    chain,root=model_chain(graph,sampler);result['model_root']=root;result['model_chain']=chain
    latent=sinputs.get('latent_image')
    latent_nodes=ancestors(graph,latent[0]) if is_link(latent) else set()
    sizes=[key for key in graph if key in latent_nodes and graph[key]['class_type'] in {'EmptyFlux2LatentImage','EmptySD3LatentImage','EmptyLatentImage'}]
    if len(sizes)!=1:errors.append('未找到唯一的空白画布尺寸节点；首版支持文生图工作流。');return result
    result['latent_node']=sizes[0]
    for field in ('steps','cfg','seed','noise_seed'):
        v=sinputs.get(field)
        if isinstance(v,str):
            match=re.fullmatch(r'\{\{[^:}]+:(-?[\d.]+)\}\}',v)
            if match:
                try:v=float(match[1]) if '.' in match[1] else int(match[1])
                except ValueError:pass
        if isinstance(v,(int,float)):result['defaults']['seed' if field=='noise_seed' else field]=v
    manage=selection.get('manage_loras',True)
    if type(manage) is not bool:raise ValueError('LoRA 管理模式无效。')
    result['bindings']['manage_loras']=manage
    lora_nodes=[key for key in reversed(chain) if 'lora' in graph[key]['class_type'].lower()]
    result['lora_nodes']=lora_nodes
    for key in lora_nodes:
        try:result['loras'].extend(dict(entry,node_id=key) for entry in lora_entries(graph[key]))
        except ValueError as error:
            if manage:errors.append(str(error))
            else:warnings.append(str(error))
    if manage:
        enabled=[]
        for e in result['loras']:
            if e['enabled']:
                if any(x['name']==e['name'] for x in enabled):errors.append('同一个 LoRA 在工作流中出现多次，请选择保留原工作流 LoRA。')
                enabled.append({k:v for k,v in e.items() if k in ('name','strength','clip_strength')})
        result['defaults']['loras']=enabled
    else:
        result['defaults']['loras']=[]
        warnings.append('保留原工作流 LoRA，Penna 多选列表不会替换它们。')
    if not errors:result['status']='ready'
    return result

def read(path,selection=None):
    file=Path(path)
    if not file.is_file() or file.stat().st_size>4*1024*1024:raise ValueError('工作流不存在或超过 4 MB。')
    raw=file.read_bytes();analysis=inspect(graph_value(json.loads(raw.decode('utf-8-sig'))),selection)
    return {'hash':hashlib.sha256(raw).hexdigest(),'defaults':analysis['defaults'],'inspection':analysis}

def prune(graph,output):
    keep=ancestors(graph,output)
    return {key:n for key,n in graph.items() if key in keep}

def configure(graph,analysis,prompt,width,height,seed,steps,cfg,loras):
    if analysis['status']!='ready':raise ValueError('工作流需要绑定：'+'；'.join(analysis['errors']))
    graph=copy.deepcopy(graph);binding=analysis['bindings'];sampler=binding['sampler']
    target,field=binding['positive'].rsplit('.',1);graph[target]['inputs'][field]=prompt
    graph[analysis['latent_node']]['inputs'].update(width=width,height=height,batch_size=1)
    inputs=graph[sampler]['inputs'];inputs.update(steps=steps,cfg=cfg)
    inputs['noise_seed' if graph[sampler]['class_type']=='KSamplerAdvanced' else 'seed']=seed
    if binding['manage_loras']:
        old=set(analysis['lora_nodes'])
        def bypass(link,seen=None):
            if not is_link(link) or link[0] not in old:return link
            seen=set() if seen is None else seen
            if link[0] in seen:raise ValueError('LoRA 链存在循环。')
            seen.add(link[0]);n=graph[link[0]];name='model' if link[1]==0 else 'clip' if link[1]==1 else None
            if name is None or not is_link(n['inputs'].get(name)):raise ValueError('LoRA 额外输出仍被使用；请保留原工作流 LoRA。')
            return bypass(n['inputs'][name],seen)
        for key,n in graph.items():
            if key not in old:
                for field,v in list(n['inputs'].items()):
                    if is_link(v):n['inputs'][field]=bypass(v)
        for key in old:graph.pop(key)
        root=analysis['model_root'];model=[root,0]
        # CLIP patches follow the same chosen LoRA stack, if requested.
        clip=None;link=graph[target]['inputs'].get('clip');seen=set()
        while is_link(link) and link[0] not in seen:
            seen.add(link[0]);n=graph[link[0]]
            if n['class_type']=='CLIPLoader':clip=link;break
            if n['class_type']=='CheckpointLoaderSimple':clip=[link[0],1];break
            link=n['inputs'].get('clip')
        new={};previous=model;previous_clip=clip
        for i,entry in enumerate(loras):
            key='12' if i==0 else f'relay_lora_{i+1}'
            while key in graph or key in new:key='penna_'+key
            inp={'model':previous,'lora_name':entry['name'],'strength_model':entry['strength']}
            if entry.get('clip_strength',0):
                if previous_clip is None:raise ValueError('当前正面入口没有可识别的 CLIP，无法应用 CLIP LoRA 强度。')
                inp.update(clip=previous_clip,strength_clip=entry['clip_strength']);kind='LoraLoader';previous_clip=[key,1]
            else:kind='LoraLoaderModelOnly'
            new[key]={'class_type':kind,'inputs':inp};previous=[key,0]
        if new:
            for n in graph.values():
                for field,v in list(n['inputs'].items()):
                    if v==model:n['inputs'][field]=previous
                    elif clip is not None and v==clip and previous_clip!=clip:n['inputs'][field]=previous_clip
            graph.update(new)
    return prune(graph,binding['output'])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--workflow',required=True);parser.add_argument('--selection',default='{}');args=parser.parse_args()
    try:print(json.dumps(read(args.workflow,json.loads(args.selection)),ensure_ascii=False))
    except (OSError,ValueError,KeyError,TypeError) as e:print(json.dumps({'error':str(e)},ensure_ascii=False));return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
