"""Phase-one offline planning. Rendering orchestration is intentionally not connected."""
from pathlib import Path
from .config import Settings
from .parser import read_book
from .storage import digest, file_digest, output_lock, read_json, safe_name, write_json
from .storyboard import plan_book


def create_plan(source,output,settings=Settings()):
    source,output=Path(source).resolve(),Path(output).resolve()
    config=settings.to_dict()
    fingerprint=digest({'input_sha256':file_digest(source),'settings':config,'planner_version':1})
    with output_lock(output):
        previous=read_json(output/'manifest.json',{})
        if (previous.get('plan_fingerprint')==fingerprint and
            all((output/p['page_json']).is_file() and (output/p['page_json']).with_name('manifest.json').is_file()
                for p in previous.get('pages',[])) and previous.get('pages')):
            return previous
        book=read_book(source)
        pages=plan_book(book,settings.pages_per_chapter,settings.panels_per_page,
                        (settings.width,settings.height),settings.seed)
        entries=[]
        warnings=[]
        for page in pages:
            page['style']=settings.style
            volume=page['source']['volume']
            name=f'p{page["volume_page"]:04d}'
            folder=Path(safe_name(book.title))/safe_name(volume)/name
            page_path=folder/'page.json'
            image=folder.parent/(name+'.png')
            panels=[i for i in page['items'] if i['type']=='panel']
            for panel in panels:
                panel['prompt']=(f'{"black and white manga, zero colour, ink and screentone" if settings.style=="mono" else "manga illustration"}. '
                                 f'One continuous image, single viewpoint. {panel["desc"]} '
                                 'No lettering, no captions, no speech bubbles, no watermark, no text.')
            if page['adaptation']['dialogue_count']<2:
                warnings.append(f'{page["id"]}: 原文对白不足两条，保留旁白，不编造人物台词。')
            write_json(output/page_path,page)
            record={'schema_version':1,'page_id':page['id'],'status':'planned','source':page['source'],
                    'settings':config,'image':image.as_posix(),'elapsed_seconds':0,
                    'panels':[{'id':p['id'],'seed':p['seed'],'prompt':p['prompt'],
                               'status':'planned','lora':config['lora'],'lora_strength':config['lora_strength'],
                               'render_size':p['render_size'],'elapsed_seconds':0,'attempts':[]}
                              for p in panels]}
            write_json(output/folder/'manifest.json',record)
            entries.append({'id':page['id'],'title':page['title'],'volume':volume,
                            'chapter':page['source']['chapter'],'chapter_index':page['source']['chapter_index'],
                            'volume_page':page['volume_page'],'status':'planned',
                            'page_json':page_path.as_posix(),'image':image.as_posix()})
        manifest={'schema_version':1,'stage':'planned','book':book.title,'input':str(source),
                  'plan_fingerprint':fingerprint,'settings':config,'total_pages':len(entries),
                  'completed_pages':0,'chapters':[{'index':c.index,'title':c.title,'volume':c.volume,'characters':len(c.text)} for c in book.chapters],
                  'pages':entries,'warnings':warnings,
                  'execution':{'mode':'offline','network_requests':0,'rendering_connected':False}}
        write_json(output/'manifest.json',manifest)
        return manifest
