<p align="right"><a href="CONTRIBUTING.md">Русский</a> · <b>English</b></p>

# Contributing to MultiShift

Thank you for helping improve MultiShift. English and Russian reports and pull requests are welcome.
Start with an [issue](https://github.com/SokolovMO/MultiShift/issues/new/choose) for a substantial
feature so the interaction and scope can be discussed before implementation.

## Set up

Use macOS 14+, Xcode with its macOS SDK, and Python 3.12. Install dependencies as shown in the
[README](README.en.md#build-from-source). You do not need production credentials, an Apple
Developer account, or the maintainer's release signing key. Local builds disable update checks.

```sh
QT_QPA_PLATFORM=offscreen python -m pytest -q
swift test --package-path macos
bash scripts/build_macos.sh
```

The native core tests run without driving the desktop. Tests requiring optional external tools
can skip when those tools are unavailable. A successful unit run does not establish that Finder
dragging, notification clicks, or a full GUI update works; verify relevant interactions on a Mac
and describe what you actually observed.

## Make a change

- Keep pull requests focused. Describe the user-visible problem and resulting behavior.
- Preserve original files. Process outputs in private staging and publish copies only after success.
- Use system components for native windows, dialogs, settings, and notifications. Support both
  appearances, keyboard operation, and English/Russian text.
- Add meaningful tests for changed behavior. Document required optional tools and conversion limits.
- Preserve dependency copyright notices. Explain the origin and license of reused code or assets.
- Do not include private documents, history, credentials, signing seeds, compiled apps, or QA recordings.
  Use synthetic fixtures; crop or redact reports before sharing.
- Follow [AGENTS.md](AGENTS.md), especially the verified-delta requirements for releases.

Use a branch such as `fix/result-opening` and a clear commit title such as
`fix: explain when an output file is missing`. In the pull request include the validation
performed and any limitations. The default CI builds the app without production secrets.

## Release changes

Only maintainers publish production artifacts. Do not replace an archive under an existing
build number. Preserve old signed bases and generate a delta from the previous public build.
See [DISTRIBUTION.md](docs/DISTRIBUTION.md) for the signing, client checks, and rollback process.

## Licensing and conduct

By submitting a contribution, you agree that it may be distributed under the project's
[GNU AGPL v3 license](LICENSE), preserving any required third-party notices.
Please follow the [code of conduct](CODE_OF_CONDUCT.md).
Report security issues privately as described in [SECURITY.md](SECURITY.md).
