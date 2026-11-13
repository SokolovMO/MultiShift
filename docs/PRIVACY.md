# Privacy notes

## Local processing

MultiShift converts files locally using its packaged Python engine and conversion libraries.
No cloud conversion account is required. Optional external applications such as LibreOffice
run on the Mac. This describes MultiShift's own conversion flow, not every external app's policy.

Operation history, output paths, preferences, caches, and diagnostic information are stored
locally. History is normally under `~/Library/Application Support/MultiShift/operations.json`.
Diagnostic entries are stored in `~/Library/Application Support/diagnostics.jsonl`.
Logs and screenshots can reveal file names or paths; inspect and redact them before reporting a bug.
Undo removes generated outputs through the Trash and does not promise secure erasure.

## System interactions

The native app reads drag/shortcut state to display the action wheel. Notification permission
controls system result notifications. Finder, file dialogs, preview players, login-item settings,
and access to protected folders remain subject to macOS controls and user choices.

## Network requests

The distributed app uses Sparkle to check its configured release feed and fetch updates.
The release server sees ordinary HTTP request information, including the client IP address;
server access logs may retain it. Ed25519 signatures verify update content.

Choosing to view an image's location opens OpenStreetMap in a browser and puts the coordinates
in that URL. Loading the website, GitHub, Homebrew, or other external links contacts those
services and is governed by their policies.

The optional website download counter stores daily totals by application/build, not a list
of installations or unique users. Its code uses short-lived in-memory hashes of IP/user-agent
information to avoid counting immediate retries. This does not override web-server logging.
There is no account-based telemetry or conversion upload implemented in the native app.

## Reporting

Use synthetic examples where possible. Do not attach original confidential documents,
unredacted diagnostic files, or operation history to public issues. Report vulnerabilities
through the [security policy](../SECURITY.md).
