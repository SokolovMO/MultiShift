#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build MultiShift.app on macOS." >&2
  exit 2
fi

DEFAULT_PYTHON="python3"
if [[ -x "$ROOT/.venv/bin/python" ]]; then
  DEFAULT_PYTHON="$ROOT/.venv/bin/python"
fi
PYTHON="${PYTHON:-$DEFAULT_PYTHON}"
OUTPUT_DIR="${MULTISHIFT_OUTPUT_DIR:-$ROOT/dist}"
BUILD_CACHE="${MULTISHIFT_BUILD_CACHE_DIR:-$ROOT/build}"
APP_VERSION="$($PYTHON -c 'from dragshift import __version__; print(__version__)')"
BUILD_NUMBER="${MULTISHIFT_BUILD_NUMBER:-$(cat macos/build-number.txt)}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]{0,8}$ ]] || { echo "Invalid build number" >&2; exit 1; }
COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || echo no-git)"
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then DIRTY="dirty"; else DIRTY="clean"; fi
SOURCE_FINGERPRINT="$( { find dragshift macos/Sources macos/Assets.xcassets scripts -type f ! -name '*.pyc' ! -name '.DS_Store' ! -path '*/__pycache__/*' -print; printf '%s\n' DragShift.spec requirements-macos.lock engine_main.py; } | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256 | awk '{print $1}')"
BUILD_ID="${COMMIT}-${DIRTY}-${SOURCE_FINGERPRINT:0:16}"
STAGING="$OUTPUT_DIR/.native-build"
APP="$OUTPUT_DIR/MultiShift.app"
ARCH="$(uname -m)"
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"

mkdir -p "$OUTPUT_DIR" "$BUILD_CACHE"
rm -rf "$STAGING" "$APP"
mkdir -p "$STAGING/engine"

MULTISHIFT_BUILD_CACHE_DIR="$BUILD_CACHE" MULTISHIFT_ICON_OUTPUT="$STAGING/multishift.icns" \
  "$PYTHON" scripts/build_icon.py
MULTISHIFT_ENGINE_ONLY=1 PYINSTALLER_CONFIG_DIR="$BUILD_CACHE/pyinstaller-engine" \
  "$PYTHON" -m PyInstaller --clean --distpath "$STAGING/engine" \
  --workpath "$BUILD_CACHE/pyinstaller-engine-work" DragShift.spec --noconfirm

ENGINE="$STAGING/engine/MultiShiftEngine/MultiShiftEngine"
if [[ ! -x "$ENGINE" ]]; then
  echo "Packaged Python engine was not created: $ENGINE" >&2
  exit 1
fi
"$ENGINE" --selftest

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/MultiShiftEngine"
cp -R "$STAGING/engine/MultiShiftEngine/." "$APP/Contents/Resources/MultiShiftEngine/"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/Licenses/"
cp "$STAGING/multishift.icns" "$APP/Contents/Resources/multishift.icns"
cp "$BUILD_CACHE/icon-light.png" "$BUILD_CACHE/icon-dark.png" "$APP/Contents/Resources/"
# Python runtime metadata is not needed to execute the frozen worker and confuses
# Apple's recursive bundle signer because these plain directories end in .dist-info.
find "$APP/Contents/Resources/MultiShiftEngine" -type d -name '*.dist-info' -prune -exec rm -rf {} +

if [[ "$ARCH" == "arm64" ]]; then
  TARGET="arm64-apple-macosx14.0"
elif [[ "$ARCH" == "x86_64" ]]; then
  TARGET="x86_64-apple-macosx14.0"
else
  echo "Unsupported macOS build architecture: $ARCH" >&2
  exit 2
fi

mkdir -p "$BUILD_CACHE/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE/swift-module-cache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_CACHE/swift-module-cache"
# Record the actual linked SDK, independently from the minimum supported OS.
# Leaving this implicit makes ld record SDK 14 and enables legacy AppKit rendering.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SWIFT_FLAGS=(-module-name MultiShift -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
if [[ "${MULTISHIFT_ENABLE_UPDATES:-0}" == "1" ]]; then
  : "${MULTISHIFT_SPARKLE_FRAMEWORK:?Provide verified Sparkle 2.10.0 framework}"
  : "${MULTISHIFT_SPARKLE_PUBLIC_KEY:?Provide EdDSA public key}"
  "$PYTHON" -c 'import base64,os; assert len(base64.b64decode(os.environ["MULTISHIFT_SPARKLE_PUBLIC_KEY"],validate=True)) == 32'
  SPARKLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MULTISHIFT_SPARKLE_FRAMEWORK/Resources/Info.plist")
  [[ "$SPARKLE_VERSION" == "2.10.0" ]] || { echo "Unexpected Sparkle version" >&2; exit 1; }
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$MULTISHIFT_SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
  mkdir -p "$APP/Contents/Resources/Licenses"
  cp "$(dirname "$MULTISHIFT_SPARKLE_FRAMEWORK")/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle.txt"
  SWIFT_FLAGS+=(-F "$APP/Contents/Frameworks" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi
"$SWIFTC" "${SWIFT_FLAGS[@]}" -target "$TARGET" -sdk "$SDK" \
  -disable-sandbox \
  -module-cache-path "$BUILD_CACHE/swift-module-cache" \
  -framework AppKit -framework AVKit -framework SwiftUI -framework CoreGraphics -framework ServiceManagement -framework UserNotifications \
  macos/Sources/Core/MultiInterfaceMetrics.swift macos/Sources/Core/MultiAuditEnvironment.swift macos/Sources/Core/WheelGeometry.swift macos/Sources/Core/InterfaceCopy.swift macos/Sources/Core/EngineClient.swift macos/Sources/Core/FileJobCoordinator.swift macos/Sources/Core/NotificationDispatcher.swift macos/Sources/Core/OutputOpening.swift \
  macos/Sources/MultiDesignKit.swift macos/Sources/MultiPopoverKit.swift macos/Sources/DesignSystem.swift macos/Sources/StatusPopover.swift macos/Sources/NativeModels.swift macos/Sources/NativeViews.swift macos/Sources/NativeFileEditor.swift macos/Sources/ExtendedFormats.swift macos/Sources/OperationNotifications.swift macos/Sources/UpdateController.swift macos/Sources/AppDelegate.swift \
  -o "$APP/Contents/MacOS/MultiShift"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>CFBundleLocalizations</key><array><string>ru</string><string>en</string></array>
  <key>CFBundleExecutable</key><string>MultiShift</string>
  <key>CFBundleIdentifier</key><string>com.multiswitcher.multishift</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>multishift</string>
  <key>CFBundleDisplayName</key><string>multishift</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>MultiShiftBuildID</key><string>$BUILD_ID</string>
  <key>MultiShiftSourceFingerprint</key><string>$SOURCE_FINGERPRINT</string>
  <key>MultiShiftEngineVersion</key><string>$APP_VERSION</string>
  <key>CFBundleIconFile</key><string>multishift.icns</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSRequiresAquaSystemAppearance</key><false/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>MultiShift file</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.item</string><string>public.data</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [[ "${MULTISHIFT_ENABLE_UPDATES:-0}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $MULTISHIFT_SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
  : "${MULTISHIFT_RELEASE_URL:?Set the HTTPS directory for downloads and updates}"
  "$PYTHON" -c 'from urllib.parse import urlsplit; import os; u=urlsplit(os.environ["MULTISHIFT_RELEASE_URL"]); assert u.scheme == "https" and u.hostname and not u.username and not u.password and not u.query and not u.fragment'
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string ${MULTISHIFT_RELEASE_URL%/}/appcast.xml" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUAutomaticallyUpdate bool false' "$APP/Contents/Info.plist"
fi
# Compile the same native grayscale accent as MultiSwitcher before signing.
xcrun actool --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --accent-color AccentColor \
  --output-partial-info-plist "$BUILD_CACHE/asset-info.plist" --output-format human-readable-text "$ROOT/macos/Assets.xcassets"
cat > "$APP/Contents/Resources/BUILD.json" <<BUILD
{"version":"$APP_VERSION","build_number":"$BUILD_NUMBER","build_id":"$BUILD_ID","commit":"$COMMIT","worktree":"$DIRTY","source_fingerprint":"$SOURCE_FINGERPRINT"}
BUILD

# Finder and LaunchServices still consult PkgInfo for classic application
# bundles. Keep it in sync with CFBundlePackageType so a manually built .app
# launches the same way as an Xcode-produced app.
printf 'APPL????' > "$APP/Contents/PkgInfo"

xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
# File Provider can leave FinderInfo on the package directory itself even after
# recursively cleaning its children. Remove that root attribute before signing.
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP" 2>/dev/null || true
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    codesign --force --preserve-metadata=identifier,entitlements --sign - "$binary"
  fi
done < <(find "$APP/Contents" -type f -print0)
if [[ -d "$APP/Contents/Frameworks" ]]; then
  while IFS= read -r bundle; do
    codesign --force --preserve-metadata=identifier,entitlements --sign - "$bundle"
  done < <(find "$APP/Contents/Frameworks" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -type d)
fi
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
[[ "$(cat "$APP/Contents/PkgInfo")" == "APPL????" ]]
plutil -lint "$APP/Contents/Info.plist"
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then codesign --verify --strict "$binary"; fi
done < <(find "$APP/Contents" -type f -print0)
"$APP/Contents/MacOS/MultiShift" --selftest
echo "Built and verified $APP $APP_VERSION ($BUILD_ID) for $ARCH (local ad-hoc signature; not notarized)."
