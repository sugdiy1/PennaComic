"""Deterministic scene-aware compression; every word of dialogue has a source."""
import math
import re

WORDS = ['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX']
CAMERAS = ['wide', 'medium', 'close', 'low']
SHOT = {'wide': 'wide establishing shot, environment and small human figures',
        'medium': 'waist-up medium shot, readable gestures and interaction',
        'close': 'close-up, one expressive face, eyes and expression in focus',
        'low': 'low-angle dramatic shot, strong perspective and motion'}
DIALOGUE = re.compile(r'[「“]([^」”]+)[」”]')
SCENE_BREAK = re.compile(r'^(?:[\d０-９]{1,3}|[＊*◇◆☆★]{2,}|[—─-]{3,})$|^(?:与此同时|翌日|次日|第二天|另一边|片刻后|数日后|当晚)')


def paragraphs(text):
    return [s.strip() for s in text.splitlines() if s.strip() and not re.fullmatch(r'[\d０-９]{1,3}', s.strip())]


def split_groups(lines, n):
    """Contiguous groups near equal text size, preferring real scene boundaries."""
    if not lines:
        return [[] for _ in range(n)]
    if len(lines) < n:
        return [[lines[min(i, len(lines) - 1)]] for i in range(n)]
    weights = [len(s) for s in lines]
    groups, start = [], 0
    for i in range(n - 1):
        remaining = n - i
        target = sum(weights[start:]) / remaining
        total, candidates = 0, []
        for end in range(start + 1, len(lines) - remaining + 2):
            total += weights[end - 1]
            # A scene marker at the next line nudges the cut, without losing order.
            bonus = target * .30 if end < len(lines) and SCENE_BREAK.search(lines[end]) else 0
            candidates.append((abs(total - target) - bonus, end))
        end = min(candidates)[1]
        groups.append(lines[start:end])
        start = end
    groups.append(lines[start:])
    return groups


def dialogue_fragments(text, limit=42):
    result = []
    for line in text.splitlines():
        for match in DIALOGUE.finditer(line):
            before = line[:match.start()].strip()
            # Names/titles in narrative quotes are not dialogue.
            if before and not re.search(r'(?:说|问|喊|道|叫|答|回应|嘀咕|低语)[^。！？]{0,16}[：:]?$', before):
                continue
            quote = match.group(1).strip()
            if len(re.findall(r'[\u3400-\u9fff]', quote)) < 2:
                continue
            # Split at original punctuation; never add fabricated words/ellipsis.
            parts = re.findall(r'[^，、。！？!?；;…]+[，、。！？!?；;…]*|[，、。！？!?；;…]+', quote)
            buf = ''
            for part in parts:
                if buf and len(buf) + len(part) > limit:
                    result.append(buf)
                    buf = ''
                while len(part) > limit:
                    if buf:
                        result.append(buf)
                        buf = ''
                    result.append(part[:limit])
                    part = part[limit:]
                buf += part
            if buf:
                result.append(buf)
    return result


def boxes(n, w, h):
    """Right-to-left reading order, one broad establishing panel and a hero end."""
    m, g = 16, 16
    if n == 4:
        raw = [(m, m, w-m, int(h*.27)), (w//2+g//2, int(h*.27)+g, w-m, int(h*.63)),
               (m, int(h*.27)+g, w//2-g//2, int(h*.63)), (m, int(h*.63)+g, w-m, h-m)]
    elif n == 5:
        raw = [(m,m,w-m,int(h*.24)), (w//2+g//2,int(h*.24)+g,w-m,int(h*.49)),
               (m,int(h*.24)+g,w//2-g//2,int(h*.49)),
               (w//2+g//2,int(h*.49)+g,w-m,int(h*.72)),
               (m,int(h*.49)+g,w//2-g//2,int(h*.72))]
        raw[-1] = (m,int(h*.49)+g,w//2-g//2,h-m)
        raw[-2] = (w//2+g//2,int(h*.49)+g,w-m,h-m)
    else:
        raw = []
        row_h = (h - 2*m - 2*g)//3
        for r in range(3):
            y = m+r*(row_h+g)
            raw.extend([(w//2+g//2,y,w-m,y+row_h), (m,y,w//2-g//2,y+row_h)])
    return [list(b) for b in raw]


def visible_beat(lines):
    candidates = []
    visual = re.compile(r'站|走|跑|抬|转|看|握|剑|血|城|河|门|山|手|眼|脸|笑|雨|风|光|火|坐|躺|落|挥|举|伸|冲|飞|蹲|宫|瓦砾')
    for line in lines:
        if SCENE_BREAK.fullmatch(line):
            continue
        clean = DIALOGUE.sub('', line).strip(' ─—，。：「」“”')
        if len(clean) < 6:
            continue
        score = len(visual.findall(clean)) / max(1, len(clean))
        candidates.append((score, clean))
    if not candidates:
        return '人物在当前场景交谈，神态和手势自然。'
    best = max(candidates, key=lambda x: x[0])[1]
    # One source action, not an entire paragraph with competing compositions.
    return best[:200]


def plan_book(book, pages_per_chapter=4, panels_per_page=4, size=(1024,1536), seed=20261029):
    if pages_per_chapter < 1 or panels_per_page not in (4,5,6):
        raise ValueError('每章页数必须正数，每页格数为 4、5 或 6。')
    w,h = size
    if min(w,h) < 512 or w % 16 or h % 16:
        raise ValueError('画布宽高必须 >=512 且为 16 的倍数。')
    pages, volume_count = [], {}
    for chapter in book.chapters:
        chunks = split_groups(paragraphs(chapter.text), pages_per_chapter)
        for pi, lines in enumerate(chunks):
            volume_count[chapter.volume] = volume_count.get(chapter.volume,0)+1
            index = len(pages)+1
            groups = split_groups(lines, panels_per_page)
            all_dialogue = dialogue_fragments('\n'.join(lines))
            chosen, used = [], set()
            # First give each panel its own local utterance, then ensure >=2 when available.
            for group in groups:
                quote = next((q for q in dialogue_fragments('\n'.join(group)) if q not in used), '')
                chosen.append(quote)
                if quote:
                    used.add(quote)
            for q in all_dialogue:
                if sum(bool(s) for s in chosen) >= 2:
                    break
                if q not in used:
                    slot = next((j for j,s in enumerate(chosen) if not s), None)
                    if slot is not None:
                        chosen[slot] = q
                        used.add(q)
            items = []
            for j,(box,group) in enumerate(zip(boxes(panels_per_page,w,h),groups)):
                number, camera = WORDS[j], CAMERAS[j % 4]
                beat = visible_beat(group)
                x1,y1,x2,y2 = box
                position = ('the broad TOP panel' if j==0 and panels_per_page<6 else
                            'the broad BOTTOM panel' if j==3 and panels_per_page==4 else
                            f'the {"RIGHT" if x1>w*.4 else "LEFT"} panel at vertical position {y1}')
                # The middle-left reaction is a real circle; masks, not model boxes, enforce it.
                shape = 'circle' if panels_per_page==4 and j==2 else 'slant-top' if j==panels_per_page-1 else 'rect'
                if shape=='circle':
                    side = min(x2-x1,y2-y1)-12
                    cx,cy=(x1+x2)//2,(y1+y2)//2
                    box=[cx-side//2,cy-side//2,cx+(side+1)//2,cy+(side+1)//2]
                    x1,y1,x2,y2=box
                desc = f'PANEL {number}, {position}, {SHOT[camera]}. Visual event: {beat}'
                panel = {'type':'panel','id':f'pn_{j+1:02d}','bbox':box,'shape':shape,
                         'frame':'border','camera':camera,'desc':desc,'note':f'第{j+1}格：{beat}',
                         'source_text':'\n'.join(group),'seed':(seed+index*100+j) % (2**63),
                         'render_size':[math.ceil((x2-x1)/16)*16,math.ceil((y2-y1)/16)*16]}
                items.append(panel)
                quote=chosen[j]
                kind='shout' if quote and ('！' in quote or '!' in quote) and len(quote)<=18 else 'speech-notail'
                if not quote and j < 2:
                    # Faithful narration, explicitly labeled; never invent somebody's speech.
                    quote=next((s for s in group if len(s)>5 and not s.startswith(('「','“'))), '')[:38]
                    kind='narration'
                if quote:
                    bw=min(224, int((x2-x1)*.46))
                    bh=min(292, int((y2-y1)*.73))
                    bx=x2-bw-18
                    by=y1+max(20,int((y2-y1)*.10))
                    bubble={'type':'bubble','id':f'b_{j+1:02d}','panel_id':panel['id'],
                            'bbox':[bx,by,bx+bw,by+bh],'text':quote,'kind':kind,
                            'desc':f'in the upper right of PANEL {number}, {"narrator" if kind=="narration" else "off-panel voice"}',
                            'vertical':True,'note':'原文旁白' if kind=='narration' else '原文对白，程序排字',
                            'source_text':quote}
                    items.append(bubble)
            scene='<|background_setting|>A continuous illustrated adaptation of the source scene, consistent setting and lighting.<|/background_setting|>\n<|layout|>LAYOUT AND STORY: '
            scene+=' '.join(i['desc'] for i in items if i['type']=='panel')+'<|/layout|>'
            pages.append({'id':f'p{index:02d}','index':index,'title':f'{chapter.title} · {pi+1}',
                          'rev':1,'version':2,'size':[w,h],'style':'mono','vertical':True,
                          'scene':scene,'note':'Artwork contains no lettering; all dialogue is applied by Pillow.',
                          'summaryMeta':[],'summaryCaption':'','items':items,
                          'source':{'book':book.title,'volume':chapter.volume,'chapter':chapter.title,
                                    'chapter_index':chapter.index,'chapter_page':pi+1,'document':chapter.source},
                          'volume_page':volume_count[chapter.volume],
                          'adaptation':{'mode':'rules','pages_per_chapter':pages_per_chapter,
                                        'source_chars':sum(len(s) for s in lines),
                                        'dialogue_count':sum(i['type']=='bubble' and i['kind']!='narration' for i in items)}})
    return pages
