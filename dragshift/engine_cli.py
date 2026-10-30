"""JSON-lines command interface used by the native macOS shell.

This module deliberately imports no Qt or Cocoa UI modules. The Swift app owns all
windows and the menu-bar item; this process only reads files and writes result copies.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from . import convert, imaging
from . import __version__
from .util import CONFIG, UserError, category

PROTOCOL_VERSION = 1


def _failure(index: int, path: Path, error: Exception, stage: str = "convert") -> dict[str, Any]:
    message = "The file could not be processed."
    code = "conversion_failed"
    if stage == "validate":
        code = "unsupported_type"
        message = str(error)
    elif isinstance(error, PermissionError) or (isinstance(error, OSError) and error.errno in (1, 13)):
        code, stage = "permission_denied", "save"
        message = "The result could not be saved. Choose another output folder."
    elif isinstance(error, FileNotFoundError):
        code, stage = "input_missing", "read"
        message = "The source file could not be found."
    elif isinstance(error, UserError) and "password" in str(error).lower():
        code, stage = "password_required", "decode"
        message = str(error)
    else:
        try:
            if isinstance(error, convert.fitz.FileDataError):
                code, stage = "invalid_pdf", "decode"
                message = "The PDF could not be parsed. It may be damaged or use an unsupported format."
        except AttributeError:
            pass
        if isinstance(error, UserError):
            message = str(error)
    return {"input_index": index, "file": path.name, "stage": stage,
            "code": code, "message": message}


def _preview(path: Path, limit: int = 1800) -> dict[str, Any]:
    kind = category(path)
    if kind == "image":
        image = convert.open_preview(path, limit)
    elif kind == "pdf":
        doc = convert.open_pdf(path)
        try:
            page = doc.load_page(0)
            pix = page.get_pixmap(matrix=convert.fitz.Matrix(1.4, 1.4), alpha=False)
            image = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
            image.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        finally:
            doc.close()
    else:
        raise UserError("Предпросмотр доступен для изображений и PDF.")
    cache_root = Path(os.environ.get(
        "MULTISHIFT_CACHE_DIR", str(Path.home() / "Library" / "Caches" / "MultiShift")
    ))
    target = cache_root / "Previews"
    target.mkdir(parents=True, exist_ok=True)
    output = target / f"{path.stem}-{uuid.uuid4().hex[:12]}.png"
    image.save(output, "PNG", optimize=True)
    dimensions = None
    try:
        with Image.open(path) as original:
            oriented = convert.open_image(path)
            dimensions = list(oriented.size)
    except Exception:
        pass
    return {"path": str(output), "width": image.width, "height": image.height,
            "source_width": dimensions[0] if dimensions else None,
            "source_height": dimensions[1] if dimensions else None}


def _run_one(path: Path, action: str, p: dict[str, Any]) -> list[Path]:
    kind, _, name = action.partition(":")
    if kind == "convert":
        return convert.convert(path, category(path) or "", name)
    if kind != "tool":
        raise UserError("Неизвестное действие.")

    if name == "Compress":
        if category(path) == "pdf":
            return [imaging.compress_pdf(path, int(p.get("pdf_dpi", 150)), int(p.get("quality", 70)))]
        return [imaging.compress_to(path, int(p.get("quality", 72)),
                                    int(p["max_side"]) if p.get("max_side") else None,
                                    str(p.get("target") or imaging.lossy_target(path, bool(p.get("to_webp")))))]
    if name == "Resize":
        source = convert.open_image(path)
        mode = str(p.get("mode", "pct"))
        value = int(p.get("value", 50))
        if mode == "exact":
            width, height = max(1, int(p["width"])), max(1, int(p["height"]))
            if p.get("keep_proportions"):
                ratio = min(width / source.width, height / source.height)
                dims = max(1, round(source.width * ratio)), max(1, round(source.height * ratio))
            else:
                dims = width, height
        else:
            dims = imaging.resize_dims(source.size, mode, value)
        return [imaging.resize_image(path, dims)]
    if name == "Crop":
        image = convert.open_image(path)
        x, y, w, h = (int(p[k]) for k in ("x", "y", "width", "height"))
        x, y = max(0, min(x, image.width - 1)), max(0, min(y, image.height - 1))
        w, h = max(1, min(w, image.width - x)), max(1, min(h, image.height - y))
        return [imaging.save_like(image.crop((x, y, x + w, y + h)), path, "Cropped")]
    if name == "Edit":
        image = convert.open_image(path)
        adjust = imaging.Adjust(
            brightness=float(p.get("brightness", 1)), contrast=float(p.get("contrast", 1)),
            saturation=float(p.get("saturation", 1)), warmth=float(p.get("warmth", 0)),
            sharpness=float(p.get("sharpness", 1)), rotate=int(p.get("rotate", 0)) % 360,
            grayscale=bool(p.get("grayscale", False)), flip_h=bool(p.get("flip_h", False)),
            flip_v=bool(p.get("flip_v", False)))
        return [imaging.save_like(imaging.apply_adjust(image, adjust), path, "Edited")]
    if name == "Add BG":
        image = convert.open_image(path)
        bg = imaging.Background(colors=list(p.get("colors", ["#E9E9EB", "#BFC0C4"])),
                               angle=float(p.get("angle", 135)), padding=float(p.get("padding", .12)),
                               radius=int(p.get("radius", 24)), shadow=float(p.get("shadow", .35)),
                               aspect=str(p.get("aspect", "Auto")))
        return [imaging.save_like(imaging.add_background(image, bg), path, "Background", ".png")]
    if name == "Redact":
        image = convert.open_image(path)
        rects = [tuple(int(v) for v in rect) for rect in p.get("rects", [])]
        return [imaging.save_like(imaging.redact(image, rects, str(p.get("mode", "black"))), path, "Redacted")]
    if name == "Annotate":
        image = convert.open_image(path).convert("RGBA")
        draw = ImageDraw.Draw(image)
        scale = max(1, int(p.get("stroke", 5)))
        for item in p.get("items", []):
            kind = item.get("kind", "text")
            box = tuple(int(v) for v in item.get("box", []))
            color = str(item.get("color", "#111111"))
            width = max(1, int(item.get("width", scale)))
            if len(box) < 4:
                continue
            if kind == "rect":
                draw.rectangle(box, outline=color, width=width)
            elif kind == "ellipse":
                draw.ellipse(box, outline=color, width=width)
            elif kind == "redact":
                draw.rectangle(box, fill=color)
            elif kind == "arrow":
                draw.line(box, fill=color, width=width)
                import math
                x0, y0, x1, y1 = box
                theta = math.atan2(y1 - y0, x1 - x0)
                length = max(12, width * 4)
                for offset in (-.55, .55):
                    a = theta + math.pi + offset
                    draw.line((x1, y1, x1 + length * math.cos(a), y1 + length * math.sin(a)), fill=color, width=width)
            elif kind == "text":
                text = str(item.get("text", ""))
                if text:
                    draw.text((box[0], box[1]), text, fill=color, font=ImageFont.load_default(size=max(12, width * 4)))
        return [imaging.save_like(image, path, "Annotated")]
    if name == "Metadata":
        mode = str(p.get("mode", "strip"))
        if category(path) == "pdf":
            return [imaging.strip_pdf_metadata(path)] if mode == "strip" else []
        return [imaging.strip_location(path) if mode == "location" else imaging.strip_image_metadata(path)]
    if name == "Split":
        return imaging.split_pdf(path)
    if name == "Rotate":
        return [imaging.rotate_pdf(path, int(p.get("degrees", 90)))]
    if name == "Extract":
        return imaging.extract_pdf_images(path)
    if name == "Protect":
        password = str(p.get("password", ""))
        if len(password) < 4:
            raise UserError("Введите пароль длиной не менее 4 символов.")
        return [imaging.protect_pdf(path, password)]
    if name == "Merge":
        raise UserError("Для объединения выберите несколько PDF.")
    raise UserError("Это действие пока недоступно.")


def handle(request: dict[str, Any]) -> dict[str, Any]:
    request_id = request.get("request_id")
    base = {"request_id": request_id, "engine_version": __version__,
            "protocol_version": PROTOCOL_VERSION}
    operation = str(request.get("operation", ""))
    if operation == "version":
        return {**base, "ok": True}
    if operation == "preview":
        path = Path(str(request.get("path", ""))).expanduser()
        try:
            limit = max(800, min(4096, int(request.get("max_side", 1800))))
        except (TypeError, ValueError):
            limit = 1800
        return {**base, "ok": True, "preview": _preview(path, limit)}
    if operation == "inspect":
        path = Path(str(request.get("path", ""))).expanduser()
        if category(path) == "pdf":
            fields = imaging.read_pdf_metadata(path)
            has_location = False
            count = len(fields)
        else:
            fields = imaging.read_image_metadata(path)
            count, has_location = imaging.count_metadata(path)
        return {**base, "ok": True, "fields": fields, "metadata_count": count,
                "has_location": has_location}
    settings = request.get("settings", {})
    if isinstance(settings, dict):
        CONFIG["output"] = "folder" if settings.get("output") == "folder" else "next"
        try:
            CONFIG["jpg_quality"] = max(60, min(100, int(settings.get("jpg_quality", 90))))
            CONFIG["pdf_dpi"] = max(72, min(600, int(settings.get("pdf_dpi", 200))))
        except (TypeError, ValueError):
            pass
    action = str(request.get("action", ""))
    raw_paths = request.get("files", [])
    paths = [Path(str(p)).expanduser() for p in raw_paths] if isinstance(raw_paths, list) else []
    if not paths:
        return {**base, "ok": False, "outputs": [], "action": str(request.get("action", "")),
                "failures": [{"input_index": 0, "file": "", "stage": "read",
                              "code": "input_missing", "message": "No source files were provided."}]}
    parameters = request.get("parameters", {})
    parameters = parameters if isinstance(parameters, dict) else {}
    outputs = []
    failures = [_failure(index, path, FileNotFoundError(path.name), "read")
                for index, path in enumerate(paths) if not path.is_file()]
    selected = [(index, path) for index, path in enumerate(paths) if path.is_file()]
    expected = category(selected[0][1]) if selected else ""
    compatible = [(index, path) for index, path in selected if category(path) == expected]
    failures.extend(_failure(index, path, UserError("Некоторые файлы не подходят для выбранного действия."), "validate")
                    for index, path in selected if category(path) != expected)
    if action == "convert:PDF" and expected == "image" and len(selected) > 1:
        if not failures and len(compatible) == len(paths):
            outputs = convert.images_to_single_pdf([path for _, path in compatible])
    elif action == "tool:Merge":
        if len(compatible) < 2 or expected != "pdf":
            failures.append({"input_index": None, "file": "", "stage": "validate",
                             "code": "invalid_selection", "message": "Choose at least two PDF files."})
        elif not failures and len(compatible) == len(paths):
            outputs = [imaging.merge_pdfs([path for _, path in compatible])]
    else:
        for index, path in compatible:
            try:
                outputs.extend(_run_one(path, action, parameters) or [])
            except Exception as error:  # retain successful files in a mixed batch
                failures.append(_failure(index, path, error))
    return {**base, "ok": bool(outputs) and not failures, "outputs": [str(p) for p in outputs],
            "failures": failures, "action": action}


def main() -> int:
    request: Any = None
    try:
        if "--selftest" in sys.argv:
            with tempfile.TemporaryDirectory(prefix="multishift-engine-") as directory:
                root = Path(directory)
                source = root / "sample.png"
                Image.new("RGB", (24, 18), (80, 80, 80)).save(source)
                response = handle({"action": "convert:WEBP", "files": [str(source)], "settings": {}})
                if not response.get("outputs") or not Path(response["outputs"][0]).is_file():
                    raise RuntimeError("conversion did not create a result")
                old_cache = os.environ.get("MULTISHIFT_CACHE_DIR")
                os.environ["MULTISHIFT_CACHE_DIR"] = str(root / "cache")
                try:
                    preview = handle({"operation": "preview", "path": str(source), "max_side": 800})
                    preview_path = Path(preview["preview"]["path"])
                    if not preview_path.is_file():
                        raise RuntimeError("preview did not create an image")
                finally:
                    if old_cache is None:
                        os.environ.pop("MULTISHIFT_CACHE_DIR", None)
                    else:
                        os.environ["MULTISHIFT_CACHE_DIR"] = old_cache
            print("ENGINE SELFTEST OK")
            return 0
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise ValueError("Request must be a JSON object.")
        response = handle(request)
        print(json.dumps(response, ensure_ascii=False))
        return 0 if response.get("ok", False) else 1
    except Exception as error:
        request_id = request.get("request_id") if isinstance(request, dict) else None
        operation = request.get("operation") if isinstance(request, dict) else None
        if operation in ("preview", "inspect"):
            raw_path = request.get("path", "")
            failure = _failure(0, Path(str(raw_path)), error, "decode")
            if failure["code"] == "permission_denied":
                failure["stage"] = "read"
                failure["message"] = "The file could not be read."
            message = failure["message"]
        else:
            message = "The processing engine stopped unexpectedly."
            failure = {"input_index": None, "file": "", "stage": "engine",
                       "code": "engine_error", "message": message}
        print(json.dumps({"request_id": request_id, "engine_version": __version__,
                          "protocol_version": PROTOCOL_VERSION, "ok": False,
                          "error": message,
                          "failures": [failure],
                          "outputs": []}, ensure_ascii=False))
        return 1
