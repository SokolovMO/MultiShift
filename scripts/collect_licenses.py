#!/usr/bin/env python3
"""Collect runtime dependency notices into the macOS app bundle."""
from __future__ import annotations

import re
import shutil
import sys
from importlib import metadata
from pathlib import Path

from packaging.requirements import Requirement

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "third_party_licenses"
REQUIREMENTS = ROOT / "requirements.txt"
REQUIRED_LICENSES = {"pymupdf"}
PROJECT_LICENSES = [
    ("LICENSE", "Project/AGPL-3.0.txt"),
    ("licenses/third-party-components-MIT.txt", "Components/MIT.txt"),
    ("licenses/LGPL-3.0.txt", "Qt/LGPL-3.0.txt"),
    ("licenses/GPL-3.0.txt", "Qt/GPL-3.0.txt"),
    ("THIRD-PARTY-NOTICES.md", "MultiShift-THIRD-PARTY-NOTICES.md"),
]


def _normalized(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def _runtime_distributions() -> list[metadata.Distribution]:
    pending: list[str] = []
    for raw in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        req = Requirement(line)
        if req.marker is None or req.marker.evaluate():
            pending.append(req.name)

    found: dict[str, metadata.Distribution] = {}
    while pending:
        name = pending.pop()
        key = _normalized(name)
        if key in found:
            continue
        dist = metadata.distribution(name)
        found[key] = dist
        for raw in dist.requires or []:
            req = Requirement(raw)
            if req.marker is None or req.marker.evaluate():
                dependency = _normalized(req.name)
                if dependency not in found:
                    pending.append(req.name)
    return sorted(found.values(), key=lambda d: _normalized(d.metadata.get("Name", "")))


def _license_paths(dist: metadata.Distribution) -> list[tuple[str, Path]]:
    matches: list[tuple[str, Path]] = []
    for entry in dist.files or []:
        rel = Path(str(entry))
        name = rel.name.lower()
        in_license_dir = any(part.lower() in {"license", "licenses"} for part in rel.parts[:-1])
        text_file = name.endswith((".txt", ".md", ".rst", ".html"))
        named_license = name in {"license", "copying", "notice", "copyright"}
        looks_like_license = named_license or (text_file and name.startswith(("license", "copying", "notice", "copyright")))
        looks_like_license = looks_like_license or (in_license_dir and text_file)
        if not looks_like_license:
            continue
        source = Path(dist.locate_file(entry))
        if source.is_file():
            safe_rel = Path(*(part for part in rel.parts if part not in {".", ".."}))
            if safe_rel.parts:
                matches.append((safe_rel.as_posix(), source))
    return matches


def collect_license_data() -> list[tuple[str, str]]:
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)

    distributions = _runtime_distributions()
    missing_required = set(REQUIRED_LICENSES)
    index: list[str] = [
        "MultiShift runtime dependency licenses",
        "These are the installed runtime packages selected by requirements.txt and their transitive dependencies.",
        "See THIRD-PARTY-NOTICES.md in the source repository for project-level licensing information.",
        "",
    ]
    data: list[tuple[str, str]] = []
    for relative, destination in PROJECT_LICENSES:
        source = ROOT / relative
        if not source.is_file():
            raise RuntimeError(f"Required project license/notice file is missing: {relative}")
        target = OUTPUT / "project" / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        data.append((str(target), "ThirdPartyLicenses/" + destination))
    for dist in distributions:
        name = dist.metadata.get("Name", "unknown")
        version = dist.version
        license_label = dist.metadata.get("License-Expression") or dist.metadata.get("License") or "See included license files"
        urls = [value for value in dist.metadata.get_all("Project-URL", []) if value.lower().startswith(("homepage,", "source,"))]
        index.append(f"{name} {version} — {license_label}" + (f" — {urls[0].split(',', 1)[1].strip()}" if urls else ""))

        package_dir = OUTPUT / f"{_normalized(name)}-{version}"
        matches = _license_paths(dist)
        if matches:
            package_dir.mkdir(parents=True, exist_ok=True)
            for rel, source in matches:
                target = package_dir / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                data.append((str(target), "ThirdPartyLicenses/" + target.relative_to(OUTPUT).as_posix()))
            missing_required.discard(_normalized(name))
        elif _normalized(name) in REQUIRED_LICENSES:
            raise RuntimeError(f"The {name} wheel has no license text to include in the application bundle")

    if missing_required:
        raise RuntimeError("Missing required license files for: " + ", ".join(sorted(missing_required)))
    (OUTPUT / "MultiShift-NOTICES.txt").write_text("\n".join(index) + "\n", encoding="utf-8")
    data.append((str(OUTPUT / "MultiShift-NOTICES.txt"), "ThirdPartyLicenses/MultiShift-NOTICES.txt"))
    return data


if __name__ == "__main__":
    files = collect_license_data()
    print(f"Collected {len(files)} dependency notices into {OUTPUT}")
