import json
from pathlib import Path
import tempfile
import unittest
import contextlib
import io
from unittest.mock import patch
from PIL import Image
import penna_relay as relay
from test_penna_relay import snapshot


class QwenEditTests(unittest.TestCase):
    def test_generate_then_edit_routes_final_output_and_preserves_moss_original(self):
        with tempfile.TemporaryDirectory() as folder:
            value = snapshot()
            value['settings'].update(render_mode='generate_edit', edit_prompt='只修改左上格的手，保留台词。')
            job = relay.prepare(value, Path(folder))
            graph = json.loads((job/'workflow.json').read_text(encoding='utf-8'))
            self.assertEqual(graph['qwen_encode']['inputs']['images.image_1'], ['9', 0])
            self.assertEqual(graph['11']['inputs']['images'], ['qwen_decode', 0])
            self.assertEqual(graph['moss_reference']['inputs']['images'], ['9', 0])
            self.assertEqual(graph['qwen_clip']['inputs']['type'], 'qwen_image')
            self.assertEqual(graph['qwen_encode']['inputs']['prompt'], '只修改左上格的手，保留台词。')
            self.assertEqual(json.loads((job/'manifest.json').read_text(encoding='utf-8'))['render_mode'], 'generate_edit')

    def test_edit_only_saves_immutable_input_and_has_no_moss_sampler(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root/'reference.png'
            Image.new('RGB', (832,1216), 'blue').save(source)
            value = snapshot(); value['settings'].update(render_mode='edit_only', reference_image=str(source))
            value['layout'] = {}
            job = relay.prepare(value, root/'jobs')
            graph = json.loads((job/'workflow.json').read_text(encoding='utf-8'))
            self.assertNotIn('8', graph)
            self.assertEqual(graph['qwen_reference']['class_type'], 'LoadImage')
            self.assertEqual((job/'reference.png').read_bytes(), source.read_bytes())
            source.unlink()
            self.assertTrue((job/'reference.png').exists())

    def test_invalid_mode_and_empty_edit_prompt_rejected_before_job(self):
        for settings in [{'render_mode':'unknown'}, {'render_mode':'generate_edit','edit_prompt':'  '}]:
            with tempfile.TemporaryDirectory() as folder:
                value=snapshot();value['settings'].update(settings)
                with self.assertRaises(ValueError):relay.prepare(value,Path(folder))
                self.assertEqual(list(Path(folder).iterdir()),[])

    def test_generate_edit_rejects_size_that_qwen_would_round(self):
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot();value['width']=848;value['settings']['render_mode']='generate_edit'
            with self.assertRaisesRegex(ValueError,'32'):relay.prepare(value,Path(folder))

    def test_two_save_nodes_publish_edited_image_and_keep_original_on_resume(self):
        from test_penna_batch import FakeController
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot();value['settings']['render_mode']='generate_edit'
            job=relay.prepare(value,Path(folder));manifest=json.loads((job/'manifest.json').read_text(encoding='utf-8'))
            manifest['prompt_id']='finished';relay.write_json(job/'manifest.json',manifest)
            history={'status':{'status_str':'success'},'outputs':{
                'moss_reference':{'images':[{'filename':'original.png','type':'output'}]},
                '11':{'images':[{'filename':'edited.png','type':'output'}]}}}
            controller=FakeController(histories={'finished':history})
            def image(color):
                out=io.BytesIO();Image.new('RGB',(832,1216),color).save(out,format='PNG');return out.getvalue()
            original,edited=image('blue'),image('red')
            def download(url,**kwargs):return io.BytesIO(edited if 'edited.png' in url else original)
            with patch.object(relay.urllib.request,'urlopen',side_effect=download), contextlib.redirect_stdout(io.StringIO()):
                result=relay.run(job,controller,manage_gpu=False)
                self.assertEqual(result.read_bytes(),edited)
                self.assertEqual((job/'moss.png').read_bytes(),original)
                self.assertEqual(relay.run(job,controller,manage_gpu=False),result)
            self.assertEqual(controller.submitted,[])

    def test_missing_qwen_output_cannot_publish_only_moss_output(self):
        from test_penna_batch import FakeController
        with tempfile.TemporaryDirectory() as folder:
            value=snapshot();value['settings']['render_mode']='generate_edit'
            job=relay.prepare(value,Path(folder));manifest=json.loads((job/'manifest.json').read_text(encoding='utf-8'))
            manifest['prompt_id']='partial';relay.write_json(job/'manifest.json',manifest)
            controller=FakeController(histories={'partial':{'status':{'status_str':'success'},'outputs':{
                'moss_reference':{'images':[{'filename':'original.png','type':'output'}]}}}})
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError,'Qwen'):
                relay.run(job,controller,manage_gpu=False)
            self.assertFalse((job/'page.png').exists())


if __name__=='__main__':unittest.main()
