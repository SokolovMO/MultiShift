# Concurrent ecosystem edits — 23 October 2026

Two active chats received the same ecosystem request and edited the same checkouts. Current mixed sources are not a releasable build. Installed `/Applications/MultiShift.app` remains the verified preceding design pass, build `ad84241253df6d11`; the interrupted ecosystem builds were not installed.

Observed collisions:

- MultiSwitcher `SettingsWindowController.swift`: two `sidebarCollapsed` declarations and two layout controllers. The new `MultiSidebarHost` initialization coexists with the other controller's `layoutSidebar()`/timer. Keep one owner, not both.
- MultiShift `AppDelegate.swift`: `MultiDesign.visibleFrame` is main-actor isolated but is called by synchronous nonisolated window creation. Resolve isolation correctly; do not silence the compiler globally.
- Both trees now contain a Foundation/CoreGraphics `MultiInterfaceMetrics` geometry policy with three new regression tests. A second shared AppKit `MultiDesignKit.swift` also exists. Consolidate metrics instead of retaining incompatible constants (form width 560 versus 600, sidebar 0.26 versus 0.25 s).
- Common `MultiSidebarHost` offers actual-width native rows and an automatic collapse breakpoint with hysteresis, plus frame sampling. This is useful for one identical implementation across AppKit and SwiftUI; integrate rather than replace blindly.
- A completed 15-test MultiShift core run is in `shift-tests.log`. An isolated snapshot of MultiSwitcher core is being tested independently of the temporarily conflicting app shell.

Safety/recovery:

- MultiShift QA history restored atomically after verifying exactly one own undone test operation and that all retained original records were unchanged; original 20 entries recovered. Theme returned to `system` before quitting.
- Before-ecosystem source snapshots: `/private/tmp/MultiShift-before-ecosystem-20261023.tar.gz`, `/private/tmp/MultiSwitcher-before-ecosystem-20261023.tar.gz`.
- Previous verified app/settings/history backup: `~/Library/Application Support/MultiShift/Rollback/MultiShift-0.3.0-before-premium-final-20261023`.
- No reset of user working changes or business logic. Suspend overlapping edits until the user chooses an owner or explicitly authorizes coordination messages.

## Resolved after explicit user authorization

The user authorized cross-chat coordination. Owners were separated: this chat owns MultiShift; the other owns MultiSwitcher and the common kit. Duplicate controllers and incompatible constants were consolidated. Both standalone app builds now pass; the final kit is byte-identical, and metrics/spec parity is checked. The opening paragraphs above describe the earlier collision snapshot, not the final state. See REPORT.md for current acceptance evidence and limits. Installed applications were not replaced in this ecosystem iteration.
