from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class Settings:
    pages_per_chapter: int = 4
    panels_per_page: int = 4
    width: int = 1024
    height: int = 1536
    style: str = 'mono'
    lora: str = ''
    lora_strength: float = .85
    seed: int = 20261029
    steps: int = 50
    cfg: float = 3
    comfy_url: str = 'http://127.0.0.1:8188'
    workflow: str = ''

    def __post_init__(self):
        if self.pages_per_chapter < 1 or self.panels_per_page not in (4,5,6):
            raise ValueError('每章页数必须为正数，每页格数只能为 4、5、6。')
        if min(self.width,self.height)<512 or self.width%16 or self.height%16:
            raise ValueError('画布宽高须 >=512 且为 16 的倍数。')
        if self.style not in {'mono','color','sketch'}:
            raise ValueError('style 必须是 mono/color/sketch。')
        if self.steps<1 or self.cfg<=0:
            raise ValueError('steps 和 cfg 必须为正数。')

    def to_dict(self):
        values=asdict(self)
        values['lora']=self.lora or ('muqiu_moss.safetensors' if self.style=='color' else 'moss_Lineart.safetensors')
        return values
