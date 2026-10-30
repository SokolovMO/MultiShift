# Signing and notarizing MultiShift releases

The macOS release workflow publishes only after both architectures pass tests and the app bundle's self-test. It fails closed if any of the Apple credentials below are missing. It never falls back to publishing an ad-hoc signed build.

Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | Base64-encoded Developer ID Application `.p12` certificate |
| `MACOS_CERT_PASSWORD` | Password used to export that certificate |
| `MACOS_SIGN_IDENTITY` | Full Developer ID Application identity string |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | Apple app-specific password |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

Add a version tag such as `v0.1.0` after the release candidate is reviewed. The workflow signs nested Mach-O code and the app, submits the app and DMG for notarization, staples the tickets, and verifies them before creating the GitHub release. Builds require macOS 14 or later and use a separate MultiShift bundle identifier and install path; they do not replace DragShift.

Do not put certificate files or passwords in the repository. For Apple account and certificate setup, follow Apple's current Developer ID and notarization documentation.
