"""Lossless, ordered comic exports without invoking image-generation services.

Public API: export_comic(pages, output_dir, title, formats=('cbz', 'pdf'),
                         reading_direction='rtl'). See docs/comic-export.md.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
import zipfile
import zlib

from PIL import Image


def _validate_pages(pages):
    if not isinstance(pages, (list, tuple)) or not pages:
        raise ValueError("pages must be a nonempty ordered list")
    validated = []
    errors = []
    for index, page in enumerate(pages, 1):
        label = f"Page {index}"
        try:
            if not isinstance(page, dict):
                raise ValueError("entry must be an object")
            if page.get("page_number") is not None:
                label += f" (page_number={page['page_number']})"
            value = page.get("image")
            if not isinstance(value, (str, os.PathLike)) or not str(value):
                raise ValueError("image must be an absolute PNG path")
            path = Path(value)
            if not path.is_absolute():
                raise ValueError("image must be an absolute PNG path")
            with Image.open(path) as image:
                if image.format != "PNG":
                    raise ValueError("image must be a PNG")
                image.verify()
            # verify checks the PNG structure; load also verifies its pixel payload.
            with Image.open(path) as image:
                image.load()
                size = image.size
            validated.append({"image": path, "size": size,
                              "title": str(page.get("title") or "")})
        except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
            errors.append(f"{label}: {error}")
    if errors:
        raise ValueError("Invalid comic pages:\n" + "\n".join(errors))
    return validated


def _comic_info(pages, title, reading_direction):
    root = ET.Element("ComicInfo")
    for key, value in (("Title", title), ("Series", title),
                       ("PageCount", str(len(pages))),
                       ("Manga", "YesAndRightToLeft" if reading_direction == "rtl" else "Yes")):
        ET.SubElement(root, key).text = value
    page_nodes = ET.SubElement(root, "Pages")
    for index, page in enumerate(pages):
        attributes = {"Image": str(index), "Type": "FrontCover" if index == 0 else "Story",
                      "ImageWidth": str(page["size"][0]),
                      "ImageHeight": str(page["size"][1])}
        if page["title"]:
            attributes["Bookmark"] = page["title"]
        ET.SubElement(page_nodes, "Page", attributes)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def _write_cbz(path, pages, title, reading_direction):
    # PNG is already compressed. ZIP_STORED preserves the exact input bytes and
    # streams each file through zipfile rather than loading the entire book.
    width = max(4, len(str(len(pages))))
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
        for index, page in enumerate(pages, 1):
            archive.write(page["image"], f"{index:0{width}d}.png")
        archive.writestr("ComicInfo.xml", _comic_info(pages, title, reading_direction))


def _write_pdf(path, pages, title, reading_direction):
    """Write PDF 1.4 with Flate RGB images, keeping at most one decoded page.

    Pixel dimensions remain unchanged. A fixed 150 dpi sets only the physical
    MediaBox; transparent inputs are composited on white for reader consistency.
    """
    count = len(pages)
    offsets = [0] * (4 + count * 3)
    with open(path, "wb") as output:
        output.write(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")

        def obj(number, body):
            offsets[number] = output.tell()
            output.write(f"{number} 0 obj\n".encode("ascii"))
            output.write(body)
            output.write(b"\nendobj\n")

        def stream(number, attributes, payload):
            obj(number, (f"<< {attributes} /Length {len(payload)} >>\nstream\n".encode("ascii")
                         + payload + b"\nendstream"))

        direction = "R2L" if reading_direction == "rtl" else "L2R"
        obj(1, f"<< /Type /Catalog /Pages 2 0 R /ViewerPreferences << /Direction /{direction} >> >>".encode("ascii"))
        kids = " ".join(f"{4 + index * 3} 0 R" for index in range(count))
        obj(2, f"<< /Type /Pages /Count {count} /Kids [{kids}] >>".encode("ascii"))
        encoded_title = (b"\xfe\xff" + title.encode("utf-16-be")).hex()
        obj(3, f"<< /Title <{encoded_title}> /Producer (Penna Comic Export) >>".encode("ascii"))
        for index, page in enumerate(pages):
            page_id = 4 + index * 3
            image_id, content_id = page_id + 1, page_id + 2
            with Image.open(page["image"]) as source:
                if source.mode in ("RGBA", "LA") or "transparency" in source.info:
                    with source.convert("RGBA") as rgba:
                        image = Image.new("RGB", rgba.size, "white")
                        image.paste(rgba, mask=rgba.getchannel("A"))
                else:
                    image = source.convert("RGB")
                try:
                    width, height = image.size
                    compressed = zlib.compress(image.tobytes())
                finally:
                    image.close()
            # Points = pixels * 72 / 150. No resampling or JPEG encoding.
            points_w, points_h = width * 72 / 150, height * 72 / 150
            dimensions = f"{points_w:.6f} {points_h:.6f}"
            obj(page_id, (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {dimensions}] "
                          f"/Resources << /XObject << /Im0 {image_id} 0 R >> >> "
                          f"/Contents {content_id} 0 R >>").encode("ascii"))
            stream(image_id, f"/Type /XObject /Subtype /Image /Width {width} /Height {height} "
                            "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode", compressed)
            del compressed
            content = f"q {points_w:.6f} 0 0 {points_h:.6f} 0 0 cm /Im0 Do Q\n".encode("ascii")
            stream(content_id, "", content)
        xref = output.tell()
        output.write(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode("ascii"))
        for offset in offsets[1:]:
            output.write(f"{offset:010d} 00000 n \n".encode("ascii"))
        output.write((f"trailer\n<< /Size {len(offsets)} /Root 1 0 R /Info 3 0 R >>\n"
                      f"startxref\n{xref}\n%%EOF\n").encode("ascii"))


def export_comic(pages, output_dir, title, formats=("cbz", "pdf"), reading_direction="rtl"):
    """Export every page in supplied order, or raise without leaving partial files.

    Returns {files: {format: absolute_path}, page_count: int,
             reading_direction: 'rtl'|'ltr'}. Existing exports are never replaced.
    """
    if not isinstance(title, str) or not title.strip():
        raise ValueError("title must be a nonempty string")
    if reading_direction not in ("rtl", "ltr"):
        raise ValueError("reading_direction must be 'rtl' or 'ltr'")
    if isinstance(formats, str) or not isinstance(formats, (list, tuple)) or not formats:
        raise ValueError("formats must be a nonempty list of 'cbz' and/or 'pdf'")
    if any(value not in ("cbz", "pdf") for value in formats):
        raise ValueError("formats supports only 'cbz' and 'pdf'")
    formats = list(dict.fromkeys(formats))
    validated = _validate_pages(pages)
    destination = Path(output_dir).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    safe_title = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", title).strip(" .")[:100] or "comic"
    # Prefix also avoids Windows reserved device names (CON, COM1, etc.).
    base = f"comic-{safe_title}-{uuid.uuid4().hex}"
    pending, published, files = [], [], {}
    try:
        for format_name in formats:
            descriptor, temporary_name = tempfile.mkstemp(prefix=f".{base}-", suffix=".tmp", dir=destination)
            os.close(descriptor)
            temporary = Path(temporary_name)
            pending.append(temporary)
            writer = _write_cbz if format_name == "cbz" else _write_pdf
            writer(temporary, validated, title, reading_direction)
            files[format_name] = str(destination / f"{base}.{format_name}")
        # Hard-link publication is atomic and refuses an existing target on both
        # Windows and POSIX. Temporary files are on the same filesystem.
        for temporary, format_name in zip(pending, formats):
            target = Path(files[format_name])
            os.link(temporary, target)
            published.append(target)
    except BaseException:
        for path in published:
            path.unlink(missing_ok=True)
        raise
    finally:
        for path in pending:
            path.unlink(missing_ok=True)
    return {"files": files, "page_count": len(validated), "reading_direction": reading_direction}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export ordered PNG pages to CBZ/PDF")
    parser.add_argument("--request", required=True, help="UTF-8 JSON request file")
    args = parser.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8-sig"))
        result = export_comic(**request)
    except Exception as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
