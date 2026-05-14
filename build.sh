#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="Claude Clipboard Cleaner"
BUNDLE_ID="ClaudeClipboardCleaner"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$BUNDLE_ID.zip"
DMG_PATH="$BUILD_DIR/$BUNDLE_ID.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "🔨 Compiling..."
cat CleanLogic.swift ClaudeClipboardCleaner.swift > "$BUILD_DIR/main.swift"
swiftc -O \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework ServiceManagement \
    -o "$APP_BUNDLE/Contents/MacOS/$BUNDLE_ID" \
    "$BUILD_DIR/main.swift"

cp Info.plist "$APP_BUNDLE/Contents/"

# Icon (generate if missing)
if [ ! -f build/AppIcon.icns ]; then
    echo "🎨 Generating icon..."
    swiftc -O -target arm64-apple-macosx13.0 -framework AppKit \
        -o build/generate_icon scripts/generate_icon.swift
    ./build/generate_icon
fi
cp build/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"

# Menubar icon (generate if missing)
if [ ! -f build/menubar_icon.png ]; then
    echo "🎨 Generating menubar icon..."
    swiftc -O -target arm64-apple-macosx13.0 -framework AppKit \
        -o build/generate_menubar scripts/generate_menubar_icon.swift
    ./build/generate_menubar
fi
cp build/menubar_icon.png "$APP_BUNDLE/Contents/Resources/"

# Standalone CLI for stdin testing (bypasses the menubar app — useful for
# reproducing clipboard payloads without restarting the running instance).
echo "🔨 Compiling clean_string CLI..."
cat CleanLogic.swift scripts/clean_string.swift > "$BUILD_DIR/clean_string_main.swift"
swiftc -O -target arm64-apple-macosx13.0 \
    -o "$BUILD_DIR/clean_string" "$BUILD_DIR/clean_string_main.swift"

# DMG background (generate if missing)
if [ ! -f build/dmg_background.png ]; then
    echo "🎨 Generating DMG background..."
    swiftc -O -target arm64-apple-macosx13.0 -framework AppKit \
        -o build/generate_dmg_background scripts/generate_dmg_background.swift
    ./build/generate_dmg_background
fi

# Package for distribution. ditto preserves macOS metadata (and code signature
# when present); the unsigned outputs from this script will still trigger
# Gatekeeper warnings — use build-mac-signed.sh for notarized releases.
echo "Packaging zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Packaging dmg..."
./scripts/make_polished_dmg.sh "$APP_BUNDLE" "$DMG_PATH" build/dmg_background.png "$APP_NAME"

echo "✅ Built:"
echo "   App: $APP_BUNDLE"
echo "   Zip: $ZIP_PATH"
echo "   DMG: $DMG_PATH"
echo "   CLI: $BUILD_DIR/clean_string  (pbpaste | $BUILD_DIR/clean_string)"
