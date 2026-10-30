"""The native shell talks to the Python worker through this JSON request contract."""
from pathlib import Path

import pytest
from PIL import Image

from dragshift import convert
from dragshift.engine_cli import handle


def _run(action: str, files: list[Path], parameters: dict | None = None) -> dict:
    return handle({"action": action, "files": [str(path) for path in files],
                   "parameters": parameters or {}, "settings": {"output": "next"}})


def test_crop_uses_original_pixel_coordinates_and_preserves_source(tmp_path):
    source = tmp_path / "source.png"
    Image.new("RGB", (80, 40), "white").save(source)

    result = _run("tool:Crop", [source], {"x": 11, "y": 7, "width": 20, "height": 12})

    output = Path(result["outputs"][0])
    assert result["ok"] and output.is_file()
    assert Image.open(output).size == (20, 12)
    assert Image.open(source).size == (80, 40)


def test_resize_exact_can_keep_original_proportions(tmp_path):
    source = tmp_path / "source.png"
    Image.new("RGB", (80, 40), "white").save(source)

    result = _run("tool:Resize", [source], {
        "mode": "exact", "width": 30, "height": 30, "keep_proportions": True,
    })

    assert result["ok"]
    assert Image.open(result["outputs"][0]).size == (30, 15)
    assert Image.open(source).size == (80, 40)


def test_multiple_images_convert_to_a_single_pdf(tmp_path):
    files = []
    for number in range(2):
        path = tmp_path / f"image-{number}.png"
        Image.new("RGB", (24, 18), (number * 50, 70, 90)).save(path)
        files.append(path)

    result = _run("convert:PDF", files)

    assert result["ok"] and len(result["outputs"]) == 1
    with convert.fitz.open(result["outputs"][0]) as document:
        assert document.page_count == 2
    assert all(path.is_file() for path in files)


def test_mixed_inputs_keep_success_and_report_skipped_files(tmp_path):
    image = tmp_path / "image.png"
    text = tmp_path / "notes.txt"
    Image.new("RGB", (12, 12), "white").save(image)
    text.write_text("keep me", encoding="utf-8")

    result = _run("convert:WEBP", [image, text])

    assert len(result["outputs"]) == 1
    assert Path(result["outputs"][0]).is_file()
    assert result["failures"] and "не подходят" in result["failures"][0]["message"]
    assert result["failures"][0]["stage"] == "validate"
    assert result["failures"][0]["code"] == "unsupported_type"
    assert image.is_file() and text.read_text(encoding="utf-8") == "keep me"


def test_protocol_echoes_request_and_engine_version(tmp_path):
    source = tmp_path / "source.png"
    Image.new("RGB", (12, 12), "white").save(source)

    result = handle({"request_id": "request-123", "action": "convert:WEBP",
                     "files": [str(source)], "settings": {"output": "next"}})

    assert result["request_id"] == "request-123"
    assert result["engine_version"]
    assert result["protocol_version"] == 1
    assert result["ok"] and Path(result["outputs"][0]).is_file()


def test_missing_inputs_are_reported_with_original_index(tmp_path):
    valid = tmp_path / "valid.png"
    missing = tmp_path / "missing.png"
    Image.new("RGB", (12, 12), "white").save(valid)

    result = _run("convert:WEBP", [missing, valid])

    assert len(result["outputs"]) == 1 and Path(result["outputs"][0]).is_file()
    assert result["failures"][0]["input_index"] == 0
    assert result["failures"][0]["stage"] == "read"
    assert result["failures"][0]["code"] == "input_missing"


def test_invalid_pdf_is_a_decode_error_not_a_file_access_request(tmp_path):
    broken = tmp_path / "broken.pdf"
    broken.write_bytes(b"this is not a PDF")

    result = _run("convert:TXT", [broken])

    assert result["outputs"] == []
    assert result["failures"][0]["stage"] == "decode"
    assert result["failures"][0]["code"] == "invalid_pdf"


def test_protected_pdf_is_reported_as_password_required(tmp_path):
    protected = tmp_path / "protected.pdf"
    document = convert.fitz.open()
    document.new_page().insert_text((72, 72), "private")
    document.save(protected, encryption=convert.fitz.PDF_ENCRYPT_AES_256,
                  owner_pw="owner-secret", user_pw="user-secret")
    document.close()

    result = _run("convert:TXT", [protected])

    assert result["outputs"] == []
    assert result["failures"][0]["stage"] == "decode"
    assert result["failures"][0]["code"] == "password_required"
    assert "user-secret" not in str(result)


def test_preview_returns_a_native_readable_image_and_original_dimensions(tmp_path, monkeypatch):
    source = tmp_path / "source.png"
    Image.new("RGB", (1600, 800), "white").save(source)
    monkeypatch.setenv("MULTISHIFT_CACHE_DIR", str(tmp_path / "cache"))

    result = handle({"operation": "preview", "path": str(source), "max_side": 800})

    preview = result["preview"]
    assert preview["source_width"] == 1600 and preview["source_height"] == 800
    assert max(preview["width"], preview["height"]) == 800
    Path(preview["path"]).unlink(missing_ok=True)


@pytest.mark.parametrize(("action", "parameters"), [
    ("tool:Crop", {"x": 3, "y": 4, "width": 20, "height": 12}),
    ("tool:Add BG", {"colors": ["#eeeeee", "#aaaaaa"], "padding": 0.1}),
    ("tool:Annotate", {"items": [{"kind": "rect", "box": [3, 4, 24, 18], "color": "#222222", "width": 3}]}),
    ("tool:Redact", {"rects": [[3, 4, 24, 18]], "mode": "pixelate"}),
    ("tool:Edit", {"brightness": 1.1, "grayscale": True, "rotate": 90}),
    ("tool:Metadata", {"mode": "strip"}),
    ("tool:Compress", {"quality": 70, "max_side": 32, "target": "webp"}),
    ("tool:Resize", {"mode": "exact", "width": 32, "height": 24, "keep_proportions": True}),
])
def test_native_image_tools_return_copies_without_changing_the_source(tmp_path, action, parameters):
    source = tmp_path / "source.png"
    Image.new("RGBA", (48, 32), (130, 170, 210, 255)).save(source)

    result = _run(action, [source], parameters)

    assert result["ok"] and len(result["outputs"]) == 1
    output = Path(result["outputs"][0])
    assert output.is_file() and output != source
    assert Image.open(source).size == (48, 32)
    Image.open(output).load()


def test_pdf_protection_tool_encrypts_a_copy_and_preserves_the_source(tmp_path):
    source = tmp_path / "source.pdf"
    document = convert.fitz.open()
    document.new_page().insert_text((72, 72), "private")
    document.save(source)
    document.close()

    result = _run("tool:Protect", [source], {"password": "test-password"})

    assert result["ok"] and len(result["outputs"]) == 1
    output = Path(result["outputs"][0])
    assert output.is_file() and source.is_file()
    protected = convert.fitz.open(output)
    try:
        assert protected.needs_pass
        assert protected.authenticate("test-password") > 0
    finally:
        protected.close()
