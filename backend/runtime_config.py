"""Shared configuration for the Windows portable distribution."""
import json
import os
from pathlib import Path
from urllib.parse import urlparse


class RuntimeConfig:
    def __init__(self, path=None, bundle_root=None):
        self.home = Path(os.environ.get('PENNA_HOME') or (Path(os.environ.get('APPDATA', Path.home())) / 'PennaComic')).resolve()
        self.path = Path(path or os.environ.get('PENNA_INTEGRATION') or self.home / 'integration.json').resolve()
        self.bundle = Path(bundle_root or os.environ.get('PENNA_BUNDLE_ROOT') or Path(__file__).resolve().parent.parent).resolve()
        try:
            self.data = json.loads(self.path.read_text(encoding='utf-8-sig')) if self.path.exists() else {}
            if not isinstance(self.data, dict):
                raise ValueError('Expected object')
        except (OSError, ValueError) as exc:
            raise ValueError(f'integration.json 无法读取：{exc}') from exc
        self.mode = self.data.get('mode', 'external')
        if self.mode not in ('external', 'managed'):
            raise ValueError('mode 必须为 external 或 managed')
        self.comfy_url = self.url('comfy_url', 'http://127.0.0.1:8188')
        self.llm_url = self.url('llm_url', 'http://127.0.0.1:8090')
        self.output = self.file('output', str(self.home / 'renders'))
        self.workflow = self.file('workflow', str(self.bundle / 'workflows/moss-api.json'))
        self.state = self.home / 'controller'
        self.llama_executable = self.file('llama_executable', '')
        self.llama_model = self.file('llama_model', '')
        self.llama_args = self.data.get('llama_args', [])
        if not isinstance(self.llama_args, list) or not all(isinstance(x, str) for x in self.llama_args):
            raise ValueError('llama_args 必须为字符串数组')

    def file(self, key, default):
        raw = self.data.get(key, default)
        if not isinstance(raw, str):
            raise ValueError(f'{key} 必须为字符串')
        raw = raw.strip() or default
        p = Path(raw).expanduser()
        return (p if p.is_absolute() else self.path.parent / p).resolve()

    def url(self, key, default):
        raw = self.data.get(key, default)
        if not isinstance(raw, str):
            raise ValueError(f'{key} 必须为网址')
        parsed = urlparse(raw)
        if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError(f'{key} 需要不含密码、查询参数的 HTTP(S) 地址')
        return raw.rstrip('/')


CONFIG = RuntimeConfig()
