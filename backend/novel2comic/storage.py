"""Atomic local artifacts, content digests, and a kernel-released process lock."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path


def digest(value):
    if not isinstance(value, bytes):
        value=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf8')
    return hashlib.sha256(value).hexdigest()


def file_digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):
            h.update(chunk)
    return h.hexdigest()


def atomic_bytes(path,data):
    path=Path(path)
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    with tmp.open('wb') as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp,path)


def write_json(path,data):
    atomic_bytes(path,(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf8'))


def read_json(path,default=None):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except FileNotFoundError:
        return default


def safe_name(value):
    import re
    value=re.sub(r'[<>:"/\\|?*\x00-\x1f]','_',value).strip(' .')[:100] or '未命名'
    if re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?',value,re.I):
        value='_'+value
    return value


@contextmanager
def output_lock(root):
    root=Path(root)
    root.mkdir(parents=True,exist_ok=True)
    with (root/'.novel2comic.lock').open('a+b') as f:
        f.seek(0)
        if f.read(1)==b'':
            f.write(b'0')
            f.flush()
        f.seek(0)
        try:
            if os.name=='nt':
                import msvcrt
                msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
            else:
                import fcntl
                fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except OSError as exc:
            raise RuntimeError('该输出目录已有 novel2comic 进程运行。') from exc
        try:
            yield
        finally:
            f.seek(0)
            if os.name=='nt':
                msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
            else:
                fcntl.flock(f,fcntl.LOCK_UN)
