# Native refinements and output folder — 2026-11-11

Authorized request: correct inactive menu-bar styling, remove Advanced/Quit block,
unify sidebar toggle and flat app-owned marks, expose real MultiShift technical
information and selectable output folder, validate and publish both Sparkle updates.
Applied /Users/sokolovmo/.codex/skills/apple-native-app-design/SKILL.md and its
consistency/verification references. Preserved unrelated dirty-tree work.

## Implemented behavior

- MultiSwitcher status mark is now a black/transparent NSImage template instead
  of an attributed title with forced labelColor. AppKit owns inactive/pressed/menu-bar
  appearance. appearsDisabled reflects auto-correction availability while keeping the
  status item clickable; existing off-state strikethrough remains.
- Removed the standalone Quit card from Advanced. Existing native app/status menus
  and Cmd+Q remain; no duplicate settings exit block was added to MultiShift.
- Both use the same NSTitlebarAccessoryViewController and borderless native sidebar
  button; removed the separate SwiftUI toolbar item from MultiShift.
- About/sidebar marks use one shared transparent flat renderer. No additional tile,
  gradient, outline or shadow. Dock/distribution icons were not changed.
- MultiShift About now identifies engine version, macOS, architecture, bundle path,
  actual data directory and build identifier; technical details stay disclosed on demand.
- Files retains adjacent/subfolder modes and adds a chosen directory with full path,
  system NSOpenPanel and Open in Finder. Explains that MultiShift is a subfolder
  next to EACH original; no single global output folder is claimed.
- Selected folder is stored as a security-scoped bookmark and path, resolved again
  for each job. Destination and quality are frozen per job. Engine outputs remain in
  private staging; FileJobCoordinator publishes to the selected folder without replacing
  existing files. Missing/removed selection does not silently redirect output elsewhere.
- Isolated interactive review now permits sidebar folding; automatic capture mode
  retains its stable-layout behavior.

## Evidence

- Real exact ZIP candidates inspected with computer use on macOS 27.2 / SDK 27.2,
  isolated profiles, no live user file operations: same sidebar button, fold/unfold,
  flat marks in light/dark, expanded technical info, real folder picker and full selected
  test path. Advanced bottom was inspected and no Quit block remains.
- MultiSwitcher core executable: 313 passed; selected-text conversion: 111 assertions.
- SecureInputChecks passed; InteractionChecks passed focus, selection, deletion,
  disclosure opening/closing/reversal/resize, save failure, refresh/theme behavior.
- Common sidebar: 393 passed (1x/2x, four sizes, 40 animation reversals).
- Exact MultiSwitcher release binary: 100 native NSMenu state cycles passed.
- MultiShift core: 28 tests passed, including saved-folder reload, missing/removed folder,
  collision handling and original preservation. Python: 45 passed, 2 skipped.
- MultiShift AppearanceChecks: 8 transitions and reopened settings passed.
- Exact packaged engine functional audit: pause/resume, real PNG-to-JPG conversion,
  actual selected destination, undo, partial batch and modified-output protection passed.
  Original fixture unchanged. The initial directory audit compared URL directory flags;
  normalized path comparison fixed the test without changing publication behavior.
- Release distribution: 4 Switcher + 5 Shift tests passed, including real signatures
  and tampering checks with verified Sparkle tools. Build, extracted ZIP, mounted DMG,
  bundled resources and selftests passed.
- Final source archives contain matching current shared MultiDesignKit source.
- Published appcasts/ZIPs were downloaded, bytes/SHA256/signatures checked against
  local files and installed apps' unchanged public keys. Existing source/site/installer,
  download counter and previous archive links work. Main / still returns 403.
- Actual installed updaters offer the new versions with RU notes and enabled installation
  buttons. Install was not pressed; update dialogs left open for the owner.
- Existing proxy/server routes unchanged; no service restart or new proxy.

## Limits

The physical dimming of a status mark on a separate inactive display was not captured.
The code uses documented template/off-state APIs; do not call source proof a physical
multi-display acceptance test. Screen-sharing indicators and OS traffic lights remain
system-owned. Clean-Mac/older-OS installation, final installation/relaunch, VoiceOver
and owner acceptance remain separate. No new notarization is claimed.

Official API sources consulted:
https://developer.apple.com/documentation/appkit/nsimage/istemplate
https://developer.apple.com/documentation/appkit/nsstatusbarbutton/appearsdisabled
https://developer.apple.com/documentation/appkit/nsopenpanel

Temporary before-edit backups, logs, exact artifacts and functional fixtures:
/private/tmp/multi-refinement-20261111/

## MultiShift artifacts

Version: 0.3.3 (9)
ZIP: MultiShift-0.3.3-9-arm64.zip
ZIP SHA256: bf085e732ee4a7693918a6df363fdac90583eb4481fc1069da8f482a80477636
DMG SHA256: f85d29b146b04d601ceb72656dc00c1019260f65dcdaa221d47cfe0afaacf018
Current: /var/www/multishift/releases/build-9-bf085e732ee4a769
Previous: /var/www/multishift/releases/build-8-16ed60556c802199
Installed at verification: 0.3.2 (8)
Architecture: arm64; minimum macOS: 14.0; notarized: false.
