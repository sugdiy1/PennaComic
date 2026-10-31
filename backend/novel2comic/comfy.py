"""Serial ComfyUI API jobs with persisted prompt IDs, bounded retries and PNG validation."""
import io
import json
from pathlib import Path
import re
import time
from urllib import request, parse, error
from PIL import Image
from .storage import atomic_bytes, digest, file_digest, read_json, write_json

TOKEN=re.compile(r'\{\{([a-zA-Z_][\w]*)(?::([^}]*))?\}\}')


def fill_workflow(value,params):
    if isinstance(value,dict):
        return {k:fill_workflow(v,params) for k,v in value.items()}
    if isinstance(value,list):
        return [fill_workflow(v,params) for v in value]
    if not isinstance(value,str):
        return value
    def get(match):
        name,default=match.groups()
        if name in params:
            return params[name]
        if default is not None:
            try:
                return json.loads(default)
            except json.JSONDecodeError:
                return default
        raise ValueError(f'工作流缺少参数：{name}')
    full=TOKEN.fullmatch(value)
    return get(full) if full else TOKEN.sub(lambda m:str(get(m)),value)


def valid_png(path,expected=None,sha=None):
    try:
        path=Path(path)
        if sha and file_digest(path)!=sha:
            return False
        with Image.open(path) as im:
            if im.format!='PNG' or (expected and im.size!=tuple(expected)):
                return False
            im.verify()
        return True
    except (OSError,ValueError,Image.DecompressionBombError):
        return False


class ExecutionFailed(RuntimeError):
    pass


class JobPending(RuntimeError):
    """A known request must be resumed instead of submitted a second time."""


class ComfyClient:
    def __init__(self,base='http://127.0.0.1:8188',timeout=1800,poll=2,log=print):
        self.base=base.rstrip('/')
        self.timeout=timeout
        self.poll=poll
        self.log=log
        # Loopback requests must not be routed through system HTTP proxies.
        self.opener=request.build_opener(request.ProxyHandler({}))

    def http(self,path,data=None):
        payload=json.dumps(data,ensure_ascii=False).encode('utf8') if data is not None else None
        req=request.Request(self.base+path,data=payload,headers={'Content-Type':'application/json'})
        try:
            with self.opener.open(req,timeout=30) as response:
                raw=response.read()
        except error.HTTPError as exc:
            raise ExecutionFailed(f'HTTP {exc.code} {path}: {exc.read().decode("utf8",errors="replace")[:3000]}') from exc
        return json.loads(raw) if not path.startswith('/view?') else raw

    def preflight(self,graph):
        stats=self.http('/system_stats')
        needed={n['class_type'] for n in graph.values()}
        for kind in needed:
            info=self.http('/object_info/'+parse.quote(kind,safe='')).get(kind)
            if info is None:
                raise ValueError(f'ComfyUI 缺少节点：{kind}')
            for node in graph.values():
                if node['class_type']!=kind:
                    continue
                required=info.get('input',{}).get('required',{})
                for key in ('unet_name','clip_name','vae_name','lora_name'):
                    if key in node['inputs'] and key in required:
                        choices=required[key][0]
                        if isinstance(choices,list) and node['inputs'][key] not in choices:
                            raise ValueError(f'未找到已安装模型 {key}={node["inputs"][key]}；不会自动下载。')
        return stats

    def _recover_submission(self,client_id):
        queue=self.http('/queue')
        for row in queue.get('queue_running',[])+queue.get('queue_pending',[]):
            if len(row)>3 and row[3].get('client_id')==client_id:
                return row[1]
        history=self.http('/history?max_items=200')
        for pid,record in history.items():
            row=record.get('prompt',[])
            if len(row)>3 and row[3].get('client_id')==client_id:
                return pid
        return None

    def _wait(self,pid):
        start=time.monotonic()
        errors=0
        while time.monotonic()-start<self.timeout:
            try:
                history=self.http('/history/'+parse.quote(pid,safe=''))
                errors=0
            except (OSError,ExecutionFailed,ValueError):
                errors+=1
                if errors==1 or errors%15==0:
                    self.log(f'  查询暂不可用，保留任务 {pid}，等待恢复')
                time.sleep(self.poll)
                continue
            if pid in history:
                record=history[pid]
                status=record.get('status',{})
                messages=status.get('messages',[])
                failures=[m for m in messages if m[0] in {'execution_error','execution_interrupted'}]
                if status.get('status_str')=='error' or failures:
                    raise ExecutionFailed(json.dumps(failures or status,ensure_ascii=False)[:3000])
                images=[i for out in record.get('outputs',{}).values() for i in out.get('images',[]) if i.get('type','output')=='output']
                if images:
                    return images[-1]
                raise ExecutionFailed(f'任务 {pid} 已结束但没有输出图片。')
            time.sleep(self.poll)
        raise JobPending(f'任务 {pid} 在 {self.timeout}s 内未结束；ID 已保存，下次 run 将继续查询，不重复提交。')

    def render(self,graph,dest,state_path,retries=2):
        dest,state_path=Path(dest),Path(state_path)
        fingerprint=digest(graph)
        state=read_json(state_path,{})
        if state.get('fingerprint')!=fingerprint:
            if state.get('status') in {'running','submission_unknown'}:
                raise JobPending(f'旧配置任务仍待确认：{state_path}。先用原参数恢复该任务。')
            state={'fingerprint':fingerprint,'status':'pending','attempts':[],'elapsed_seconds':0}
        if state.get('status')=='complete' and valid_png(dest,sha=state.get('sha256')):
            return state,True
        # Failed jobs can be retried by another explicit run, with another bounded batch.
        last_error=None
        for _ in range(retries+1):
            started=time.monotonic()
            pid=state.get('prompt_id')
            try:
                if state.get('status')=='submission_unknown':
                    pid=self._recover_submission(state['client_id'])
                    if not pid:
                        raise JobPending('上次提交的响应丢失，队列/最近历史中暂未找到；为避免重复出图，保留记录并停止。')
                    state['prompt_id']=pid
                    state['status']='running'
                    write_json(state_path,state)
                if not pid:
                    client_id='n2c-'+digest([fingerprint,str(state_path),len(state['attempts'])])[:32]
                    state.update(status='submission_unknown',client_id=client_id)
                    state['attempts'].append({'number':len(state['attempts'])+1,'started_at':time.time()})
                    write_json(state_path,state)
                    try:
                        response=self.http('/prompt',{'prompt':graph,'client_id':client_id})
                    except OSError as exc:
                        raise JobPending('提交连接中断，任务可能已接收；已保存 client_id，下次恢复时查询队列。') from exc
                    pid=response['prompt_id']
                    state.update(prompt_id=pid,status='running')
                    state['attempts'][-1]['prompt_id']=pid
                    write_json(state_path,state)
                    self.log(f'  queued {pid}')
                image=self._wait(pid)
                query=parse.urlencode({k:image.get(k,'output' if k=='type' else '') for k in ('filename','subfolder','type')})
                raw=self.http('/view?'+query)
                with Image.open(io.BytesIO(raw)) as im:
                    if im.format!='PNG':
                        raise ExecutionFailed('ComfyUI 返回的图片不是 PNG。')
                    im.verify()
                atomic_bytes(dest,raw)
                state.update(status='complete',sha256=file_digest(dest),bytes=len(raw))
                state['elapsed_seconds']+=round(time.monotonic()-started,3)
                state['attempts'][-1]['status']='complete'
                write_json(state_path,state)
                return state,False
            except JobPending:
                state['elapsed_seconds']+=round(time.monotonic()-started,3)
                write_json(state_path,state)
                raise
            except (ExecutionFailed,OSError,ValueError,KeyError) as exc:
                last_error=str(exc)
                state['elapsed_seconds']+=round(time.monotonic()-started,3)
                state['error']=last_error
                if state.get('attempts'):
                    state['attempts'][-1]['error']=last_error
                    state['attempts'][-1]['status']='failed'
                # If history says execution failed, submit a new job. A failed download
                # retains the known ID and retries retrieving its existing output.
                if isinstance(exc,ExecutionFailed) and not str(exc).startswith('HTTP 5'):
                    state.pop('prompt_id',None)
                state['status']='failed'
                write_json(state_path,state)
                self.log('  retry/error: '+last_error[:260])
                if _<retries:
                    time.sleep(min(2**_,4))
        raise ExecutionFailed(f'初次加 {retries} 次重试仍失败：{last_error}')
