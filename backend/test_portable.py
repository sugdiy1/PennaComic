import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from runtime_config import RuntimeConfig


class PortableTests(unittest.TestCase):
    def test_relative_paths_resolve_next_to_config_not_cwd(self):
        with tempfile.TemporaryDirectory(prefix='漫画 space ') as folder:
            home = Path(folder)
            config = home / 'integration.json'
            config.write_text(json.dumps({'output': '作品', 'workflow': '模板.json', 'comfy_url': 'http://localhost:9000/'}), encoding='utf-8')
            c = RuntimeConfig(config, bundle_root=home / 'bundle')
            self.assertEqual(c.output, home / '作品')
            self.assertEqual(c.workflow, home / '模板.json')
            self.assertEqual(c.comfy_url, 'http://localhost:9000')

    def test_external_is_default_and_invalid_config_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / 'integration.json'
            self.assertEqual(RuntimeConfig(p).mode, 'external')
            p.write_text('{', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'integration.json'):
                RuntimeConfig(p)
            p.write_text(json.dumps({'comfy_url': 'file:///tmp'}), encoding='utf-8')
            with self.assertRaises(ValueError):
                RuntimeConfig(p)

    def test_external_mode_never_unloads_or_terminates_models(self):
        import gpu_mode
        with patch.object(gpu_mode, 'MODE', 'external'):
            c = gpu_mode.Controller()
            with patch.object(c, 'api', side_effect=AssertionError('must not call API')), patch.object(c, 'stop_owned', side_effect=AssertionError('must not kill')):
                self.assertEqual(c.chat()['status'], 'external')
                self.assertEqual(c.image()['status'], 'external')
                c.adopt_configured_server()


if __name__ == '__main__':
    unittest.main()
