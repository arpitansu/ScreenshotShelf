#!/bin/bash
# Builds "Screenshot Shelf.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling…"
swift build -c release

APP="build/Screenshot Shelf.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenshotShelf "$APP/Contents/MacOS/ScreenshotShelf"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo ""
echo "Done: $APP"
echo "Start it with:  open \"$APP\""
