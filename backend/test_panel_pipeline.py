import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import penna_relay as relay
from test_penna_batch import FakeController


def snapshot():
    boxes = [
        {'box':[8,8,120,72],'name':'第1格','label':'object','caption':'An adult in a blue coat catches a box.'},
        {'box':[8,80,60,152],'name':'第2格','label':'object','caption':'Close-up of hands.','shape':[[0.2,0],[1,0],[1,1],[0,1]]},
        {'box':[68,80,120,152],'name':'第3格','label':'object','caption':'An adult face.','shape':'ellipse'},
        {'box':[18,20,50,40],'label':'text','text':'接住！','caption':'speech bubble'},
    ]
    return {'title':'panel test','width':128,'height':160,'source':{'width':128,'height':160,'style':'color manga','cast':{},'boxes':boxes},
            'layout':{'summary':{'caption':'Three panel page'},'items':[]},
            'settings':{'render_mode':'panels','panel_indices':[0,1,2],'seed':100,'steps':4,'loras':[],'panel_resolution':256}}


class PanelPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.addCleanup(patch.stopall)
        patch.object(relay,'OUTPUT',self.root).start()
        self.executed=[]
        self.real_run=relay.run
        def render(job, controller=None, **kwargs):
            child=json.loads((job/'snapshot.json').read_text(encoding='utf-8'))
            self.executed.append(child['title'])
            path=job/'page.png';Image.new('RGB',(child['width'],child['height']),'red').save(path)
            m=json.loads((job/'manifest.json').read_text(encoding='utf-8'));m['status']='done';relay.write_json(job/'manifest.json',m)
            return path
        patch.object(relay,'run',side_effect=render).start()

    def test_split_has_independent_captions_and_routes_dialogue_once(self):
        job=relay.prepare(snapshot(),self.root)
        plan=json.loads((job/'panel-plan.json').read_text(encoding='utf-8'))
        children=[json.loads((Path(p['job_dir'])/'workflow.json').read_text(encoding='utf-8')) for p in plan['panels']]
        texts=[c['5']['inputs']['text'] for c in children]
        self.assertIn('接住！',texts[0]);self.assertNotIn('接住！',texts[1]);self.assertNotIn('接住！',texts[2])
        self.assertNotIn('Three panel page',texts[0])
        self.assertEqual([c['8']['inputs']['seed'] for c in children],[100,101,102])

    def test_masks_are_real_and_cached_rerun_needs_no_gpu(self):
        job=relay.prepare(snapshot(),self.root);c=FakeController()
        with contextlib.redirect_stdout(io.StringIO()):out=self.real_run(job,c)
        with Image.open(out) as im:
            self.assertEqual(im.size,(128,160));self.assertEqual(im.getpixel((0,0)),(255,255,255))
            self.assertEqual(im.getpixel((9,81)),(255,255,255))
            self.assertEqual(im.getpixel((69,81)),(255,255,255))
            self.assertEqual(im.getpixel((94,116)),(255,0,0))
        self.assertEqual(len(self.executed),3)
        second=relay.prepare(snapshot(),self.root);c2=FakeController()
        with contextlib.redirect_stdout(io.StringIO()):self.real_run(second,c2)
        self.assertEqual(len(self.executed),3);self.assertNotIn('image',c2.calls)

    def test_only_changed_panel_is_regenerated(self):
        with contextlib.redirect_stdout(io.StringIO()):self.real_run(relay.prepare(snapshot(),self.root),FakeController())
        value=snapshot();value['source']['boxes'][1]['caption']='A different hand pose.'
        with contextlib.redirect_stdout(io.StringIO()):self.real_run(relay.prepare(value,self.root),FakeController())
        self.assertEqual(len(self.executed),4);self.assertIn('第2格',self.executed[-1])

    def test_single_seed_override_regenerates_only_selected_panel(self):
        with contextlib.redirect_stdout(io.StringIO()):self.real_run(relay.prepare(snapshot(),self.root),FakeController())
        value=snapshot();value['settings']['panel_seeds']={'1':999}
        with contextlib.redirect_stdout(io.StringIO()):self.real_run(relay.prepare(value,self.root),FakeController())
        self.assertEqual(len(self.executed),4);self.assertIn('第2格',self.executed[-1])

    def test_unassigned_dialogue_is_rejected_instead_of_silently_dropped(self):
        value=snapshot();value['source']['boxes'][3]['box']=[0,154,20,160]
        with self.assertRaisesRegex(ValueError,'台词'):relay.prepare(value,self.root)

    def test_missing_or_text_frame_rejected_before_creating_job(self):
        for indices in [[],[3],[99],[0,0]]:
            value=snapshot();value['settings']['panel_indices']=indices
            with self.assertRaises(ValueError):relay.prepare(value,self.root)
        self.assertEqual(list(self.root.iterdir()),[])


if __name__=='__main__':unittest.main()
