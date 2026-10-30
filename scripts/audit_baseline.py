#!/usr/bin/env python3
"""Capture source provenance without copying personal data into the audit."""
import datetime
import hashlib
import json
import pathlib
import shutil
import subprocess

SHIFT = pathlib.Path(__file__).resolve().parents[1]
ROOT = SHIFT / "macos-ui-audit"
SOURCES = {"multishift": SHIFT, "multiswitcher": SHIFT.parent / "MultiSwitcher"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def main():
    ROOT.mkdir(exist_ok=True)
    target = ROOT / "baseline.json"
    if target.exists():
        raise SystemExit("Baseline already exists; preserve it.")
    snapshot = pathlib.Path("/private/tmp/multi-ui-audit-baseline-20261025")
    snapshot.mkdir(exist_ok=False)
    result = {"captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "snapshot": str(snapshot), "projects": {}, "preserved_files": {}}
    for name, repo in SOURCES.items():
        def git(*args):
            return subprocess.check_output(["git", "-C", str(repo), *args], text=True)
        status = git("status", "--porcelain")
        patch = git("diff", "--binary")
        (ROOT / "baseline").mkdir(exist_ok=True)
        (ROOT / "baseline" / (name + ".patch")).write_text(patch)
        dest = snapshot / name
        dest.mkdir()
        for entry in ["macos", "scripts", "dragshift", "dicts", "tests", "engine_main.py", "DragShift.spec", "requirements-macos.lock", "requirements.txt", "licenses", "LICENSE", "THIRD-PARTY-NOTICES.md", "TRADEMARKS.md"]:
            src = repo / entry
            if src.is_dir():
                shutil.copytree(src, dest / entry, ignore=shutil.ignore_patterns(".build", "__pycache__", "*.pyc"))
            elif src.is_file():
                shutil.copy2(src, dest / entry)
        source_hashes = {str(p.relative_to(repo)): digest(p) for p in (repo / "macos" / "Sources").rglob("*.swift")}
        result["projects"][name] = {"commit": git("rev-parse", "HEAD").strip(), "status": status,
                                             "source_sha256": source_hashes}
    home = pathlib.Path.home()
    preserved = [home / "Library/Application Support/MultiSwitcher/profile.json",
                 home / "Library/Application Support/MultiShift/operations.json",
                 home / "Library/Preferences/com.multiswitcher.app.plist",
                 home / "Library/Preferences/com.multiswitcher.multishift.plist"]
    for name in ["MultiShift", "MultiSwitcher"]:
        app = pathlib.Path("/Applications") / (name + ".app")
        preserved.extend([app / "Contents/MacOS" / name, app / "Contents/Info.plist"])
    labels = ["MultiSwitcher profile and learning data", "MultiShift operation history",
              "MultiSwitcher preferences", "MultiShift preferences",
              "Installed MultiShift executable", "Installed MultiShift bundle metadata",
              "Installed MultiSwitcher executable", "Installed MultiSwitcher bundle metadata"]
    for label, path in zip(labels, preserved):
        result["preserved_files"][label] = {"present_at_baseline": path.exists(), "content_digest_redacted": True}
    target.write_text(json.dumps(result, indent=2) + "\n")
    print("baseline captured:", snapshot)


if __name__ == "__main__":
    main()
