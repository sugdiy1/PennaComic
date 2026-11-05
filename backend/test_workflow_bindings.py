import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import penna_relay
from workflow_inspect import inspect as inspect_workflow
from test_penna_relay import snapshot

ROOT=Path(__file__).resolve().parent.parent
def graph():
    return json.loads((ROOT/'workflows/moss-official-api.json').read_text(encoding='utf-8'))
def renamed(value):
    ids={key:'n'+str(100+index*17) for index,key in enumerate(value)}
    def links(v):
        if isinstance(v,list):
            if len(v)==2 and isinstance(v[0],str) and v[0] in ids and isinstance(v[1],int):return [ids[v[0]],v[1]]
            return [links(x) for x in v]
        if isinstance(v,dict):return {k:links(x) for k,x in v.items()}
        return v
    return {ids[k]:links(v) for k,v in value.items()},ids

class WorkflowBindingsTests(unittest.TestCase):
    def test_lora_manager_and_rgthree_defaults_exclude_disabled_entries(self):
        for kind, inputs in [
            ('Power Lora Loader (rgthree)',{'lora_1':{'on':True,'lora':'paint.safetensors','strength':.7},'lora_2':{'on':False,'lora':'disabled.safetensors','strength':1}}),
            ('Lora Loader (LoraManager)',{'text':'<lora:paint.safetensors:0.7>'}),
        ]:
            value=graph();value['custom_lora']={'class_type':kind,'inputs':{'model':['1',0],**inputs}};value['2']['inputs']['model']=['custom_lora',0]
            result=inspect_workflow(value)
            self.assertEqual(result['status'],'ready')
            self.assertEqual(result['defaults']['loras'],[{'name':'paint.safetensors','strength':.7}])
    def test_unknown_lora_manager_can_be_preserved_without_silent_replacement(self):
        value=graph();value['custom_lora']={'class_type':'MysteryLoraManager','inputs':{'model':['1',0],'data':'user config'}};value['2']['inputs']['model']=['custom_lora',0]
        self.assertEqual(inspect_workflow(value)['status'],'needs_binding')
        result=inspect_workflow(value,{'manage_loras':False})
        self.assertEqual(result['status'],'ready')
        actual,_=self.prepare(value,{'workflow_bindings':result['bindings']})
        self.assertEqual(actual['custom_lora']['inputs']['data'],'user config')
    def test_no_lora_defaults_are_explicitly_empty_and_placeholder_sampling_read(self):
        result=inspect_workflow(graph())
        self.assertEqual(result['defaults']['loras'],[])
        self.assertEqual(result['defaults']['steps'],25)
        self.assertEqual(result['defaults']['cfg'],2.5)
    def prepare(self, value, settings=None):
        folder=tempfile.TemporaryDirectory();self.addCleanup(folder.cleanup)
        root=Path(folder.name);source=root/'改装官流.json'
        source.write_text(json.dumps(value),encoding='utf-8')
        snap=snapshot();snap['settings'].update(workflow_path=str(source),loras=[],**(settings or {}))
        job=penna_relay.prepare(snap,root/'jobs')
        return json.loads((job/'workflow.json').read_text(encoding='utf-8')),job

    def test_renumbered_official_graph_preserves_sampling_and_negative(self):
        value,ids=renamed(graph());value[ids['6']]['inputs']['text']='bad anatomy, watermark'
        actual,job=self.prepare(value)
        self.assertEqual(json.loads(actual[ids['5']]['inputs']['text']),snapshot()['layout'])
        self.assertEqual(actual[ids['6']]['inputs']['text'],'bad anatomy, watermark')
        self.assertEqual(actual[ids['8']]['inputs']['sampler_name'],'er_sde')
        self.assertEqual(actual[ids['8']]['inputs']['model'],[ids['15'],0])
        self.assertEqual(actual[ids['7']]['inputs']['width'],832)
        manifest=json.loads((job/'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['output_node'],ids['11'])

    def test_linked_positive_is_replaced_without_running_prompt_generator(self):
        value,ids=renamed(graph())
        value['prompt_source']={'class_type':'TextGenerate','inputs':{'prompt':'do not replay'}}
        value[ids['5']]['inputs']['text']=['prompt_source',0]
        actual,_=self.prepare(value)
        self.assertNotIn('prompt_source',actual)
        self.assertEqual(json.loads(actual[ids['5']]['inputs']['text']),snapshot()['layout'])

    def test_ambiguous_outputs_require_binding_and_do_not_create_job(self):
        value=graph();value['another_save']={'class_type':'SaveImage','inputs':{'images':['9',0],'filename_prefix':'other'}}
        with self.assertRaisesRegex(ValueError,'绑定|多个'):
            self.prepare(value)
        actual,_=self.prepare(value,{'workflow_bindings':{'output':'another_save','sampler':'8','positive':'5.text','manage_loras':True}})
        self.assertIn('another_save',actual)
        self.assertNotIn('11',actual)

    def test_changed_workflow_hash_rejected_before_job_creation(self):
        with self.assertRaisesRegex(ValueError,'变化|改变|重新识别'):
            self.prepare(graph(),{'workflow_sha256':'0'*64})

    def test_qwen_attach_uses_detected_moss_image_and_output(self):
        value,ids=renamed(graph())
        actual,_=self.prepare(value,{'render_mode':'generate_edit','edit_steps':10,'edit_prompt':'保留台词'})
        self.assertEqual(actual['qwen_encode']['inputs']['images.image_1'],[ids['9'],0])
        self.assertEqual(actual[ids['11']]['inputs']['images'],['qwen_decode',0])

if __name__=='__main__':unittest.main()
