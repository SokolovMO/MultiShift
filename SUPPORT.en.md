<p align="right"><a href="SUPPORT.md">Русский</a> · <b>English</b></p>

# MultiShift support

[Download](https://sokolovmo.ru/multishift/) · [Install](README.en.md#install) ·
[Report a bug](https://github.com/SokolovMO/MultiShift/issues/new/choose)

## The app will not open

Check macOS 14+ and Apple Silicon. Current builds are ad-hoc signed and not Apple-notarized.
After attempting to open a trusted download, macOS may offer approval in System Settings →
Privacy & Security. Do not disable system protection globally. See [distribution](docs/DISTRIBUTION.md).

## The action wheel does not appear

Start dragging a supported file in Finder, then press your configured key. Confirm MultiShift
is running, not paused, and uses the key you expect. Include the format and exact steps in reports.

## A result cannot be opened

History records operations; it is not a backup. If an output was moved or removed, check the
output folder and Trash, or recreate the copy from the original. Build 11 explains missing
files and failed opening requests.

## A conversion is unavailable or differs from the source

Actions depend on the input format. Legacy DOC/XLS/PPT needs LibreOffice separately.
Published builds include FFmpeg. Complex documents may need manual correction; scanned PDF OCR
is not included. See [format limits](docs/NATIVE-FEATURES-2026-11-12.md).

## An update downloads a large package

Deltas require a matching base build. First installation, Homebrew, and fallback use the full
archive. The published 0.4.0 → 0.4.1 delta is 183 KiB; future sizes depend on changes.
See [delta verification](docs/DELTA-UPDATES-2026-11-13.md).

## Report a problem

Include the app version/build, macOS, chip, installation method, input format, steps, expected
result, and actual result. Attach synthetic files and inspect captures/logs for private data.
English and Russian are welcome. There is no guaranteed response time. Report vulnerabilities
[privately](SECURITY.en.md).
