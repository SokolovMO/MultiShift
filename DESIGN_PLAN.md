# multishift — premium monochrome

## scope and existing architecture

The shipping UI is SwiftUI hosted by AppKit windows and a native status item. AppModel owns settings, file actions, operation history and notifications; FileJobCoordinator and the Python engine perform file work. Preserve their protocol, action IDs, settings keys, file access, originals, output paths and undo safety.

Real surfaces: onboarding; settings (general, files, appearance, notifications, about); status menu and history; drag radial menu; keyboard action chooser; image/PDF tools and preview; operation details; native file panels, alerts and notification actions. There are no keyboard remapping rules, per-app profiles or shortcut editors. The concept's keycaps describe the existing drag modifier and keyboard navigation only.

## reference mapping

Use the approved concept's compact translucent sidebar, inset content cards, black/white primary actions, neutral selected states, arrow mark and small floating panels. Retain native window traffic lights, file pickers, alert and notification chrome. The OS may apply its own accent to native chrome. User file contents, filenames, passwords and diagnostic identifiers retain their original case and colors.

The local MultiSwitcher project uses semantic SF typography, NSVisualEffectView sidebar material, 206-point navigation and short page transitions. Reuse those principles as independent SwiftUI tokens; no source or runtime dependency on MultiSwitcher.

## design system

- neutral canvas: light 0.96 white; dark 0.075 white
- raised card: light 0.99 white; dark 0.115 white
- secondary surface: light 0.93 white; dark 0.15 white
- text: semantic label / secondary label; monochrome selection and status symbols
- border: neutral foreground at 7% light / 12% dark; stronger in increased contrast
- spacing: 4, 8, 12, 16, 20, 24, 28
- radius: keycap 5; control 8; card 12; floating surface 16
- typography: SF system, 12–13 body, 11 supporting, 20–22 title; monospaced numbers
- motion: critically damped spring response 0.28–0.34; pressed feedback 0.98; no loops or polling added
- reduce motion: short opacity changes; no scaling or spring movement
- reduce transparency: opaque surfaces; increased contrast: stronger neutral boundaries

## implementation

1. Add independent theme, surface, button, keycap and branding components.
2. Recompose existing settings into stable navigation IDs and focused cards. Keep system/light/dark preferences and original persistence keys.
3. Add a native NSPopover for left-click status access, preserve the native context menu on right-click. Expose existing recent results and operation actions; no invented statistics or rules.
4. Restyle onboarding, chooser, wheel, editor and details. Use the same spacing, hierarchy, surfaces and monochrome state language.
5. Lowercase controlled copy at localization/display boundaries; never lowercase user data or engine action IDs.
6. Generate matching light/dark arrow icon resources. Use the effective app appearance for the runtime icon; retain a standard ICNS for Finder.
7. Build the full bundle, run core and Python checks, exercise conversion/preview/undo and capture real light/dark windows, popover and notification state. Compare against the supplied composition and refine.

## acceptance evidence

Store build and functional results plus real screenshot paths in `docs/REDESIGN_QA.md`. Report any OS-controlled banner, permission or capture limitations explicitly. Do not substitute a rendered mockup for the running application.
