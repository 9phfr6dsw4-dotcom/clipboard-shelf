#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.1.4"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/Clipboard Shelf.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_MODE="${SIGN_MODE:-adhoc}"
export SIGN_MODE

# Sparkle, pinned by version and checksum: the same archive Sparkle's own Package.swift pins.
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959"
SPARKLE_ARCHIVE="$BUILD_DIR/Sparkle-$SPARKLE_VERSION.zip"
SPARKLE_DIR="$BUILD_DIR/Sparkle-$SPARKLE_VERSION"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

curl -fsSL -o "$SPARKLE_ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip"
echo "$SPARKLE_SHA256  $SPARKLE_ARCHIVE" | shasum -a 256 -c -
ditto -x -k "$SPARKLE_ARCHIVE" "$SPARKLE_DIR"
SPARKLE_FRAMEWORKS="$SPARKLE_DIR/Sparkle.xcframework/macos-arm64_x86_64"
test -d "$SPARKLE_FRAMEWORKS/Sparkle.framework"

python3 "$ROOT/Scripts/test_generate_icon.py"
python3 "$ROOT/Scripts/generate_icon.py" "$BUILD_DIR/AppIcon.iconset" "$ROOT/Resources/AppIcon-1024.png"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT/Resources/AppIcon-1024.png" "$RESOURCES_DIR/AppIcon-1024.png"
python3 "$ROOT/Scripts/test_icon_package.py" "$ROOT/Resources/AppIcon-1024.png" "$APP"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/Acknowledgements.txt" "$RESOURCES_DIR/Acknowledgements.txt"

# The macOS 26 icon: compile the Icon Composer file (Resources/AppIcon.icon) into Assets.car.
# Without it, macOS 26 shows the classic .icns shrunk onto a grey plate. actool can exit 0
# even when it skips the icon, so its output is checked, not just its exit code.
ICON_OUT="$BUILD_DIR/AppIcon-compiled"
mkdir -p "$ICON_OUT"
xcrun actool "$ROOT/Resources/AppIcon.icon" \
  --compile "$ICON_OUT" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ICON_OUT/partial.plist" \
  --output-format human-readable-text \
  --errors --warnings --notices
test -s "$ICON_OUT/Assets.car" || { echo "actool didn't produce Assets.car from Resources/AppIcon.icon" >&2; exit 1; }
ICON_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$ICON_OUT/partial.plist" 2>/dev/null || true)"
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  xcrun assetutil --info "$ICON_OUT/Assets.car" | grep -q '"AppIcon"' \
    || { echo "Assets.car doesn't contain an app icon named AppIcon" >&2; exit 1; }
fi
# Only Assets.car is copied; the classic AppIcon.icns above stays as the fallback.
cp "$ICON_OUT/Assets.car" "$RESOURCES_DIR/Assets.car"

COMMON_ARGS=(
  -O
  -warnings-as-errors
  -sdk "$SDK"
  -framework AppKit
  -F "$SPARKLE_FRAMEWORKS"
  -framework Sparkle
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
  "$ROOT/Sources/ClipboardCore.swift"
  "$ROOT/Sources/ShelfView.swift"
  "$ROOT/Sources/Updates.swift"
  "$ROOT/Sources/main.swift"
)

xcrun swiftc "${COMMON_ARGS[@]}" -target arm64-apple-macos26.0 -o "$BUILD_DIR/ClipboardShelf-arm64"
xcrun swiftc "${COMMON_ARGS[@]}" -target x86_64-apple-macos26.0 -o "$BUILD_DIR/ClipboardShelf-x86_64"
lipo -create "$BUILD_DIR/ClipboardShelf-arm64" "$BUILD_DIR/ClipboardShelf-x86_64" -output "$MACOS_DIR/ClipboardShelf"
chmod +x "$MACOS_DIR/ClipboardShelf"

# Sparkle goes in beside the app, and the app finds it through the rpath set above.
mkdir -p "$FRAMEWORKS_DIR"
ditto "$SPARKLE_FRAMEWORKS/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FRAMEWORKS_DIR/Sparkle.framework/Resources/Info.plist")"
[[ "$SPARKLE_BUILT" == "$SPARKLE_VERSION" ]]
test -x "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
test -x "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
otool -l "$MACOS_DIR/ClipboardShelf" | grep -F 'path @executable_path/../Frameworks'
grep -F "Sparkle $SPARKLE_VERSION" "$RESOURCES_DIR/Acknowledgements.txt"

plutil -lint "$CONTENTS/Info.plist"
# Signing is the last change to the app; the zip, the checksum and the update signature come after.
bash "$ROOT/Scripts/sign-app.sh" "$APP"
"$MACOS_DIR/ClipboardShelf" --self-test
ARCHS="$(lipo -archs "$MACOS_DIR/ClipboardShelf")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]

NOTARIZED="no"
if [[ "$SIGN_MODE" == "developer-id" ]]; then
  bash "$ROOT/Scripts/notarize.sh" "$APP"
  NOTARIZED="yes"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
(
  cd "$DIST_DIR"
  shasum -a 256 "Clipboard-Shelf-$VERSION.zip" > "Clipboard-Shelf-$VERSION.zip.sha256"
)
printf 'mode=%s\nnotarized=%s\n' "$SIGN_MODE" "$NOTARIZED" > "$DIST_DIR/signing.txt"

printf 'Built %s\n' "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
