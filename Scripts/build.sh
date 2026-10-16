#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.1.1"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/Clipboard Shelf.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

python3 "$ROOT/Scripts/test_generate_icon.py"
python3 "$ROOT/Scripts/generate_icon.py" "$BUILD_DIR/AppIcon.iconset" "$ROOT/Resources/AppIcon-1024.png"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT/Resources/AppIcon-1024.png" "$RESOURCES_DIR/AppIcon-1024.png"
python3 "$ROOT/Scripts/test_icon_package.py" "$ROOT/Resources/AppIcon-1024.png" "$APP"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

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
  "$ROOT/Sources/ClipboardCore.swift"
  "$ROOT/Sources/ShelfView.swift"
  "$ROOT/Sources/main.swift"
)

xcrun swiftc "${COMMON_ARGS[@]}" -target arm64-apple-macos26.0 -o "$BUILD_DIR/ClipboardShelf-arm64"
xcrun swiftc "${COMMON_ARGS[@]}" -target x86_64-apple-macos26.0 -o "$BUILD_DIR/ClipboardShelf-x86_64"
lipo -create "$BUILD_DIR/ClipboardShelf-arm64" "$BUILD_DIR/ClipboardShelf-x86_64" -output "$MACOS_DIR/ClipboardShelf"
chmod +x "$MACOS_DIR/ClipboardShelf"

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
"$MACOS_DIR/ClipboardShelf" --self-test
ARCHS="$(lipo -archs "$MACOS_DIR/ClipboardShelf")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
(
  cd "$DIST_DIR"
  shasum -a 256 "Clipboard-Shelf-$VERSION.zip" > "Clipboard-Shelf-$VERSION.zip.sha256"
)

printf 'Built %s\n' "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
