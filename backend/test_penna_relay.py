import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import penna_relay


def snapshot():
    return {"title": "茶凉以后", "width": 832, "height": 1216,
            "source": {"caption": "Rainy station", "boxes": []},
            "layout": {"summary": {"caption": "Rainy station", "canvas": "multi_panel"},
                       "items": [{"label": "character", "caption": "A girl", "bbox": [-400, -300, 400, 300]},
                                 {"label": "text", "caption": "Speech", "text": "你终于来了。", "bbox": [-500, -100, -400, 100]}],
                       "bbox_coord_space": "abs_centralized", "bbox_format": "yxyx"},
            "settings": {"steps": 4, "seed": 42, "lora": "moss_Lineart.safetensors", "strength": 0.85}}


class RelayTests(unittest.TestCase):
    def legacy_job(self, folder):
        job = penna_relay.prepare(snapshot(), Path(folder))
        page = json.loads((job / 'page.json').read_text(encoding='utf-8'))
        page.pop('text_mode', None)
        page['dialogues'] = [{'text': '你终于来了。', 'box': [316, 108, 516, 208], 'kind': 'oval'}]
        penna_relay.write_json(job / 'page.json', page)
        return job

    def test_program_bubbles_use_bundled_chinese_font_on_non_chinese_windows(self):
        bundled = Path(penna_relay.__file__).resolve().parent.parent / 'font/LXGW975YuanSC-500W.ttf'
        with tempfile.TemporaryDirectory() as folder:
            job = self.legacy_job(folder)
            Image.new('RGB', (832, 1216), 'gray').save(job / 'raw.png')
            actual_loader = penna_relay.ImageFont.truetype
            used = []
            def load(path, *args, **kwargs):
                used.append(Path(path))
                if Path(path).resolve() != bundled:
                    raise AssertionError('Compositor must use the packaged font, not a host font')
                return actual_loader(path, *args, **kwargs)
            with patch.object(penna_relay.ImageFont, 'truetype', side_effect=load):
                result = penna_relay.compose(job)
            self.assertTrue(result.is_file())
            self.assertTrue(used)

    def test_template_compiles_typed_values_and_sends_exact_layout_to_model(self):
        with tempfile.TemporaryDirectory() as folder:
            job = penna_relay.prepare(snapshot(), Path(folder))
            wf = json.loads((job / "workflow.json").read_text(encoding="utf-8"))
            self.assertEqual(wf['1']['inputs']['unet_name'], 'moss_image_sft_int8_convrot.safetensors')
            self.assertNotIn('13', wf)
            self.assertIsInstance(wf["8"]["inputs"]["seed"], int)
            self.assertEqual(wf["8"]["inputs"]["steps"], 4)
            self.assertEqual(wf["12"]["inputs"]["strength_model"], 0.85)
            self.assertEqual(json.loads(wf['5']['inputs']['text']), snapshot()['layout'])
            negative = wf['6']['inputs']['text'].lower()
            for banned in ['text', 'lettering', 'speech bubble', 'caption', 'subtitles']:
                self.assertNotIn(banned, negative)
            page = json.loads((job / 'page.json').read_text(encoding='utf-8'))
            self.assertEqual(page['text_mode'], 'model')
            self.assertEqual(page['dialogues'], [])
            self.assertNotIn('bubble', page['settings'])
            self.assertTrue((job / "page.json").is_file())

    def test_invalid_size_fails_before_creating_job(self):
        with tempfile.TemporaryDirectory() as folder:
            value = snapshot(); value["width"] = 0
            with self.assertRaises(ValueError):
                penna_relay.prepare(value, Path(folder))
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_dialogue_and_bubble_captions_are_preserved_everywhere(self):
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot()
            value['layout']['summary']['caption']='Rainy station; a rounded speech bubble sits above her. Dialogue: "你终于来了。"'
            job=penna_relay.prepare(value,Path(folder))
            wf=json.loads((job/'workflow.json').read_text(encoding='utf-8'))
            self.assertEqual(json.loads(wf['5']['inputs']['text']), value['layout'])

    def test_model_lettering_publishes_raw_bytes_without_fonts_or_drawing(self):
        with tempfile.TemporaryDirectory() as folder:
            job = penna_relay.prepare(snapshot(), Path(folder))
            Image.new('RGBA', (832, 1216), (70, 80, 90, 100)).save(job / 'raw.png')
            original = (job / 'raw.png').read_bytes()
            metadata = (job / 'page.json').read_bytes()
            with patch.object(penna_relay.ImageFont, 'truetype', side_effect=AssertionError('No fonts')), \
                 patch.object(penna_relay.ImageDraw, 'Draw', side_effect=AssertionError('No drawing')):
                result = penna_relay.compose(job)
            self.assertEqual(result.read_bytes(), original)
            self.assertEqual((job / 'page.json').read_bytes(), metadata)
            self.assertFalse((job / 'page.png.tmp').exists())

    def test_model_lettering_rejects_wrong_image_size_without_publishing(self):
        with tempfile.TemporaryDirectory() as folder:
            job = penna_relay.prepare(snapshot(), Path(folder))
            Image.new('RGB', (64, 64), 'gray').save(job / 'raw.png')
            original = (job / 'raw.png').read_bytes()
            with self.assertRaisesRegex(ValueError, '尺寸'):
                penna_relay.compose(job)
            self.assertFalse((job / 'page.png').exists())
            self.assertFalse((job / 'page.png.tmp').exists())
            self.assertEqual((job / 'raw.png').read_bytes(), original)

    def test_program_bubbles_keep_image_dimensions_and_record_text(self):
        with tempfile.TemporaryDirectory() as folder:
            job = self.legacy_job(folder)
            raw = Image.new("RGB", (832, 1216), "gray")
            raw.save(job / "raw.png")
            result = penna_relay.compose(job)
            with Image.open(result) as image:
                self.assertEqual(image.size, (832, 1216))
                self.assertNotEqual(image.getpixel((416, 158)), (128, 128, 128))
            page = json.loads((job / "page.json").read_text(encoding="utf-8"))
            self.assertEqual(page["dialogues"][0]["text"], "你终于来了。")

    def test_multiple_selected_loras_are_chained_with_independent_strengths(self):
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot()
            value['settings']['loras']=[{'name':'moss_Lineart.safetensors','strength':.85},
                                        {'name':'muqiu_moss.safetensors','strength':.3}]
            job=penna_relay.prepare(value,Path(folder))
            wf=json.loads((job/'workflow.json').read_text(encoding='utf-8'))
            loaders={k:v for k,v in wf.items() if v['class_type']=='LoraLoaderModelOnly'}
            self.assertEqual(len(loaders),2)
            self.assertEqual(wf['relay_lora_2']['inputs']['model'],['12',0])
            self.assertEqual(wf['relay_lora_2']['inputs']['strength_model'],.3)
            self.assertEqual(wf['2']['inputs']['model'],['relay_lora_2',0])

    def test_no_lora_uses_base_model_without_loading_any_file(self):
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot();value['settings']['loras']=[]
            job=penna_relay.prepare(value,Path(folder))
            wf=json.loads((job/'workflow.json').read_text(encoding='utf-8'))
            self.assertFalse(any(n['class_type']=='LoraLoaderModelOnly' for n in wf.values()))
            self.assertEqual(wf['2']['inputs']['model'],['1',0])

    def test_template_defaults_use_types_and_unknown_without_default_fails(self):
        template = json.loads(penna_relay.TEMPLATE.read_text(encoding='utf-8-sig'))
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            template['1']['inputs']['extra_default'] = '{{another_value:1.25}}'
            path = root / 'template.json'
            path.write_text(json.dumps(template), encoding='utf-8')
            with patch.object(penna_relay, 'TEMPLATE', path):
                job = penna_relay.prepare(snapshot(), root / 'jobs')
                workflow = json.loads((job / 'workflow.json').read_text(encoding='utf-8'))
                self.assertEqual(workflow['1']['inputs']['extra_default'], 1.25)
                template['1']['inputs']['extra_default'] = '{{missing_value}}'
                path.write_text(json.dumps(template), encoding='utf-8')
                with self.assertRaisesRegex(ValueError, 'missing_value'):
                    penna_relay.prepare(snapshot(), root / 'jobs')


if __name__ == "__main__":
    unittest.main()
