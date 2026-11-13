"""Native-shell operations; outputs are copies and staging is never bypassed."""
from __future__ import annotations
import io
import os
import tarfile
import zipfile
from pathlib import Path
from PIL import Image
from .util import UserError, sibling


def archive_folder(src: Path, target: str) -> Path:
    from .convert import atomic_save
    if target not in ('ZIP', 'TAR.GZ'):
        raise UserError('Choose ZIP or TAR.GZ.')
    if src.is_symlink(): raise UserError("Choose a folder rather than a symbolic link.")
    out = sibling(src, ext='.zip' if target == 'ZIP' else '.tar.gz')
    def entries():
        for root, dirs, files in os.walk(src, followlinks=False):
            dirs[:] = sorted(d for d in dirs if not (Path(root) / d).is_symlink())
            yield Path(root), Path(src.name) / Path(root).relative_to(src)
            for name in sorted(files):
                path = Path(root) / name
                if path.is_file() and not path.is_symlink():
                    yield path, Path(src.name) / path.relative_to(src)
    def write(dst):
        if target == 'ZIP':
            with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as archive:
                for path, relative in entries(): archive.write(path, relative.as_posix())
        else:
            with tarfile.open(dst, 'w:gz') as archive:
                for path, relative in entries(): archive.add(path, relative.as_posix(), recursive=False)
    atomic_save(write, out)
    return out


def compress_under(path: Path, limit: int, max_side: int = 0) -> Path:
    from . import convert
    if limit < 1024: raise UserError('Choose a target of at least 1 KB.')
    image = convert.open_image(path)
    if max_side: image.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    # An explicit lossy copy makes the target meaningful even for a huge lossless source.
    image = convert.flatten(convert.to_srgb(image))
    while True:
        best = None
        low, high = 5, 95
        while low <= high:
            quality = (low + high) // 2
            buffer = io.BytesIO()
            convert.save_image(image, buffer, 'JPG', quality=quality, keep_meta=False)
            data = buffer.getvalue()
            if len(data) <= limit: best, low = data, quality + 1
            else: high = quality - 1
        if best:
            out = sibling(path, 'Compressed', '.jpg')
            convert.atomic_save(lambda dst: Path(dst).write_bytes(best), out)
            return out
        if min(image.size) <= 16:
            raise UserError('This target size is too small. Choose a larger limit.')
        image.thumbnail((max(1, int(image.width * .8)), max(1, int(image.height * .8))), Image.Resampling.LANCZOS)


def text_to_md(src: Path, cat='text') -> list[Path]:
    from . import convert
    out = sibling(src, ext='.md')
    text = convert.read_text(src)
    if src.suffix.lower() not in ('.txt', '.md'):
        lang = src.suffix.lstrip('.')
        fence = '`' * max(3, max((len(x) for x in __import__('re').findall(r'`+', text)), default=0) + 1)
        text = f'{fence}{lang}\n{text}\n{fence}\n'
    convert.atomic_save(lambda dst: Path(dst).write_text(text, encoding='utf-8'), out)
    return [out]


def pdf_to_md(src: Path, cat='pdf') -> list[Path]:
    from . import convert
    out = sibling(src, ext='.md')
    with convert.open_pdf(src) as document:
        text = '\n\n---\n\n'.join(page.get_text(sort=True) for page in document)
    convert.atomic_save(lambda dst: Path(dst).write_text(text, encoding='utf-8'), out)
    return [out]


def metrics(inputs: list[Path], outputs: list[Path]) -> dict:
    from .util import file_size
    from . import convert
    value = {'before_bytes': sum(file_size(p) for p in inputs),
             'after_bytes': sum(file_size(p) for p in outputs), 'output_count': len(outputs)}
    for label, paths in [('before', inputs), ('after', outputs)]:
        if len(paths) == 1:
            try:
                with Image.open(paths[0]) as im: value[label + '_dimensions'] = list(im.size)
            except Exception: pass
            if paths[0].suffix.lower() == '.pdf':
                try:
                    with convert.open_pdf(paths[0]) as doc: value[label + '_pages'] = len(doc)
                except Exception: pass
    if len(outputs) == 1:
        from . import media
        from .util import category
        if category(outputs[0]) in ("audio", "video"):
            info = media.probe(outputs[0])
            if info:
                value["duration"] = info.duration
                value["silent_video"] = bool(info.has_video and not info.has_audio)
    return value
