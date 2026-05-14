#!/bin/bash
#
# Build a polished, drag-to-Applications DMG.
#
# Usage:  make_polished_dmg.sh <app-bundle> <output-dmg> <background-png> [volume-name]
#
# Produces a compressed read-only DMG whose mounted Finder window has:
#   - A custom background image (with an arrow)
#   - The .app on the left, an "Applications" symlink on the right
#   - Toolbar and sidebar hidden, fixed window size, 96pt icons
#
# Note: the AppleScript step controls Finder. The first time you run this,
# macOS will prompt to grant Terminal (or your shell host) the right to
# script Finder under System Settings → Privacy & Security → Automation.

set -e

APP_PATH="$1"
DMG_PATH="$2"
BG_PNG="$3"
VOLUME_NAME="${4:-$(basename "$APP_PATH" .app)}"

if [ -z "$APP_PATH" ] || [ -z "$DMG_PATH" ] || [ -z "$BG_PNG" ]; then
    echo "Usage: $0 <app-bundle> <output-dmg> <background-png> [volume-name]" >&2
    exit 1
fi
if [ ! -d "$APP_PATH" ]; then
    echo "App not found: $APP_PATH" >&2
    exit 1
fi
if [ ! -f "$BG_PNG" ]; then
    echo "Background image not found: $BG_PNG" >&2
    exit 1
fi

APP_BASENAME=$(basename "$APP_PATH")
WORK_DIR=$(mktemp -d -t polished-dmg)
TMP_DMG="$WORK_DIR/rw.dmg"

# If a previous run is still mounted (e.g. interrupted), unmount it.
if [ -d "/Volumes/$VOLUME_NAME" ]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet || true
fi

# Size: app + 20MB headroom.
APP_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_MB=$(( (APP_KB / 1024) + 20 ))

hdiutil create \
    -srcfolder "$APP_PATH" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${DMG_MB}m" \
    -quiet \
    "$TMP_DMG"

# Mount via the default /Volumes path. The AppleScript `disk "X"` reference
# below depends on this — using -mountpoint causes Finder to fail to find
# files within the volume when setting the background picture.
ATTACH_OUTPUT=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen)
MOUNT_DIR=$(echo "$ATTACH_OUTPUT" | grep -E '^/dev/' | grep -oE '/Volumes/.*$' | head -1)

if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "Failed to determine mount point from hdiutil output:" >&2
    echo "$ATTACH_OUTPUT" >&2
    exit 1
fi

# Stage layout resources.
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_PNG" "$MOUNT_DIR/.background/background.png"
ln -s /Applications "$MOUNT_DIR/Applications"

# Give Finder a moment to notice the new files before scripting.
sleep 1

# Drive Finder. Errors setting the background are caught and retried — Finder
# sometimes needs the window opened twice before it will accept a background
# picture reference for files it just learned about.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 740, 580}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set text size of theViewOptions to 12
        set position of item "$APP_BASENAME" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        close
        open
        delay 1
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Let Finder flush .DS_Store.
sync
sleep 2

hdiutil detach "$MOUNT_DIR" -quiet

# Compress to final read-only DMG.
rm -f "$DMG_PATH"
hdiutil convert "$TMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    -quiet

rm -rf "$WORK_DIR"

echo "Polished DMG: $DMG_PATH"
