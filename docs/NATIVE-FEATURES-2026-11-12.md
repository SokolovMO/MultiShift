# Native feature expansion — 12 November 2026

Scope: implement the feature comparison requested in this chat, using `apple-native-app-design`.
The native shell remains AppKit/SwiftUI, macOS 14+, arm64. No server, proxy, installed
application or published update is replaced by this work.

## Implemented

- Native SwiftUI grouped forms and semantic system surfaces replace the limited editor.
  AppKit owns windows; AVKit owns playback; UserNotifications owns background banners.
- Results include operation context, byte savings, dimensions, page count, media duration
  and missing audio where applicable. Image notification attachments are downsampled using
  ImageIO. Open/Finder/Undo are contextual; clicking the body opens details. Dismissal
  does not open a window. Foreground feedback appears in editor and settings.
- Image target-size compression enforces the actual byte limit. This mode explicitly
  creates a JPEG copy and may reduce resolution or flatten transparency to white.
  Ordinary quality compression retains the existing format policy.
- Preview uses the same Python operation and encoder as Save Copy, including warmth,
  sharpness, auto enhancement and manual adjustments. It writes only temporary copies.
- Crop has aspect ratios, pixel coordinates/dimensions and rotation. Edit adds auto,
  flips and grayscale. Existing resize and background operations remain available.
- Markup supports multiple arrows/rectangles/ellipses, freehand pen, translucent marker,
  text and numbered steps, color, stroke width, undo/redo. Multiple redactions are burned
  into pixels, with metadata removed from their new copies.
- Metadata shows all fields, with a location warning/map action and location-only removal.
- A native reorderable list confirms PDF/image/audio/video combination before execution;
  buttons and keyboard selection complement drag reorder. Cancel submits no operation.
- Audio/video conversion and audio extraction, compression, trim, speed/gain/normalization,
  fades/mono for audio, video orientation/mute/resolution, metadata stripping and merge.
  A five-second sample can be processed and played using AVKit; media size is an estimate.
- New document routes cover Markdown/HTML, spreadsheets/data, presentations, older word
  formats, e-books/page documents, SVG, subtitles and archive format conversion. Markdown
  PDF output has typography, semantic lists, document title and page-number footer.
- Folder archiving to ZIP/TAR.GZ explicitly opts into directory staging. It skips symlinks
  and preserves originals; other operations continue rejecting directories at staging.
- Image-quality changes preserve supported ICC/EXIF, honor 16-bit/orientation, retain
  animation in capable conversion targets, support multipage TIFF→PDF, improve encodings,
  embed images efficiently in PDFs and use pdf2docx for layout-aware Word conversion.
- Existing private staging, no-overwrite publication, partial batch results and
  fingerprint-checked Trash undo are retained. Media/document output is not published
  until it passes the same file coordinator.
- FFmpeg and conversion libraries are bundled. Markdown extension imports are explicit;
  external converter diagnostics go to stderr, keeping stdout a valid single JSON response.
  Build selftests additionally exercise Markdown→PDF, CSV→XLSX and WAV→MP3.

## Evidence and limits

Runtime: macOS 27.2, arm64. Native shell links SDK 27.2 with minimum macOS 14.
Swift testing used `/Applications/Xcode.app/Contents/Developer`; no global toolchain setting changed.

Observed with computer-use tools: light-theme compression, actual 10 KB copy saving,
real multi-object arrows in dark appearance, Undo/Redo, saved markup, native order list
and row movement before combining two images, AVKit video playback/range input/processed
sample and real trim saving. The resulting video is 1.5 s long and retains audio.
UI tests use synthetic files and isolated audit preferences, with global input monitoring
disabled. For video, an identical-binary review copy had a separate bundle identifier to
prevent UI tooling selecting the installed application. No production profile was used
for conversions. Later backend packaging fixes do not change those rendered controls.

The local candidate is ad-hoc signed; no new notarization is claimed. No release is
published, no updater is offered, and the installed application is not replaced.
Real system notification presentation/actions with OS authorization/Focus, physical Finder
trigger gestures for every new family, VoiceOver, a clean/older Mac, Intel, optional
LibreOffice routes and owner acceptance remain unverified. The notification renderer and
routing compile; source or gateway checks are not evidence of delivered system banners.

LibreOffice remains an optional external dependency for DOC/XLS/PPT and additional
Office routes. Built-in presentation/Word rendering does not promise pixel-identical
Office layout. PDF→Word has a fallback and may require manual correction. Scanned-document
OCR was not added. Media target sizes are estimates; image target-size mode enforces bytes.
Animated formats retain animation in conversion paths, while image-editing tools operate
on a still frame and GIF/ICO edits produce PNG as before.

Automated logs and exact candidate paths are recorded below after final verification.

## Provenance

Adapted MIT-licensed DragShift PR #6 at `690cba9c1f96c6849c47ea7b294c60d26a5a4841`
and PR #15 at `5adf9ae41026671101f0abf8d118a4a850c7e5e2`; these are unmerged upstream
proposals, not assertions about upstream releases. Contributor notices are retained.
Folder/order/native UI changes were implemented locally.

Official design/API sources consulted:
- https://developer.apple.com/design/human-interface-guidelines/notifications
- https://developer.apple.com/documentation/usernotifications/unnotificationattachment
- https://developer.apple.com/documentation/swiftui/list

## Final verification

- Python: **416 passed, 26 skipped**, default pytest collection; log
  `/private/tmp/multishift-delivery-tests.log`. Skips include same-format pairs and
  platform/external-office cases. Known dependency deprecation/palette warnings remain.
- Swift: **29 passed, 0 failures**, including directory archive staging and original
  preservation; `/private/tmp/multishift-core-final.log`. Scoped-bookmark tests were run
  with access to the actual macOS service after the sandbox prevented that access.
- Packaged candidate: Markdown→PDF, CSV→XLSX, PNG→JPG, folder→ZIP, image render,
  bundled FFmpeg, processed media sample and PDF→Word passed through the real JSON
  worker. Result: `/private/tmp/multishift-packaged-feature-check/results.json`.
- Final shell/engine selftests and strict signature verification passed.
- Dependency-license paths are normalized so cleanup of Python `.dist-info` directories
  no longer deletes copied license notices. Bundled imageio-ffmpeg/pdf2docx license
  files were verified after packaging.
- Local artifact: `/Users/sokolovmo/Documents/MultiShift/dist/MultiShift-preview.app`.
  Version 0.3.3 (9), build `dda84a9d5e40-dirty-969b5056cf36135a`.
  This is a local development candidate, with automatic updates disabled.
- Final image preview preserves the Fit/100% controls and scrollable content; the
  final compiled review window exposed both native scale controls. Physical zoom
  scrolling, VoiceOver and system banner delivery are separate unverified paths.

Build log: `/private/tmp/multishift-ready-build.log`. No commit/push/installation or
publication was performed. The source tree contains the requested implementation.

Delivery archive: `dist/MultiShift-preview.zip`, generated from the clean verified
candidate and extracted again under `/private/tmp/multishift-final-archive-check`
for strict signature/selftest verification. Prefer the ZIP for transfer: this
workspace's File Provider can reintroduce FinderInfo metadata on loose `.app`
directories after copying, which makes strict code-signature validation fail even
though the executable and source have not changed. The ZIP preserves the clean bundle.
