#!/usr/bin/env python3
"""Render the editable SVG mark into the multi-resolution macOS ICNS asset."""
from __future__ import annotations

import shutil
import struct
import os
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / "dragshift" / "assets" / "multishift.svg"
BUILD_ROOT = Path(os.environ.get("MULTISHIFT_BUILD_CACHE_DIR", str(ROOT / "build")))
ICONSET = BUILD_ROOT / "MultiShift.iconset"
OUTPUT = Path(os.environ.get("MULTISHIFT_ICON_OUTPUT", str(ROOT / "dragshift" / "assets" / "multishift.icns")))
PREVIEW = BUILD_ROOT / "MultiShift-icon-preview.png"


def main() -> None:
    ICONSET.parent.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir()

    def render(dark: bool) -> Image.Image:
        master = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        mask = Image.new("L", master.size)
        ImageDraw.Draw(mask).rounded_rectangle((96, 96, 928, 928), radius=188, fill=255)
        shadow_mask = ImageChops.offset(mask, 0, 20).filter(ImageFilter.GaussianBlur(28))
        shadow = Image.new("RGBA", master.size, (0, 0, 0, 0))
        shadow.putalpha(shadow_mask.point(lambda a: round(a * 0.16)))
        master.alpha_composite(shadow)
        tile = Image.new("RGBA", master.size)
        d = ImageDraw.Draw(tile)
        for y in range(1024):
            t = max(0, min(1, (y - 96) / 832))
            white = round((47 if dark else 253) * (1-t) + (24 if dark else 230) * t)
            d.line((0, y, 1024, y), fill=(white, white, white, 255))
        master.paste(tile, (0, 0), mask)
        d = ImageDraw.Draw(master)
        edge = 76 if dark else 255
        d.rounded_rectangle((97, 97, 927, 927), radius=187, outline=(edge, edge, edge, 190), width=2)
        ink = (248, 248, 248, 255) if dark else (28, 28, 28, 255)
        # The approved arrow mark, constructed as editable vector geometry.
        d.line((512, 690, 512, 332), fill=ink, width=94)
        d.line((348, 482, 512, 318, 676, 482), fill=ink, width=94, joint="curve")
        for x, y in [(512, 690), (348, 482), (512, 318), (676, 482)]:
            d.ellipse((x-47, y-47, x+47, y+47), fill=ink)
        return master

    master = render(False)
    master.save(PREVIEW)
    master.save(BUILD_ROOT / "icon-light.png")
    render(True).save(BUILD_ROOT / "icon-dark.png")

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / filename)
    # Write the documented ICNS container directly. iconutil can reject otherwise valid
    # iconsets produced in restricted build environments, while ICNS is a simple chunk format.
    reps = [
        (b"icp4", 16), (b"icp5", 32), (b"icp6", 64),
        (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024),
        (b"ic11", 32), (b"ic12", 64), (b"ic13", 256), (b"ic14", 512),
    ]
    chunks = []
    for kind, size in reps:
        filename = next(name for name, dims in sizes.items() if dims == size)
        png_data = (ICONSET / filename).read_bytes()
        chunk = kind + struct.pack(">I", len(png_data) + 8) + png_data
        chunks.append(chunk)
    toc_data = b"".join(chunk[:4] + chunk[4:8] for chunk in chunks)
    toc = b"TOC " + struct.pack(">I", len(toc_data) + 8) + toc_data
    payload = toc + b"".join(chunks)
    OUTPUT.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(f"Generated {OUTPUT}")


if __name__ == "__main__":
    main()
