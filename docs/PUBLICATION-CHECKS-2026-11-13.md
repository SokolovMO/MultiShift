# Public repository checks · 2026-11-13

## Scope

Prepare the existing SokolovMO/MultiShift repository for public access, preserving its history
and integrating the native tools, build 11 fix, and verified-delta pipeline already developed
in this working tree. This is a source-repository publication, not a new application build.

## Local verification

- Python: **441 passed, 25 skipped**, 6 warnings. Skips include optional routes and tools.
- Swift native core: **31 tests, 0 failures**.
- Release tests are included in the full Python run; delta integrity and client-evidence gates pass.
- `git diff --check` and local links in the public-facing Markdown files pass.
- Gitleaks **8.30.1**, downloaded from the official release with its SHA256 verified:
  all 10 pre-publication commits across local/fetched refs scanned; no unresolved findings.
  Three exact historical findings are source SHA256 entries and are documented in `.gitleaksignore`.
- The publishable working source and available historical Actions logs were also scanned:
  no secret-pattern findings. Existing Actions artifacts list was empty.
- Historical preview ZIPs contained no private credential filenames. Prior QA privacy notes
  record synthetic fixtures and redaction checks. Pattern scanning is not a security audit.

## Repository presentation

English README with a project banner, Russian introduction, installation requirements,
Homebrew instructions, honest signing status, limitations, provenance, and delta-update details.
Contribution/security/conduct policies, issue forms, PR template, changelog, architecture,
privacy notes, pinned CI actions, monthly Actions dependency updates, and a history secret scan.
Upstream MIT notices and the existing AGPL license remain intact.

Generated QA directories and old preview builds are removed from the current Git index and
ignored, while remaining on the maintainer's disk. Historical commits retain those artifacts;
the history has not been rewritten. A shallow clone is recommended in the README.
The old donation destination is retained only locally and is not used by MultiShift.

## Existing application update evidence

See [delta verification](DELTA-UPDATES-2026-11-13.md): public 10 → 11 selection by real Sparkle,
187494-byte selected-URL download by NSURLSession, signature verification, application to an
exact old bundle, target tree match, codesign, and selftest. No installation or GUI relaunch of
the user's app was performed. Apple notarization remains unavailable for the current build.

## Hosted compiler compatibility

The first GitHub build passed Python and Swift core tests but exposed a SwiftUI type-checking
timeout in the crop field's combined numeric Binding. That expression was split into typed
Double/CGFloat helpers without changing its coordinate and aspect-ratio rules. Whole-app
Swift type checking then passed locally. The follow-up GitHub build must pass before public access.

Public availability and the final hosted build results are checked separately after publication.
