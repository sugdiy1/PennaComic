"""Precise panel masks and programmatic Chinese lettering, adapted from page3_compose.py."""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

VERTICAL = str.maketrans({'（':'︵','）':'︶','(':'︵',')':'︶','「':'﹁','」':'﹂',
                          '『':'﹃','』':'﹄','—':'︱','─':'︱','…':'︙','“':'﹁','”':'﹂'})


def fit_vertical(text, box, font_path, hi=36, lo=14):
    x1,y1,x2,y2=box
    # An inscribed rectangle keeps text inside ellipse/cloud/spikes, including corner glyphs.
    iw,ih=int((x2-x1)*.66),int((y2-y1)*.66)
    text=text.translate(VERTICAL)
    for size in range(hi,lo-1,-1):
        row_step=math.ceil(size*1.13)
        col_step=math.ceil(size*1.15)
        rows=max(1,(ih-size)//row_step+1)
        columns=[]
        for part in text.split('\n'):
            columns.extend(part[i:i+rows] for i in range(0,len(part),rows))
        columns=columns or ['']
        tw=(len(columns)-1)*col_step+size
        th=(max(map(len,columns))-1)*row_step+size
        if tw<=iw and th<=ih:
            ImageFont.truetype(str(font_path),size)  # Fail early for missing/unusable fonts.
            right=(x1+x2+tw)/2-size
            top=(y1+y2-th)/2
            glyphs=[(round(right-ci*col_step),round(top+ri*row_step),ch)
                    for ci,col in enumerate(columns) for ri,ch in enumerate(col)]
            return {'font_size':size,'columns':columns,'glyphs':glyphs,'text_box':[round(right-tw+size),round(top),round(right+size),round(top+th)]}
    raise ValueError(f'台词无法以最小字号 {lo} 放入气泡；请放大 bbox 或拆分台词：{text[:30]}')


def _shape_points(box, kind):
    x1,y1,x2,y2=box
    cx,cy=(x1+x2)/2,(y1+y2)/2
    rx,ry=(x2-x1)/2,(y2-y1)/2
    points=[]
    if kind=='spiky':
        for i in range(48):
            a=2*math.pi*i/48
            r=1 if i%2==0 else .86
            points.append((cx+rx*r*math.cos(a),cy+ry*r*math.sin(a)))
    elif kind=='cloud':
        for i in range(240):
            a=2*math.pi*i/240
            r=.94+.06*math.cos(a*12)
            points.append((cx+rx*r*math.cos(a),cy+ry*r*math.sin(a)))
    return points


def balloon(draw,item,font_path):
    box=item['bbox']
    x1,y1,x2,y2=box
    cx,cy=(x1+x2)/2,(y1+y2)/2
    kind=item.get('kind','speech')
    shape='spiky' if kind in {'shout','spiky'} else 'cloud' if kind in {'thought','cloud','tremble'} else 'oval'
    target=item.get('tail')
    if target is None and kind in {'speech','shout','spiky','whisper','thought','cloud'}:
        target=[x1+int((x2-x1)*.25),y2+28]
    # Draw connector first, then white bubble body; two lines join without a base seam.
    if target and kind not in {'narration','speech-notail'}:
        tx,ty=target
        if kind in {'thought','cloud'}:
            for t,r in ((.75,3),(.52,5),(.30,7)):
                px=cx+(tx-cx)*t
                py=y2+(ty-y2)*t
                draw.ellipse((px-r,py-r,px+r,py+r),fill='white',outline='black',width=2)
        else:
            bx=cx+(tx-cx)*.35
            a=(bx-12,y2-13)
            b=(bx+13,y2-13)
            draw.polygon([a,(tx,ty),b],fill='white')
            draw.line([a,(tx,ty),b],fill='black',width=3)
    if kind=='narration':
        draw.rounded_rectangle(box,radius=3,fill='white',outline='black',width=3)
    elif shape in {'cloud','spiky'}:
        points=_shape_points(box,shape)
        draw.polygon(points,fill='white')
        draw.line(points+[points[0]],fill='black',width=3,joint='curve')
    else:
        draw.ellipse(box,fill='white',outline='black',width=3)
    layout=fit_vertical(item['text'],box,font_path)
    font=ImageFont.truetype(str(font_path),layout['font_size'])
    for x,y,ch in layout['glyphs']:
        draw.text((x,y),ch,font=font,fill='black',anchor='lt')
    return {'id':item['id'],'text':item['text'],'kind':kind,'bbox':box,
            'font_size':layout['font_size'],'columns':layout['columns'],'text_box':layout['text_box']}


def compose(page,panel_paths,dest,font_path):
    canvas=Image.new('RGB',tuple(page['size']),'white')
    draw=ImageDraw.Draw(canvas)
    for panel in (i for i in page['items'] if i['type']=='panel'):
        x1,y1,x2,y2=panel['bbox']
        width,height=x2-x1,y2-y1
        with Image.open(panel_paths[panel['id']]) as source:
            art=ImageOps.fit(source.convert('RGB'),(width,height),method=Image.Resampling.LANCZOS)
        if page['style']=='mono':
            art=ImageOps.grayscale(art).convert('RGB')
        mask=Image.new('L',(width,height),0)
        md=ImageDraw.Draw(mask)
        shape=panel.get('shape','rect')
        polygon=None
        if shape=='circle':
            md.ellipse((1,1,width-2,height-2),fill=255)
        elif shape in {'slant-top','slant-side'}:
            cut=max(16,int(min(width,height)*.09))
            polygon=([(0,cut),(width-1,0),(width-1,height-1),(0,height-1)] if shape=='slant-top' else
                     [(cut,0),(width-1,0),(width-cut-1,height-1),(0,height-1)])
            md.polygon(polygon,fill=255)
        else:
            md.rectangle((0,0,width-1,height-1),fill=255)
        canvas.paste(art,(x1,y1),mask)
        if panel.get('frame','border')!='none' and not shape.startswith('bleed'):
            line=5 if panel.get('frame')=='thick' else 3
            if shape=='circle':
                draw.ellipse((x1+1,y1+1,x2-2,y2-2),outline='black',width=line)
            elif polygon:
                pts=[(x+x1,y+y1) for x,y in polygon]
                draw.line(pts+[pts[0]],fill='black',width=line,joint='curve')
            else:
                draw.rectangle((x1,y1,x2-1,y2-1),outline='black',width=line)
    lettering=[balloon(draw,i,font_path) for i in page['items'] if i['type']=='bubble']
    dest=Path(dest)
    dest.parent.mkdir(parents=True,exist_ok=True)
    temp=dest.with_name(dest.name+'.tmp')
    canvas.save(temp,format='PNG')
    temp.replace(dest)
    return lettering
