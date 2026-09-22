#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.0"
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/Clipboard Shelf.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

python3 "$ROOT/Scripts/generate_icon.py" "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

COMMON_ARGS=(
  -O
  -warnings-as-errors
  -sdk "$SDK"
  -framework AppKit
  "$ROOT/Sources/ClipboardCore.swift"
  "$ROOT/Sources/main.swift"
)

xcrun swiftc "${COMMON_ARGS[@]}" -target arm64-apple-macos13.0 -o "$BUILD_DIR/ClipboardShelf-arm64"
xcrun swiftc "${COMMON_ARGS[@]}" -target x86_64-apple-macos13.0 -o "$BUILD_DIR/ClipboardShelf-x86_64"
lipo -create "$BUILD_DIR/ClipboardShelf-arm64" "$BUILD_DIR/ClipboardShelf-x86_64" -output "$MACOS_DIR/ClipboardShelf"
chmod +x "$MACOS_DIR/ClipboardShelf"

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
"$MACOS_DIR/ClipboardShelf" --self-test
ARCHS="$(lipo -archs "$MACOS_DIR/ClipboardShelf")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]]

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
shasum -a 256 "$DIST_DIR/Clipboard-Shelf-$VERSION.zip" > "$DIST_DIR/Clipboard-Shelf-$VERSION.zip.sha256"

printf 'Built %s\n' "$DIST_DIR/Clipboard-Shelf-$VERSION.zip"
