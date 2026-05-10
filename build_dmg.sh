#!/usr/bin/env bash
#
# build_dmg.sh
# DevPad — build a Release .app and package it into a distributable .dmg.
#
# Usage:
#   ./build_dmg.sh              # build with ad-hoc signing (local use only)
#   ./build_dmg.sh --signed     # use the code-signing identity from Xcode
#
# Output: build/DevPad.dmg
#
# Copyright © 2026 bachbnt. All rights reserved.
#

set -euo pipefail

# Resolve to the script's directory so the script can be invoked from anywhere.
cd "$(dirname "$0")"

PROJECT="DevPad"
SCHEME="DevPad"
CONFIG="Release"
BUILD_DIR="$(pwd)/build"
DERIVED="$BUILD_DIR/DerivedData"
DMG_STAGE="$BUILD_DIR/dmg-stage"
DMG_PATH="$BUILD_DIR/$PROJECT.dmg"
DMG_VOL_NAME="$PROJECT"

SIGNED=0
if [[ "${1:-}" == "--signed" ]]; then
    SIGNED=1
fi

# --- preflight ---------------------------------------------------------------

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌  xcodebuild not found. Install Xcode and try again." >&2
    exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
    echo "❌  hdiutil not found (should be a macOS default)." >&2
    exit 1
fi

# --- clean -------------------------------------------------------------------

echo "🧹  Cleaning previous build artifacts…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DMG_STAGE"

# --- build -------------------------------------------------------------------

echo "🔨  Building $PROJECT ($CONFIG)…"

XC_FLAGS=(
    -project "$PROJECT.xcodeproj"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -derivedDataPath "$DERIVED"
)

if [[ $SIGNED -eq 0 ]]; then
    # Ad-hoc signing — no developer ID needed. The resulting app will not
    # be notarized; first launch requires right-click → Open.
    XC_FLAGS+=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM=""
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=YES
    )
fi

# `-quiet` suppresses the firehose of Xcode logs but still prints errors.
xcodebuild "${XC_FLAGS[@]}" -quiet build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$PROJECT.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌  Build output not found at $APP_PATH" >&2
    exit 1
fi

echo "✅  Built: $APP_PATH"

# --- stage -------------------------------------------------------------------

echo "📦  Staging DMG contents…"

cp -R "$APP_PATH" "$DMG_STAGE/"
# A symlink to /Applications gives the user a familiar drag-to-install layout.
ln -s /Applications "$DMG_STAGE/Applications"

# --- create dmg --------------------------------------------------------------

echo "💿  Creating DMG…"

# UDZO = compressed read-only, the standard format for distributed apps.
hdiutil create \
    -volname "$DMG_VOL_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "🎉  Done."
echo "    $DMG_PATH ($DMG_SIZE)"

if [[ $SIGNED -eq 0 ]]; then
    echo ""
    echo "ℹ️  Built unsigned. To open the installed app the first time:"
    echo "   right-click $PROJECT.app → Open → Open in the dialog."
fi
