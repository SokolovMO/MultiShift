#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CHECK_ROOT="$(mktemp -d /private/tmp/shift-appearance.XXXXXX)"
# Reuse the real application delegate without its process entry point.
sed '/^@main$/d' "$ROOT/macos/Sources/AppDelegate.swift" > "$CHECK_ROOT/AppDelegate.swift"
SOURCES=()
for source in "$ROOT"/macos/Sources/*.swift; do
 [[ "$source" == */AppDelegate.swift ]] || SOURCES+=("$source")
done
xcrun swiftc -disable-sandbox -module-cache-path "$CHECK_ROOT/cache" \
 "$ROOT"/macos/Sources/Core/*.swift "${SOURCES[@]}" "$CHECK_ROOT/AppDelegate.swift" \
 "$ROOT/macos/Tests/AppearanceChecks/AppearanceChecks.swift" -o "$CHECK_ROOT/checks"
MULTI_AUDIT_DATA_ROOT="$CHECK_ROOT/data" "$CHECK_ROOT/checks"
