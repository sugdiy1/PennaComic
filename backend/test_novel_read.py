import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from novel2comic.cli import main


class NovelReadTests(unittest.TestCase):
    def test_read_returns_complete_chapter_text_without_planning_or_network(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'小说.txt'
            text = '第一卷\n第一章 初见\n成年站务员站在站台。\n“接住！”她喊道。\n第二章 归途\n他们把书送上车。'
            source.write_text(text,encoding='utf-8')
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = main(['read','--input',str(source),'--json'])
            self.assertEqual(code,0)
            result = json.loads(out.getvalue())
            self.assertEqual(len(result['chapters']),2)
            self.assertIn('接住',result['chapters'][0]['text'])
            self.assertIn('送上车',result['chapters'][1]['text'])
            self.assertEqual(source.read_text(encoding='utf-8'),text)
            self.assertEqual(list(Path(folder).glob('*.json')),[])
