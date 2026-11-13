<p align="right"><a href="CHANGELOG.md">Русский</a> · <b>English</b></p>

# Changelog

User-facing changes to MultiShift. Versions refer to the published macOS app; repository-only
work is listed separately. The project is in early 0.x development.

## Unreleased

- Shared presentation with MultiSwitcher: Russian by default, English via a link,
  themed headers, support pages, and contribution templates. Documentation and assets only;
  application code, released packages, and delta updates are unchanged.

- Split crop-field numeric bindings into typed helpers for hosted Swift compiler compatibility.

- Public repository documentation, English/Russian introduction, contribution and security policies.
- Required previous-release delta generation, real Sparkle selection checks, and publication gates.
- Removal of generated QA bundles and recordings from the current source tree.

## 0.4.1 · build 11 · 2026-11-13

- Explain why a result cannot be opened when its file was removed or cannot be opened.
- Route result-opening actions through a shared native handler.
- Add a signed 0.4.0 → 0.4.1 delta to the existing release feed: 187,494 bytes instead of
  a 130,291,174-byte full archive. Existing ZIP, DMG, and source archive are unchanged.

See [release verification](docs/RELEASE-0.4.1-11.md) and
[delta verification](docs/DELTA-UPDATES-2026-11-13.md).

## 0.4.0 · build 10 · 2026-11-12

- Native operation notifications with output actions and undo.
- Image editing previews, size-limited compression, annotations, redaction, and crop tools.
- Ordered combining and additional document, media, subtitle, and archive operations.
- Bundled FFmpeg and expanded conversion-quality checks.

See [feature scope](docs/NATIVE-FEATURES-2026-11-12.md) and
[release verification](docs/RELEASE-0.4.0-10.md) for limits and evidence.

## Earlier development

The project evolved from MIT-licensed DragShift into a native macOS application.
Earlier native UI, output-folder, history, and signed-update work is recorded in the Git history.
