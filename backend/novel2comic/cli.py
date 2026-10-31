import argparse
import json
from pathlib import Path
import sys
from .config import Settings
from .pipeline import create_plan


def main(argv=None):
    for stream in (sys.stdout,sys.stderr):
        if hasattr(stream,'reconfigure'):
            stream.reconfigure(encoding='utf8')
    parser=argparse.ArgumentParser(description='novel2comic 框架阶段：离线解析小说并生成分镜计划。')
    commands=parser.add_subparsers(dest='command',required=True)
    run=commands.add_parser('run',aliases=['plan'],help='生成 page.json / manifest.json，不提交生图任务')
    run.add_argument('--input',required=True,type=Path)
    run.add_argument('--out',required=True,type=Path)
    run.add_argument('--plan-only',action='store_true',help='当前阶段始终为离线计划模式')
    run.add_argument('--style',choices=['mono','color','sketch'],default='mono')
    run.add_argument('--lora',default='')
    run.add_argument('--lora-strength',type=float,default=.85)
    run.add_argument('--pages-per-chapter',type=int,default=4)
    run.add_argument('--panels-per-page',type=int,choices=[4,5,6],default=4)
    run.add_argument('--width',type=int,default=1024)
    run.add_argument('--height',type=int,default=1536)
    run.add_argument('--seed',type=int,default=20261029)
    run.add_argument('--steps',type=int,default=50)
    run.add_argument('--cfg',type=float,default=3)
    run.add_argument('--comfy-url',default='http://127.0.0.1:8188',help='仅写入后续生成配置，不连接服务')
    run.add_argument('--json',action='store_true')
    doctor=commands.add_parser('doctor',help='仅检查本地文件，不连接 ComfyUI')
    doctor.add_argument('--json',action='store_true')
    render=commands.add_parser('render',help='后续阶段接通批量渲染（当前不可用）')
    render.add_argument('--out',type=Path,required=True)
    args=parser.parse_args(argv)
    try:
        if args.command=='render':
            parser.error('批量渲染尚未接通；本阶段仅搭建 Penna 工作区和离线分镜框架。')
        if args.command=='doctor':
            defaults=Settings().to_dict()
            result={'python':sys.executable,'workflow_exists':Path(defaults['workflow']).is_file(),
                    'mode':'offline','rendering_connected':False,'network_requests':0}
        else:
            settings=Settings(**{k:getattr(args,k) for k in ('style','lora','lora_strength','pages_per_chapter',
                              'panels_per_page','width','height','seed','steps','cfg','comfy_url')})
            result=create_plan(args.input,args.out,settings)
        if args.json:
            print(json.dumps(result,ensure_ascii=False))
        else:
            print(json.dumps({k:v for k,v in result.items() if k not in {'pages','settings','chapters'}},ensure_ascii=False,indent=2))
        return 0
    except (OSError,ValueError,RuntimeError) as exc:
        print(str(exc),file=sys.stderr)
        return 1
