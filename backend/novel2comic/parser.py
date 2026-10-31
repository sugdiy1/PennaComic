"""TXT/EPUB parsing without extraction, network access, or third-party parsers."""
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
import posixpath
import re
import xml.etree.ElementTree as ET
import zipfile

NUM = r'零〇一二三四五六七八九十百千万两\d０-９'
VOLUME = re.compile(rf'^第[{NUM}]+[卷部集](?:\s|[：:『「《]|$)')
CHAPTER = re.compile(rf'^(?:第[{NUM}]+[章节回幕]|序章|序幕|楔子|终章|尾声|幕间|間章|间章|番外|序言)(?:\s|[：:『「《]|$)')
BACK = re.compile(r'^(?:后记|後記|插图|插圖|彩页|目录|目錄|版权|版權|作者的话|制作信息|致谢|Contents|Acknowledg)', re.I)
CREDITS = re.compile(r'^(?:台版\s*转自|天使动漫录入组|图源[：:]|录入[：:]|校对[：:]|轻之国度|本书由)')


@dataclass
class Chapter:
    title: str
    volume: str
    text: str
    source: str = ''
    index: int = 0


@dataclass
class Book:
    title: str
    chapters: list[Chapter] = field(default_factory=list)
    source: str = ''


class Blocks(HTMLParser):
    """Preserve line/heading boundaries, ignoring nav, ruby readings and scripts."""
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.buf = []
        self.heading = ''
        self.hidden = 0

    def flush(self):
        value = re.sub(r'[\t \xa0\u3000]+', ' ', ''.join(self.buf)).strip()
        if value:
            self.blocks.append((self.heading or 'text', value))
        self.buf.clear()

    def handle_starttag(self, tag, attrs):
        if tag in {'head', 'nav', 'script', 'style', 'rt'}:
            self.hidden += 1
        if self.hidden:
            return
        if tag in {'p', 'div', 'br', 'li', 'section', 'h1', 'h2', 'h3', 'h4', 'h5'}:
            self.flush()
        if tag in {'h1', 'h2', 'h3', 'h4', 'h5'}:
            self.heading = tag

    def handle_endtag(self, tag):
        if tag in {'head', 'nav', 'script', 'style', 'rt'}:
            self.hidden = max(0, self.hidden - 1)
            return
        if self.hidden:
            return
        if tag in {'p', 'div', 'li', 'section', 'h1', 'h2', 'h3', 'h4', 'h5'}:
            self.flush()
        if tag in {'h1', 'h2', 'h3', 'h4', 'h5'}:
            self.heading = ''

    def handle_data(self, data):
        if not self.hidden:
            # HTML whitespace is not a paragraph boundary.
            self.buf.append(data.replace('\r', '').replace('\n', ' '))


def decode_text(data):
    for enc in ('utf-8-sig', 'utf-16' if data[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8', 'gb18030'):
        try:
            return data.decode(enc)
        except UnicodeError:
            pass
    raise ValueError('文本编码无法识别；请将小说转为 UTF-8。')


def _collect(book, documents):
    volume = '第一卷'
    title = ''
    lines = []
    origin = ''
    skip = False

    def commit():
        nonlocal lines
        text = '\n'.join(lines).strip()
        if text and not skip:
            book.chapters.append(Chapter(title or '正文', volume, text, origin, len(book.chapters) + 1))
        lines = []

    for source, blocks in documents:
        # Each spine document can be a chapter even if it lacks a heading.
        if lines:
            commit()
        title, skip, origin = '', False, source
        for kind, value in blocks:
            value = value.strip('\ufeff \t\r\n\xa0\u3000')
            if not value or CREDITS.match(value):
                continue
            is_heading = kind.startswith('h') or bool(CHAPTER.match(value) or VOLUME.match(value))
            if is_heading and VOLUME.match(value):
                commit()
                volume, title, skip = value, '', False
            elif is_heading and BACK.match(value):
                commit()
                title, skip = value, True
            elif is_heading:
                commit()
                title, skip = value, False
            elif not skip:
                lines.append(value)
        commit()
    if not book.chapters:
        raise ValueError('未发现可用正文（目录、后记和纯插图已排除）。')
    return book


def read_book(path: Path) -> Book:
    path = Path(path).resolve()
    if path.suffix.lower() == '.txt':
        lines = decode_text(path.read_bytes()).splitlines()
        first = next((s.strip() for s in lines if s.strip()), '')
        title = path.stem
        if first and len(first) <= 60 and not (CHAPTER.match(first) or VOLUME.match(first)):
            title = first
            lines = lines[lines.index(next(s for s in lines if s.strip())) + 1:]
        return _collect(Book(title, source=str(path)), [(str(path), [('text', s) for s in lines])])
    if path.suffix.lower() != '.epub':
        raise ValueError('输入必须是 .txt 或 .epub。')
    with zipfile.ZipFile(path) as z:
        container = ET.fromstring(z.read('META-INF/container.xml'))
        opf = next(e.attrib['full-path'] for e in container.iter() if e.tag.split('}')[-1] == 'rootfile')
        package = ET.fromstring(z.read(opf))
        title = next((e.text.strip() for e in package.iter() if e.tag.split('}')[-1] == 'title' and e.text), path.stem)
        manifest = {e.attrib['id']: e.attrib for e in package.iter() if e.tag.split('}')[-1] == 'item'}
        documents = []
        for ref in package.iter():
            if ref.tag.split('}')[-1] != 'itemref' or ref.get('linear') == 'no':
                continue
            item = manifest.get(ref.get('idref'), {})
            if 'nav' in item.get('properties', '').split() or item.get('media-type') not in {'application/xhtml+xml', 'text/html'}:
                continue
            name = posixpath.normpath(posixpath.join(posixpath.dirname(opf), unquote(item['href'].split('#')[0])))
            html = Blocks()
            html.feed(decode_text(z.read(name)))
            html.flush()
            documents.append((name, html.blocks))
        return _collect(Book(title, source=str(path)), documents)
