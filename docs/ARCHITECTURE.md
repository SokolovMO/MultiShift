# Architecture

MultiShift combines a native macOS shell with an isolated Python conversion worker.

## Native app

`macos/Sources/` owns the menu bar companion, Finder drag/shortcut interaction, action chooser,
editors, settings, operation history, notifications, and Sparkle integration. SwiftUI and AppKit
provide the interface; system components own dialogs and notifications.

`macos/Sources/Core/` contains independently testable logic: geometry, engine requests,
job coordination, notification dispatch, output opening, and audit storage isolation.
`macos/Package.swift` exposes that core to `swift test`; it does not build the complete app.

## Conversion worker

`dragshift/` contains conversion, document, media, image, archive, and reporting logic.
`engine_main.py` exposes the packaged worker entry point. The native shell calls it through
`EngineClient`, with per-job staging managed by `FileJobCoordinator`.

The Python module name and legacy Qt entry points preserve DragShift lineage. They are not
separate Windows/Linux product commitments. Optional converters, such as LibreOffice, must
be present for the routes that need them.

## Outputs and storage

Outputs are copies. Private staging separates intermediate work from completed results.
The native model stores operation history on the Mac; undo moves generated files to the Trash.
Test launches can use an isolated audit data root and defaults namespace so fixtures do not
replace real operation history. See `MultiAuditEnvironment` for the supported variables.

## Build and distribution

`scripts/build_macos.sh` freezes the Python worker, builds the Swift shell, adds licenses and
assets, signs the bundle ad-hoc, and checks its selftest. `scripts/build_release.py` creates
signed distribution artifacts. `scripts/release_deltas.py` generates and verifies BinaryDelta
patches from exact signed old and new bundles. `scripts/check_delta_client.py` checks real
Sparkle selection and selected-URL downloads without installing into the user's app.

`scripts/publish_release.py` verifies artifacts and switches the static release atomically.
Signing secrets remain outside Git. See [distribution](DISTRIBUTION.md) and [security](../SECURITY.md).

The optional `download-service/` counts website download starts; it is not required to run or
build the app. `release-site/` contains the download page template. Generated builds, runtime
captures, and design QA recordings belong in ignored local storage rather than the source tree.
