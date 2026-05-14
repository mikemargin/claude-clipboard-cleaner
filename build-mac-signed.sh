#!/bin/bash
#
# Build, sign, and notarize Claude Clipboard Cleaner for public distribution.
#
# This wraps build.sh: it produces the same .app / .zip / .dmg layout, but the
# binaries are code-signed with the hardened runtime, the DMG is submitted to
# Apple's notary service, and the notarization ticket is stapled onto both the
# .app and the .dmg. The final zip is produced from the stapled .app so it
# passes Gatekeeper offline.
#
# Prerequisites (one-time setup):
#
#   1. Apple Developer Program membership ($99/yr). Notarization requires a
#      paid account.
#         https://developer.apple.com/programs/
#
#   2. A "Developer ID Application" certificate installed in your login
#      keychain. In Xcode:
#         Settings → Accounts → your Apple ID → Manage Certificates →
#         "+" → "Developer ID Application"
#      This script auto-discovers the identity via `security find-identity`.
#
#   3. An app-specific password for notarytool (NOT your Apple ID password):
#         https://account.apple.com → Sign-In and Security →
#         App-Specific Passwords → Generate
#
#   4. Your 10-character Apple Team ID:
#         https://developer.apple.com/account → Membership Details
#
# Create a .env file in the project root (already covered by .gitignore):
#
#     APPLE_ID=you@example.com
#     APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
#     APPLE_TEAM_ID=ABCD123456
#
# Run:
#
#     ./build-mac-signed.sh [version]
#
# Output lands in dist/:
#
#     dist/Claude Clipboard Cleaner.app             (signed + stapled)
#     dist/ClaudeClipboardCleaner-<ver>-arm64.zip   (from stapled .app)
#     dist/ClaudeClipboardCleaner-<ver>-arm64.dmg   (signed + stapled)
#
# Notes:
#   - codesign passes --timestamp because notarization rejects submissions
#     without a secure timestamp.
#   - The hardened runtime (--options runtime) is required for notarization.
#   - If the app ever needs special privileges (Apple Events, network sandbox,
#     etc.) add `--entitlements path/to/entitlements.plist` to the codesign
#     invocation below.

set -e
cd "$(dirname "$0")"

# Load .env
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
    echo "❌ .env must define APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID (see header)"
    exit 1
fi

VERSION=${1:-"1.0.0"}
APP_NAME="Claude Clipboard Cleaner"
BUNDLE_ID="ClaudeClipboardCleaner"
BUILD_DIR="build"
DIST_DIR="dist"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DIST_APP="$DIST_DIR/$APP_NAME.app"
DIST_ZIP="$DIST_DIR/$BUNDLE_ID-$VERSION-arm64.zip"
DIST_DMG="$DIST_DIR/$BUNDLE_ID-$VERSION-arm64.dmg"

# Find a Developer ID Application identity in the keychain.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ -z "$IDENTITY" ]; then
    echo "❌ No 'Developer ID Application' certificate found (see header for setup)"
    exit 1
fi
echo "🔑 Signing identity: $IDENTITY"

# Produce unsigned artifacts in build/ (.app + .zip + .dmg).
./build.sh

# Sign the .app with hardened runtime and a secure timestamp.
echo "🔐 Signing app..."
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" \
    "$APP_BUNDLE"

codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep "Authority"

# Stage the signed .app in dist/. ditto preserves the signature and metadata.
mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP"
ditto "$APP_BUNDLE" "$DIST_APP"

# Build a signed DMG from the signed .app. The unsigned DMG that build.sh
# produced in build/ is stale at this point — we rebuild here so the DMG
# contains the signed bundle. build.sh already generated build/dmg_background.png.
echo "📦 Creating DMG..."
./scripts/make_polished_dmg.sh "$DIST_APP" "$DIST_DMG" build/dmg_background.png "$APP_NAME"

codesign --force --timestamp --sign "$IDENTITY" "$DIST_DMG"

# Submit to Apple's notary service and wait for the result (~1–5 min).
echo "📤 Notarizing..."
xcrun notarytool submit "$DIST_DMG" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

# Staple the notarization ticket so Gatekeeper can validate offline.
echo "📎 Stapling..."
xcrun stapler staple "$DIST_APP"
xcrun stapler staple "$DIST_DMG"

# Produce the final zip from the stapled .app. ditto preserves the signature
# and the stapled ticket.
echo "📦 Creating zip..."
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$DIST_APP" "$DIST_ZIP"

echo ""
echo "✅ Done:"
echo "   App: $DIST_APP"
echo "   Zip: $DIST_ZIP   ($(du -h "$DIST_ZIP" | cut -f1))"
echo "   DMG: $DIST_DMG   ($(du -h "$DIST_DMG" | cut -f1))"
