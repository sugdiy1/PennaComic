import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('package_release', Path(__file__).resolve().parent.parent / 'tool/package_release.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class DistributionTests(unittest.TestCase):
    def test_rejected_credentials_leave_no_publishable_partial_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            safe = root / 'safe.py'
            safe.write_text('print("safe")', encoding='utf-8')
            sensitive = root / 'sensitive.py'
            sensitive.write_text('token = "' + 'ghp_' + 'x' * 36 + '"', encoding='utf-8')
            out = root / 'release.zip'
            with self.assertRaisesRegex(ValueError, 'Credential-like'):
                pack.write_package([(safe, 'a.py'), (sensitive, 'b.py')], out)
            self.assertFalse(out.exists(), 'A rejected build must never look like a usable ZIP')
            self.assertFalse(out.with_suffix('.zip.sha256').exists())

    def test_archive_entry_paths_cannot_escape_or_collide_after_normalization(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            file = root / 'sample.py'
            file.write_text('pass', encoding='utf-8')
            for index, name in enumerate(['../escape.py', '/absolute.py', 'C:/drive.py', 'lib/../escape.py', 'dir\\escape.py']):
                with self.subTest(name=name):
                    with self.assertRaises(ValueError):
                        pack.write_package([(file, name)], root / f'bad-{index}.zip')
            with self.assertRaises(ValueError):
                pack.write_package([(file, 'a.py'), (file, 'A.py')], root / 'collision.zip')

    def test_source_package_excludes_user_data_builds_and_model_files(self):
        with tempfile.TemporaryDirectory(prefix='分发 space ') as folder:
            root = Path(folder)
            for name in ['lib/main.dart', 'backend/penna_relay.py', 'LICENSE', 'README.md', 'backend/server-state.json', 'assets/keys.dat', 'backend/private.gguf', 'build/data/app.so', 'workspace.json']:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('synthetic', encoding='utf-8')
            out = root / 'dist/source.zip'
            report = pack.write_package(pack.source_files(root), out)
            self.assertEqual(report['files'], 4)
            with zipfile.ZipFile(out) as archive:
                self.assertEqual(set(archive.namelist()), {'lib/main.dart', 'backend/penna_relay.py', 'LICENSE', 'README.md', 'PACKAGE-MANIFEST.json'})
                self.assertEqual(len(json.loads(archive.read('PACKAGE-MANIFEST.json'))), 4)


if __name__ == '__main__':
    unittest.main()
