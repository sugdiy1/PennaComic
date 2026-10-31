"""Contract tests: run with the bundled ComfyUI Python, no model required."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import comic_export


class ComicExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "exports"
        self.pages = []
        # Deliberately misleading filenames/numbers: caller order is authoritative.
        for index in range(13):
            path = self.root / f"page-{13 - index}.png"
            Image.new("RGB", (30 + index, 60), (index * 15, 40, 200)).save(path)
            self.pages.append({"image": str(path), "title": f"第{index + 1}页",
                               "page_number": 99 - index})

    def test_cbz_preserves_supplied_order_original_bytes_and_unicode_metadata(self):
        title = '中文漫画 & <雨天> "相遇"'
        result = comic_export.export_comic(self.pages, self.output, title, ("cbz",))
        self.assertEqual(result["page_count"], 13)
        self.assertEqual(result["reading_direction"], "rtl")
        with zipfile.ZipFile(result["files"]["cbz"]) as archive:
            self.assertEqual(archive.namelist(), [f"{i:04d}.png" for i in range(1, 14)]
                             + ["ComicInfo.xml"])
            for index, page in enumerate(self.pages, 1):
                self.assertEqual(archive.read(f"{index:04d}.png"),
                                 Path(page["image"]).read_bytes())
            metadata = ET.fromstring(archive.read("ComicInfo.xml"))
            self.assertEqual(metadata.findtext("Title"), title)
            self.assertEqual(metadata.findtext("Series"), title)
            self.assertEqual(metadata.findtext("PageCount"), "13")
            self.assertEqual(metadata.findtext("Manga"), "YesAndRightToLeft")
            self.assertEqual(metadata.find("Pages/Page").attrib["Type"], "FrontCover")
            self.assertEqual(metadata.find("Pages/Page").attrib["Image"], "0")

    def test_pdf_has_all_pages_and_lossless_ordered_images(self):
        pdfinfo = shutil.which("pdfinfo")
        pdftoppm = shutil.which("pdftoppm")
        if not pdfinfo or not pdftoppm:
            self.skipTest("Optional Poppler validation tools unavailable")
        result = comic_export.export_comic(self.pages, self.output, "中文PDF")
        pdf = result["files"]["pdf"]
        info = subprocess.run([pdfinfo, "-f", "1", "-l", "13", pdf],
                              capture_output=True, text=True, encoding="utf-8", check=True)
        self.assertRegex(info.stdout, r"Pages:\s+13\b")
        self.assertRegex(info.stdout, r"Page\s+1 size:\s+14\.4 x 28\.8 pts")
        subprocess.run([pdftoppm, "-png", "-r", "150", pdf, str(self.root / "extracted")],
                       capture_output=True, check=True)
        images = sorted(self.root.glob("extracted-*.png"))
        self.assertEqual(len(images), 13)
        for image, page in zip(images, self.pages):
            with Image.open(image) as actual, Image.open(page["image"]) as expected:
                self.assertEqual(actual.size, expected.size)
                self.assertEqual(actual.convert("RGB").tobytes(), expected.tobytes())
        data = Path(pdf).read_bytes()
        self.assertIn(b"/Direction /R2L", data)
        self.assertNotIn(b"/DCTDecode", data)

    def test_transparency_is_composited_on_white_in_pdf_but_original_cbz_is_preserved(self):
        pdftoppm = shutil.which("pdftoppm")
        if not pdftoppm:
            self.skipTest("Optional Poppler validation tools unavailable")
        path = self.root / "alpha.png"
        Image.new("RGBA", (30, 60), (255, 0, 0, 128)).save(path)
        result = comic_export.export_comic([{"image": str(path)}], self.output, "透明")
        subprocess.run([pdftoppm, "-png", "-r", "150", "-singlefile", result["files"]["pdf"],
                        str(self.root / "alpha-render")], capture_output=True, check=True)
        with Image.open(self.root / "alpha-render.png") as rendered:
            self.assertEqual(rendered.convert("RGB").getpixel((15, 30)), (255, 127, 127))
        with zipfile.ZipFile(result["files"]["cbz"]) as archive:
            self.assertEqual(archive.read("0001.png"), path.read_bytes())

    def test_missing_or_corrupt_late_page_creates_no_partial_export(self):
        for failure in ("missing", "corrupt", "truncated"):
            with self.subTest(failure=failure):
                broken = self.root / f"{failure}.png"
                if failure == "corrupt":
                    broken.write_bytes(b"not a png")
                elif failure == "truncated":
                    broken.write_bytes(Path(self.pages[0]["image"]).read_bytes()[:45])
                pages = self.pages + [{"image": str(broken), "page_number": 14}]
                with self.assertRaisesRegex(ValueError, "14"):
                    comic_export.export_comic(pages, self.output, "失败")
                self.assertFalse(self.output.exists())

    def test_empty_pages_invalid_formats_and_relative_paths_are_rejected(self):
        cases = [([], {}), (self.pages, {"formats": ("epub",)}),
                 (self.pages, {"formats": ()}),
                 (self.pages, {"reading_direction": "up"}),
                 ([{"image": "relative.png"}], {})]
        for pages, kwargs in cases:
            with self.subTest(kwargs=kwargs, count=len(pages)):
                with self.assertRaises(ValueError):
                    comic_export.export_comic(pages, self.output, "验证", **kwargs)
                self.assertFalse(self.output.exists())

    def test_repeated_exports_never_overwrite_and_ltr_metadata_is_explicit(self):
        first = comic_export.export_comic(self.pages[:1], self.output, "CON:漫画/测试",
                                          ("cbz",), "ltr")
        original = Path(first["files"]["cbz"]).read_bytes()
        second = comic_export.export_comic(self.pages[:1], self.output, "CON:漫画/测试",
                                           ("cbz",), "ltr")
        self.assertNotEqual(first["files"], second["files"])
        self.assertEqual(Path(first["files"]["cbz"]).read_bytes(), original)
        self.assertEqual(len(list(self.output.iterdir())), 2)
        with zipfile.ZipFile(second["files"]["cbz"]) as archive:
            self.assertEqual(ET.fromstring(archive.read("ComicInfo.xml")).findtext("Manga"), "Yes")

    def test_failed_second_format_cleans_temporary_files(self):
        # Disk/encoder failures are external; inject failure at the writer boundary.
        with patch.object(comic_export, "_write_pdf", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                comic_export.export_comic(self.pages, self.output, "中断")
        self.assertEqual(list(self.output.iterdir()), [])

    def test_publication_failure_rolls_back_completed_export_without_touching_existing_files(self):
        self.output.mkdir()
        unrelated = self.output / "existing.cbz"
        unrelated.write_bytes(b"prior export")
        original_link = os.link
        calls = 0

        def fail_second_link(source, target):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("publication failed")
            original_link(source, target)

        with patch.object(comic_export.os, "link", side_effect=fail_second_link):
            with self.assertRaisesRegex(OSError, "publication failed"):
                comic_export.export_comic(self.pages, self.output, "中断")
        self.assertEqual(list(self.output.iterdir()), [unrelated])
        self.assertEqual(unrelated.read_bytes(), b"prior export")

    def test_cli_reads_utf8_request_and_prints_json(self):
        request = self.root / "request.json"
        request.write_text(json.dumps({"pages": self.pages[:2],
                                       "output_dir": str(self.output),
                                       "title": "命令行导出", "formats": ["cbz"]},
                                      ensure_ascii=False), encoding="utf-8")
        run = subprocess.run([sys.executable, str(Path(comic_export.__file__)),
                              "--request", str(request)],
                             capture_output=True, text=True, encoding="utf-8", check=True)
        result = json.loads(run.stdout)
        self.assertEqual(result["page_count"], 2)
        self.assertTrue(Path(result["files"]["cbz"]).is_file())


if __name__ == "__main__":
    unittest.main()
