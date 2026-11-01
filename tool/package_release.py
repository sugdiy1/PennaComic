"""Whitelist packaging. No installed user data, runtimes or models are copied."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
from pathlib import PurePosixPath
import zipfile

ROOT = Path(__file__).resolve().parent.parent
EXCLUDED = {'ephemeral', '__pycache__', '.git', '.dart_tool', 'build', 'dist', 'release', 'superpowers', 'control'}
TOP_FILES = {'README.md', 'LICENSE', 'NOTICE.md', 'CHANGELOG.md', 'CONTRIBUTING.md', '.gitignore', '.metadata', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'integration.example.json'}
SOURCE_DIRS = {'lib', 'windows', 'font', 'assets', 'backend', 'workflows', 'test', 'tool', '.github', 'docs'}
DENIED = {'keys.dat', 'config.json', 'integration.json', 'server-state.json', 'workspace.json', 'layout.json', 'layout_chat.json', 'snapshot.json', 'manifest.json', 'relay-settings.json', 'connection.json', 'server.lock', 'tasks.json'}


def source_files(root=ROOT):
    for p in root.rglob('*'):
        rel = p.relative_to(root)
        if not p.is_file() or p.is_symlink() or not p.resolve().is_relative_to(root.resolve()) or any(x in EXCLUDED for x in rel.parts):
            continue
        if p.name.casefold() in DENIED or p.suffix.lower() in {'.gguf', '.safetensors', '.log', '.pyc', '.bak', '.original', '.tmp'}:
            continue
        if rel.parts[0] in SOURCE_DIRS or (len(rel.parts) == 1 and p.name in TOP_FILES):
            yield p, rel.as_posix()


def write_package(files, out):
    entries = list(files)
    seen = set()
    for _, name in entries:
        rel = PurePosixPath(name)
        if not name or "\\" in name or ":" in name or rel.is_absolute() or any(part in ("", ".", "..") for part in name.split("/")):
            raise ValueError(f'Unsafe archive path: {name}')
        key = name.casefold()
        if key in seen or key == 'package-manifest.json':
            raise ValueError(f'Duplicate archive path: {name}')
        seen.add(key)
    out.parent.mkdir(parents=True, exist_ok=True)
    sidecar = out.with_suffix(out.suffix + '.sha256')
    if out.exists() or sidecar.exists():
        raise ValueError('Output already exists; choose a new file name')
    manifest = []
    with tempfile.TemporaryDirectory(prefix='.penna-package-', dir=out.parent) as temp:
        staged = Path(temp) / out.name
        with zipfile.ZipFile(staged, 'w', zipfile.ZIP_DEFLATED) as z:
            for path, name in sorted(entries, key=lambda x: x[1]):
                data = path.read_bytes()
                if path.suffix.lower() in {'.dart', '.py', '.json', '.yml', '.yaml', '.md', '.ps1'}:
                    body = data.decode('utf-8-sig')
                    if re.search(r'(?:ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{32,})', body):
                        raise ValueError(f'Credential-like text in {name}; review before publishing')
                manifest.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
                z.writestr(name, data)
            z.writestr('PACKAGE-MANIFEST.json', json.dumps(manifest, indent=2))
        digest = hashlib.sha256(staged.read_bytes()).hexdigest()
        staged_sidecar = Path(temp) / sidecar.name
        staged_sidecar.write_text(f'{digest}  {out.name}\n', encoding='ascii')
        if out.exists() or sidecar.exists():
            raise ValueError('Output appeared during packaging; choose a new file name')
        staged.rename(out)
        staged_sidecar.rename(sidecar)
    return {'file': str(out), 'files': len(entries), 'bytes': out.stat().st_size, 'sha256': digest}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('kind', choices=['source', 'windows'])
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--release-dir', type=Path)
    args = p.parse_args()
    files = list(source_files())
    if args.kind == 'windows':
        release = args.release_dir
        if not release or not (release / 'penna.exe').is_file() or not (release / 'data/app.so').is_file():
            p.error('Provide a complete fresh Flutter release directory')
        files = [(f, n) for f, n in files if n.split('/')[0] in {'backend', 'workflows', 'font'} or n in {'README.md', 'NOTICE.md', 'LICENSE', 'integration.example.json', 'docs/VALIDATION.md', 'docs/DSH-MCP.md', 'docs/MOSS-QWEN.md'}]
        files = [(f, n) for f, n in files if not n.startswith('backend/test_')]
        for f in release.rglob('*'):
            if f.is_file() and not f.is_symlink():
                rel = f.relative_to(release)
                if rel.parts[0] == 'data' or (len(rel.parts) == 1 and f.suffix in {'.exe', '.dll'}):
                    files.append((f, rel.as_posix()))
    print(json.dumps(write_package(files, args.out), ensure_ascii=False))


if __name__ == '__main__':
    main()
