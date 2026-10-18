#!/bin/bash
# Builds "Screenshot Shelf.app" (with its text-reading helper) into ./build
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling…"
swift build -c release

BIN=".build/release"
APP="build/Screenshot Shelf.app"
XPC="$APP/Contents/XPCServices/local.arpit.screenshotshelf.OCRService.xpc"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$XPC/Contents/MacOS"

# Text-reading helper (XPC service)
cp "$BIN/OCRService" "$XPC/Contents/MacOS/OCRService"
cp OCRService-Info.plist "$XPC/Contents/Info.plist"

# Main app
cp "$BIN/ScreenshotShelf" "$APP/Contents/MacOS/ScreenshotShelf"
cp Info.plist "$APP/Contents/Info.plist"

# Sign inside-out: helper first, then the app around it.
codesign --force --sign - "$XPC" || echo "Warning: couldn't sign the helper"
codesign --force --sign - "$APP" || echo "Warning: couldn't sign the app"

echo ""
echo "Done: $APP"
echo "Start it with:  open \"$APP\""
