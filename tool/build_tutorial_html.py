"""Build an offline illustrated manual from the checked-in Markdown and PNGs."""
from pathlib import Path
import base64
import html
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'docs/图文操作教程.md'
OUTPUT = ROOT / 'docs/图文操作教程.html'


def inline(text):
    text = html.escape(text)
    text = re.sub(r'`([^`]+)`', lambda m: '<code>'+m[1]+'</code>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    return text


def build():
    lines = SOURCE.read_text(encoding='utf-8').splitlines()
    body, toc, paragraph = [], [], []
    listing = None
    images = []

    def flush():
        nonlocal listing
        if paragraph:
            body.append('<p>'+inline(' '.join(paragraph))+'</p>')
            paragraph.clear()
        if listing:
            body.append('</'+listing+'>')
            listing = None

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            flush()
        elif line.startswith('```'):
            flush()
            code = []
            i += 1
            while i < len(lines) and not lines[i].startswith('```'):
                code.append(lines[i])
                i += 1
            body.append('<pre><code>'+html.escape('\n'.join(code))+'</code></pre>')
        elif line.startswith('#'):
            flush()
            level = len(line)-len(line.lstrip('#'))
            title = line[level:].strip()
            anchor = 'title' if level == 1 else 'section-'+str(len(toc)+1)
            if level == 2:
                toc.append((anchor, title))
            body.append(f'<h{level} id="{anchor}">{inline(title)}</h{level}>')
        elif line.startswith('!['):
            flush()
            match = re.fullmatch(r'!\[([^]]*)\]\(([^)]+)\)', line)
            if not match:
                raise ValueError('Invalid image: '+line)
            alt, relative = match.groups()
            path = (SOURCE.parent/relative).resolve()
            assert path.is_relative_to((ROOT/'docs/images').resolve())
            data = base64.b64encode(path.read_bytes()).decode('ascii')
            images.append(relative)
            body.append(f'<figure><img src="data:image/png;base64,{data}" alt="{html.escape(alt)}"><figcaption>{inline(alt)}</figcaption></figure>')
        elif line.startswith('|'):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [s.strip() for s in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?', cell) for cell in cells):
                    tag = 'th' if not rows else 'td'
                    rows.append('<tr>'+''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells)+'</tr>')
                i += 1
            body.append('<div class="table"><table>'+''.join(rows)+'</table></div>')
            continue
        elif re.match(r'^(\d+\. |[-] )', line):
            if paragraph:
                flush()
            kind = 'ul' if line.startswith('- ') else 'ol'
            if listing != kind:
                flush()
                body.append('<'+kind+'>')
                listing = kind
            body.append('<li>'+inline(re.sub(r'^(\d+\. |[-] )', '', line))+'</li>')
        else:
            if listing:
                flush()
            paragraph.append(line)
        i += 1
    flush()
    nav = ''.join(f'<a href="#{anchor}">{html.escape(title)}</a>' for anchor,title in toc)
    css = '''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f5f6f8;color:#1c2738;font:17px/1.85 "Microsoft YaHei","Noto Sans CJK SC",sans-serif}nav{position:fixed;width:245px;inset:0 auto 0 0;overflow:auto;padding:26px 18px;background:#fff;border-right:1px solid #dce2ec}nav a{display:block;color:#415575;text-decoration:none;font-size:13px;line-height:1.6;padding:7px 0}nav strong{display:block;margin-bottom:16px;font-size:21px}main{margin-left:245px;padding:45px 4vw;max-width:1500px}article{padding:34px 40px;background:#fff;border:1px solid #dce2ec;border-radius:14px}h1{font-size:34px;line-height:1.4}h2{font-size:25px;margin-top:52px;border-top:1px solid #e1e7ef;padding-top:25px;scroll-margin-top:15px}p{margin:14px 0}li{margin:8px 0}code{font:14px/1.6 Consolas,monospace;overflow-wrap:anywhere;background:#f0f3f8;padding:2px 5px;border-radius:4px}pre{padding:18px;background:#eef2f8;white-space:pre-wrap;border-radius:9px}pre code{padding:0}figure{margin:28px 0}img{display:block;width:100%;height:auto;border:1px solid #cfd8e6;border-radius:6px;cursor:zoom-in}figcaption{font-size:14px;color:#5a6d88;margin:8px 0;text-align:center}.table{overflow:auto}table{border-collapse:collapse;width:100%;font-size:15px}th,td{border:1px solid #d9e2ef;padding:11px 13px;text-align:left;vertical-align:top}th{background:#edf2fa}button{background:#285de6;color:#fff;border:0;border-radius:7px;padding:10px 15px;cursor:pointer;font:inherit;font-size:14px}.badge{font-size:14px;color:#5b6b83}dialog{border:0;padding:10px;max-width:98vw;max-height:97vh}dialog img{width:auto;max-width:95vw;max-height:91vh;object-fit:contain}dialog::backdrop{background:#14243dcc}@media(max-width:850px){nav{position:static;width:auto;max-height:260px}main{margin:0;padding:15px}article{padding:20px}h1{font-size:27px}}@media print{body{background:#fff;font-size:11pt;line-height:1.6}nav,button,dialog{display:none}main{margin:0;padding:0;max-width:none}article{border:0;padding:0}h2{break-before:page;font-size:18pt}figure,pre,tr{break-inside:avoid}img{max-height:215mm;object-fit:contain}figcaption{font-size:9pt}table{font-size:10pt}a{color:inherit}h1{font-size:25pt}@page{size:A4;margin:16mm}}'''
    shot_count = sum(path.startswith('images/tutorial/') for path in images)
    document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PennaComic .9 全功能图文教程</title><style>'+css+'</style><nav><strong>PennaComic</strong><div class="badge">.9 版 · 离线全功能教程<br>'+str(shot_count)+' 张界面截图＋历史样张</div>'+nav+'</nav><main><article><button onclick="window.print()">打印 / 另存为 PDF</button>'+''.join(body)+'</article></main><dialog id="viewer"><button onclick="this.parentElement.close()">关闭大图</button><img alt="放大截图"></dialog><script>document.querySelectorAll("figure img").forEach(img=>img.onclick=()=>{let d=document.getElementById("viewer");d.querySelector("img").src=img.src;d.showModal()});</script></html>'
    OUTPUT.write_text(document,encoding='utf-8')
    print(f'{OUTPUT}: {len(toc)} sections, {len(images)} embedded images, {OUTPUT.stat().st_size} bytes')


if __name__ == '__main__':
    build()
