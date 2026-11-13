"""Turns 'what just happened' into a short, useful summary for the notification:
sizes saved, new dimensions, pages, fields removed…"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from . import l10n
from .util import category, file_size, human_size


@dataclass
class Result:
    title: str
    detail: str
    outs: list[Path]
    srcs: list[Path] = field(default_factory=list)
    good: str = ""     # highlighted figure, e.g. "−75%"

    @property
    def thumb(self) -> Path | None:
        for o in self.outs:
            if category(o) == "image":
                return o
        return None


@dataclass
class BatchResult:
    outputs: list[Path] = field(default_factory=list)
    failures: list[tuple[str, str]] = field(default_factory=list)
    succeeded_inputs: int = 0


def process_files(paths: list[str | Path], operation) -> BatchResult:
    """Run independent file operations to completion and keep successes if one fails."""
    result = BatchResult()
    for value in paths:
        path = Path(value)
        try:
            outputs = operation(path) or []
            if isinstance(outputs, (str, Path)):
                outputs = [outputs]
            result.outputs.extend(Path(output) for output in outputs if output)
            result.succeeded_inputs += 1
        except Exception as exc:  # one bad file must not discard other completed files
            result.failures.append((path.name, str(exc) or exc.__class__.__name__))
    return result


def dims(path: Path) -> tuple[int, int] | None:
    try:
        from PIL import Image
        with Image.open(path) as im:
            return im.size
    except Exception:
        return None


def pages(path: Path) -> int | None:
    try:
        from .convert import fitz
        with fitz.open(path) as d:
            return d.page_count
    except Exception:
        return None


def size_change(before: int, after: int) -> tuple[str, str]:
    """('2.4 MB → 610 KB', '75% smaller') — second part empty if no meaningful change."""
    text = f"{human_size(before)} → {human_size(after)}"
    if before <= 0:
        return text, ""
    pct = (1 - after / before) * 100
    if pct >= 1:
        return text, f"{pct:.0f}% smaller"
    if pct <= -1:
        return text, f"{-pct:.0f}% larger"
    return text, "same size"


def _dim_str(d) -> str:
    return f"{d[0]}×{d[1]}" if d else ""


def summarize(action: str, srcs: list, outs: list | BatchResult, extra: str = "") -> Result:
    batch = outs if isinstance(outs, BatchResult) else None
    outputs = batch.outputs if batch is not None else outs
    result = _summarize_complete(action, srcs, outputs, extra)
    if batch is not None and batch.failures:
        total = len(srcs)
        completed = batch.succeeded_inputs
        failures = "; ".join(f"{name}: {l10n.tr(message)}" for name, message in batch.failures[:2])
        if len(batch.failures) > 2:
            failures += f"; +{len(batch.failures) - 2}"
        if l10n.language() == "ru":
            result.title = "Готово с ошибками" if batch.outputs else "Не удалось обработать файлы"
            result.detail = f"Готово: {completed} из {total}; ошибок: {len(batch.failures)}"
        else:
            result.title = "Completed with errors" if batch.outputs else "Couldn't process files"
            result.detail = f"Completed: {completed} of {total}; failed: {len(batch.failures)}"
        if failures:
            result.detail += f" · {failures}"
    return result


def _summarize_complete(action: str, srcs: list, outs: list, extra: str = "") -> Result:
    if l10n.language() == "ru":
        return _summarize_ru(action, srcs, outs, extra)
    srcs = [Path(s) for s in srcs]
    outs = [Path(o) for o in outs if o]
    if not outs:
        return Result(action, extra or "Nothing was written", [], srcs)
    src = srcs[0] if srcs else outs[0]
    before = sum(file_size(s) for s in srcs if s.is_file())
    after = sum(file_size(o) for o in outs if o.is_file())
    kind, _, name = action.partition(":")
    o0 = outs[0]
    good = ""

    if kind == "convert":
        fmt = name
        if len(srcs) > 1 and len(outs) == 1:
            title = f"{len(srcs)} files → 1 {fmt}"
        elif len(outs) > 1 and len(srcs) == 1:
            n = pages(src)
            title = f"{n or len(outs)} pages → {len(outs)} {fmt}s"
        elif len(outs) > 1:
            title = f"{len(outs)} files → {fmt}"
        else:
            title = f"{src.suffix.lstrip('.').upper()} → {fmt}"
        bits = [o0.name if len(outs) == 1 else f"{o0.parent.name}/{o0.name} …"]
        d = dims(o0) if category(o0) == "image" else None
        if d:
            bits.append(_dim_str(d))
        if o0.suffix.lower() == ".pdf":
            n = pages(o0)
            if n:
                bits.append(f"{n} page{'s' if n != 1 else ''}")
        if category(o0) in ("audio", "video"):
            from . import media
            info = media.probe(o0)
            if info:
                bits.append(media.human_duration(info.duration))
                if info.has_video and not info.has_audio: bits.append("no sound")
        bits.append(human_size(after))
        return Result(title, " · ".join(bits), outs, srcs)

    if name == "Compress":
        sizes, verdict = size_change(before, after)
        title = f"Compressed {len(srcs)} files" if len(srcs) > 1 else "Compressed"
        if verdict.endswith("larger") or verdict == "same size":
            verdict = "already well compressed"
        return Result(title, sizes + (f" · {extra}" if extra else ""), outs, srcs, good=verdict)

    if name in ("Crop", "Resize", "Edit"):
        d0, d1 = dims(src), dims(o0)
        verb = {"Crop": "Cropped", "Resize": "Resized", "Edit": "Edited"}[name]
        if len(outs) > 1:
            return Result(f"{verb} {len(outs)} images", f"{human_size(before)} → {human_size(after)}", outs, srcs)
        detail = f"{_dim_str(d0)} → {_dim_str(d1)}" if d0 and d1 and d0 != d1 else _dim_str(d1)
        if extra:
            detail += f" · {extra}"
        return Result(verb, f"{detail} · {o0.name}", outs, srcs)

    if name == "Add BG":
        return Result("Background added", f"{_dim_str(dims(o0))} PNG · {human_size(after)} · {o0.name}", outs, srcs)

    if name == "Annotate":
        return Result("Annotated", f"{extra} · {o0.name}" if extra else o0.name, outs, srcs)

    if name == "Redact":
        return Result("Redacted", f"{extra} · {o0.name}" if extra else o0.name, outs, srcs,
                      good="burned into pixels")

    if name == "Metadata":
        return Result("Metadata removed", f"{extra} · {o0.name}" if extra else o0.name, outs, srcs,
                      good="private copy")

    if name == "Split":
        return Result(f"Split into {len(outs)} PDFs", f"{o0.name} …", outs, srcs)

    if name == "Merge":
        n = pages(o0)
        return Result(f"Merged {len(srcs)} PDFs", f"{n} pages · {human_size(after)} · {o0.name}", outs, srcs)

    if name == "Rotate":
        n = pages(o0)
        return Result("Rotated 90°", f"{n} page{'s' if n != 1 else ''} · {o0.name}", outs, srcs)

    if name == "Protect":
        return Result("Password protected", f"AES-256 · {o0.name}", outs, srcs, good="encrypted")

    if name == "Extract":
        return Result(f"Extracted {len(outs)} image{'s' if len(outs) != 1 else ''}",
                      f"{o0.parent.name}/ · {human_size(after)}", outs, srcs)

    # generic
    return Result(name or action, f"{o0.name} · {human_size(after)}", outs, srcs)


def _summarize_ru(action: str, srcs: list, outs: list, extra: str = "") -> Result:
    srcs = [Path(s) for s in srcs]
    outs = [Path(o) for o in outs if o]
    if not outs:
        return Result(action, extra or l10n.tr("Nothing was written"), [], srcs)
    src = srcs[0] if srcs else outs[0]
    before = sum(file_size(s) for s in srcs if s.is_file())
    after = sum(file_size(o) for o in outs if o.is_file())
    kind, _, name = action.partition(":")
    out = outs[0]

    if kind == "convert":
        if len(srcs) > 1 and len(outs) == 1:
            title = f"{len(srcs)} {l10n.file_word(len(srcs))} → 1 {name}"
        elif len(outs) > 1 and len(srcs) == 1:
            count = pages(src) or len(outs)
            title = f"{count} {l10n.page_word(count)} → {len(outs)} {name}"
        elif len(outs) > 1:
            title = f"{len(outs)} {l10n.file_word(len(outs))} → {name}"
        else:
            title = f"{src.suffix.lstrip('.').upper()} → {name}"
        bits = [out.name if len(outs) == 1 else f"{out.parent.name}/{out.name} …"]
        d = dims(out) if category(out) == "image" else None
        if d:
            bits.append(_dim_str(d))
        if out.suffix.lower() == ".pdf":
            n = pages(out)
            if n:
                bits.append(f"{n} {l10n.page_word(n)}")
        bits.append(human_size(after))
        return Result(title, " · ".join(bits), outs, srcs)

    if name == "Compress":
        sizes, verdict = size_change(before, after)
        title = f"Сжато · {len(srcs)} {l10n.file_word(len(srcs))}" if len(srcs) > 1 else "Сжато"
        if verdict.endswith("larger") or verdict == "same size":
            verdict = l10n.tr("already well compressed") if verdict.endswith("larger") else "без изменений"
        else:
            verdict = f"на {verdict.split('%')[0]}% меньше"
        return Result(title, sizes + (f" · {extra}" if extra else ""), outs, srcs, good=verdict)

    if name in ("Crop", "Resize", "Edit"):
        d0, d1 = dims(src), dims(out)
        verb = {"Crop": "Обрезано", "Resize": "Размер изменён", "Edit": "Изображение обработано"}[name]
        if len(outs) > 1:
            return Result(f"{verb}: {len(outs)} изображений", f"{human_size(before)} → {human_size(after)}", outs, srcs)
        detail = f"{_dim_str(d0)} → {_dim_str(d1)}" if d0 and d1 and d0 != d1 else _dim_str(d1)
        if extra:
            detail += f" · {extra}"
        return Result(verb, f"{detail} · {out.name}", outs, srcs)

    if name == "Add BG":
        return Result("Фон добавлен", f"{_dim_str(dims(out))} PNG · {human_size(after)} · {out.name}", outs, srcs)
    if name == "Annotate":
        return Result("Разметка добавлена", f"{extra} · {out.name}" if extra else out.name, outs, srcs)
    if name == "Redact":
        return Result("Данные скрыты", f"{extra} · {out.name}" if extra else out.name, outs, srcs,
                      good=l10n.tr("burned into pixels"))
    if name == "Metadata":
        return Result("Метаданные удалены", f"{extra} · {out.name}" if extra else out.name, outs, srcs,
                      good=l10n.tr("private copy"))
    if name == "Split":
        return Result(f"PDF разделён на {len(outs)} частей", f"{out.name} …", outs, srcs)
    if name == "Merge":
        n = pages(out)
        return Result(f"Объединено PDF: {len(srcs)}", f"{n} {l10n.page_word(n or 0)} · {human_size(after)} · {out.name}", outs, srcs)
    if name == "Rotate":
        n = pages(out)
        return Result("Поворот: 90°", f"{n} {l10n.page_word(n or 0)} · {out.name}", outs, srcs)
    if name == "Protect":
        return Result("PDF защищён паролем", f"AES-256 · {out.name}", outs, srcs, good="зашифровано")
    if name == "Extract":
        return Result(f"Извлечено изображений: {len(outs)}", f"{out.parent.name}/ · {human_size(after)}", outs, srcs)
    return Result(l10n.tr(name or action), f"{out.name} · {human_size(after)}", outs, srcs)
