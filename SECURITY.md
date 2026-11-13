# Security policy

## Supported builds

Security fixes target the latest published MultiShift version. Older versions should be updated.
MultiShift is an early-stage project; there is no guaranteed response or remediation deadline.

## Report a vulnerability privately

Use GitHub's **Security → Report a vulnerability** on this repository:

https://github.com/SokolovMO/MultiShift/security/advisories/new

Include the affected version/build, macOS version, impact, and minimal reproduction steps.
Use synthetic files. Do not post credentials, private documents, or exploit details in a public issue.
If private reporting is temporarily unavailable, open a public issue asking the maintainer to
provide a private reporting channel, without disclosing the vulnerability itself.

## Trust model

- The current app is ad-hoc signed and is not notarized by Apple.
- Distributed update archives, delta patches, and the appcast use a persistent Ed25519 key.
  Update signatures and Apple code signing/notarization serve different purposes.
- Full archives remain available if a matching delta is absent or patching fails.
- Local development builds do not enable the production updater by default.
- Production signing seeds and server credentials must never be committed or uploaded to CI.
- Converters parse complex, potentially untrusted formats. Avoid opening unknown files until
  you trust their origin; conversion is not a malware-sanitization guarantee.

The automated checks cover secret patterns, tests, bundle integrity, and release validation.
They do not constitute a complete security audit. See [privacy notes](docs/PRIVACY.md).
