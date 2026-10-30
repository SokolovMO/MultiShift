# multi ecosystem interface specification

Status: implementation in progress, 23 October 2026. Applies independently to MultiShift and MultiSwitcher.

## Evidence and scope

MultiShift's first redesign pass is installed and has real screenshots, 20 fast sidebar cycles per theme, PNG→JPG/undo evidence and a fixed SwiftUI lazy-history accessibility crash in `docs/qa-20261023/`. These checks are a baseline, not acceptance of the ecosystem task. Its QA operation was removed only after matching all existing history records against the backup; the original 20 records were restored.

MultiSwitcher source and installed app differ: the installed app still exposes capitalized legacy settings; current source already has monochrome controls and a rule dialog. Source inspection confirms page expansion hides the entire sidebar, is restricted to three sections, and uses independent frame/alpha animations followed by completion-time document sizing. Settings cards are horizontally centred at a maximum width, and the rule dialog explicitly enables resizing/fullscreen. These conflict with the requested canonical behaviour.

No image references were accessible with either pasted request. Visual acceptance against an approved concept remains unverified until those references are available.

## Shared geometry

All sizes are logical points; fonts and controls never scale with window size. Shared Foundation-only metrics/geometry are vendored identically into each app, with regression tests. A shared external package would introduce a build-time checkout dependency into MultiShift's direct swiftc build; independent copies with parity verification keep both applications self-contained. No business logic is shared.

- sidebar: 208 expanded, 60 compact; 32 row, 4 row gap, 12 horizontal inset; 20 symbol box, 7 selection radius.
- page: 24 inset, top/leading aligned; form maximum 560; tables use available width, with a bounded minimum and local scrolling.
- window defaults: MultiSwitcher 860×600, MultiShift 800×560 content; minima 700×480 and 680×460, constrained to the available display.
- spacing: 4/8/12/16/24; body 12–14, annotation 11–12, heading 20; card radius 12, control radius 7.
- compact mode: preserve icons, selection, tooltips, accessibility names, vertical positions and keyboard navigation. No disappearance, oversized selected row hidden by a mask, or conditional sidebar reconstruction.
- sidebar geometry has a single progress owner. Selection, icon position and label opacity derive from that progress. SwiftUI layout receives the actual intermediate width. AppKit lays out both columns in one pass from the same progress value, including during reversal/resize. Label opacity does not alter intrinsic dimensions.

## Responsive rules

Measure available content width, never physical display width. A form is `min(available width - 48, 560)` with one fixed leading guide. Lists/tables grow with useful space. Shorter windows scroll locally. Narrow field groups wrap/stack when they cannot fit, preserving reading order and actions. Compact navigation may be requested manually; narrow-window adaptation must preserve the user's choice and not oscillate at a threshold. Resizing does not change font, selected section, field input or scroll position unexpectedly.

Settings windows support ordinary edge resize and zoom, never primary fullscreen. Save frame on move/resize/close; restore onto a current visible display and clamp the entire frame. Changing section/theme must never resize or recreate the window. Closing settings leaves the utility running.

## Monochrome components and forms

Black/white/graphite only for owned UI. Native traffic lights, permission panels and file pickers remain system-owned. Keep a visible neutral focus indication; support keyboard, VoiceOver, disabled and pressed states. Apply tokens to nested controls, sheets, popovers and alerts. User filenames, paths, rule patterns and technical diagnostics retain exact case.

The rule editor is a compact standalone form (no sidebar), fixed comfortable width, left-aligned labels, consistent field heights/gaps, a neutral surface and bottom trailing cancel/save. Keep every field, validation, tab chain, return/escape and save semantics. Do not allow pointless fullscreen or unconstrained resizing.

## Motion and feedback

Hover 0.12 s, press 0.10 s, navigation 0.16 s, sidebar 0.26 s critically damped/no overshoot, popover 0.18 s, feedback 0.22 s. Geometry and content animate in one transaction/controller; interrupt from the displayed value. Reduce Motion uses direct geometry with optional short opacity feedback. No idle animation timers. A frame-driving timer exists only while an AppKit sidebar transition is active.

Popover width 340; bounded history/secondary scroll region; compact shared header, 28–32 action rows, persistent footer. Escape, repeated menu-bar click and outside click dismiss. Real menu actions stay the source of truth. Native permission/Focus semantics remain intact. Ordinary keyboard correction must not post repeated system notifications; important background file results may notify using the existing native API.

## Acceptance evidence

Both apps: default/minimum/large/zoom, width-only and height-only resizing, reverse to minimum, restore frame, resize while sidebar animates; all sections in both themes; compact/expanded focus and navigation; ≥20 cycles including fast reversals. Record real sidebar/resize/theme/popover video. Rule editor: cancel/save, invalid input, focus/tab/return/escape, themes. MultiShift: file open/processing/history/undo, drag/Shift/radial where the input tools permit. MultiSwitcher: existing core suites plus real layout/correction/rules/learning/shortcuts where permissions and input tools permit. Document any unperformed physical input, monitor/scaling, VoiceOver or accessibility-settings matrix explicitly; a build is not proof of UI acceptance.
