# release implementation — 2026-11-01

## Implemented

Both apps use independently signed feeds under https://sokolovmo.github.io/multi-releases/. MultiShift has optional Sparkle 2.10.0, separate numeric build metadata, update preferences and delayed shutdown for file operations. MultiSwitcher configures Sparkle before starting it, stops monitoring before termination, waits for queued replacements and restores owned clipboard contents.

Source candidate workflows require the exact main commit's successful CI and immutable matching version/build tags. Source builds produce draft artifacts, candidate manifest, corresponding source and notices. Trusted Apple signing/notarization remain mandatory; no unsigned fallback is published.

The separate public `release-infra` project is pushed to https://github.com/SokolovMO/multi-releases. It serializes publication/withdrawal, binds owner acceptance to the actual artifact hash, checks the updater public key, and regenerates signed beta+stable feeds from current published state. It does not reuse a historical release-event feed. Pages deployments compare deployed bytes and verify public artifact endpoints.

The separate private `multi-release-console` project is pushed to https://github.com/SokolovMO/multi-release-console. It implements owner-only GitHub OAuth, scoped GitHub App tokens, HttpOnly signed sessions, Origin/CSRF protection, two-app status, candidate creation, artifact-bound checklists, publication, withdrawal, retry and links to the Actions audit trail. Production access remains disabled until authentication provisioning is complete.

## Verified

- MultiShift: 28 Core tests; Python 49 passed / 3 skipped, five dependency warnings.
- Full updater-enabled arm64 MultiShift bundle built in /tmp/MultiShift-updater-candidate, strict signature verification and native/engine selftests passed. This is an ad-hoc local signature, not Developer ID.
- MultiSwitcher: 313 Core checks and 109 actual-source selected-text assertions passed; updater-enabled native target compiled successfully.
- Console: production Next.js build passed, five authorization/dispatch tests passed. Real desktop/mobile setup screen and unauthenticated endpoints checked; authenticated local route rejects cross-origin requests, wrong CSRF and unknown app.
- Release manifest: two artifact-replacement/incomplete-acceptance tests passed.
- Feed tooling: three tests passed including signing with real Sparkle and rejection after XML tampering.
- Hosted delivery workflow completed successfully. Both deployed feed signatures verified after downloading the public URLs. Both feeds currently contain zero releases; no installers were published.
- YAML parsing, shell syntax and whitespace checks passed.

Pilot bundles default to beta; explicit saved channel choices survive distribution-channel changes. Three channel regression tests cover fresh pilot, explicit stable/beta overrides and invalid preferences.

## Additional hosted/runtime validation

- MultiShift hosted PR CI passed after fixing the Bash 3 empty-array expansion and explicitly typing sidebar spring arithmetic.
- MultiSwitcher hosted CI passed on macOS 15, macOS 26 and Xcode 27 after guarding the macOS 27-only menu API at compile time and explicitly converting CGFloat/Double spring values.
- Official Sparkle postpone-relaunch callbacks are implemented in both apps, in addition to normal termination guards. Signed end-to-end relaunch remains a separate acceptance gate.
- Actual AppKit sidebar components: 393 checks passed in each app (1x/2x rendering, four sizes, forty reversals). The Switcher runner uses an immutable color-preference fixture; production preference behavior and VoiceOver are not inferred from these geometry checks.
- Console hosted CI and both signed-feed deployment runs passed. Authentication/hosting provisioning still requires the owner.

## Configured externally

- Public distribution repository and private console repository exist.
- GitHub Pages enabled for public delivery.
- Separate Sparkle signing seeds generated and stored locally with restrictive permissions; corresponding public variables and environment-scoped private secrets provisioned. Private keys are not in source or reports.
- Source release environments and public-delivery environment exist.

## Still requires external account action

1. Register/install the GitHub App with access only to the three named repositories. The console's `npm run configure:github` helper prepares the registration form and saves credentials without exposing them in browser output; permission approval remains an owner action. Run `npm run configure:installation` afterward.
2. Connect Vercel hosting and the console's canonical HTTPS OAuth callback/environment. No Vercel credential is available in this session. The console is available locally on http://127.0.0.1:3033 in setup mode.
3. Enroll in Apple Developer Program and configure Developer ID/notarization credentials. Owner confirmed no account yet.
4. Review and merge source changes before triggering candidates. No source release tags or unsigned public releases were created.
5. Complete signed A-to-B, physical input/Finder/VoiceOver/multi-display acceptance, supported-OS checks and pilot. These are not certified by compile/unit results.

The full original release plan is not declared complete. Apple signing, hosted owner authentication and actual pilot acceptance remain separate gates.
