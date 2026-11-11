# MultiShift 0.3.1 (7) — 2026-11-11

Published https://sokolovmo.ru/multishift/ from the actual working tree.
User authorized both apps and Sparkle publication. Applied apple-native-app-design
and apple-design, preserving unrelated edits and existing branding.

## Changes

Native SwiftUI action styles and rounded text fields replace custom button/focus
painting. Removed the duplicate overlay and shadow over the floating system material.
Removed root-wide monochrome tint. Notification test copy is shorter; foreground
notifications follow the configured macOS presentation style. UserNotifications owns
notification identity, backgrounds, placement and accessibility.

## Artifact and publication

- ZIP: MultiShift-0.3.1-7-arm64.zip
- SHA256: d2d05a291707ba2ff8c62796b8505ce7a6901b966a0c221e325f05be74c4d7d1
- DMG SHA256: 62d5b6aa2c9bfbb41b18a39bc4e378a26eca661d81d9dd5d6aeaa396893168c9
- Target: /var/www/multishift/releases/build-7-d2d05a291707ba2f
- Previous: /var/www/multishift/releases/site-6-ae8889bf5007878d
- Existing Sparkle key retained. Appcast has specific RU/EN notes.
- Public appcast/ZIP downloaded, signature verified against installed app public key,
  SHA256 and local bytes matched. Site/source/installer/download counter and previous
  archive links work. Existing proxy unchanged; no service restart.
- Not notarized; Apple Silicon / macOS 14+ as before.

## Verification

- Exact ZIP and mounted DMG signature/selftest checks passed.
- Swift core: 25 tests passed using full Xcode. Initial Command Line Tools run could
  not import XCTest; rerun with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer passed.
- Python: 45 passed, 2 skipped.
- AppearanceChecks: 8 light/dark/system transitions and reopened settings passed.
- HistoryChecks: identity, original-file preservation, relaunch policy and write failure passed.
- Distribution: 5 passed, including real signing/tamper checks using the verified
  shared Sparkle tool directory (rather than skipping its default missing path).
- Real exact candidate settings and native controls were inspected on macOS 27.2
  in an isolated interactive mode with no keyboard monitor/file actions.
- Permission status was authorized. Clicking the test button reported submission
  to macOS. The computer-use tool timed out obtaining Notification Center; a real
  system banner screenshot was not obtained. Submission is not visual acceptance.
- Actual installed 0.3.0 (6) queried Sparkle and offered 0.3.1 with Russian notes and
  enabled install button. Dialog left open; install not pressed.

Real 6 -> 7 install/relaunch, clean-Mac trust, physical system banner appearance,
older OS and global accessibility display settings remain unverified. No owner
acceptance claimed. Evidence: /private/tmp/multi-native-fix-20261111/ (temporary).

## Post-install verification

The owner subsequently reported installing both Sparkle updates. Rechecked
/Applications/MultiShift.app: 0.3.1 (7), and the running About view reports 0.3.1.
This establishes the completed owner-operated update and relaunch. Actual
file-operation acceptance and visual system-banner acceptance remain unverified.
