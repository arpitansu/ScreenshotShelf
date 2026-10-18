# Screenshot Shelf

A small menu bar app for macOS 13+. New screenshots go to a floating shelf
instead of piling up on your Desktop.

## Build and run

    cd ~/Desktop/screnshotshelf
    ./build.sh
    open "build/Screenshot Shelf.app"

Needs Xcode or the Command Line Tools (`xcode-select --install`).
The first time, macOS asks to let the app access your Desktop. Click **Allow**:
that's how it picks up new screenshots.

## What it does

- Take a screenshot (⇧⌘3 / ⇧⌘4 / ⇧⌘5). It moves to `~/Pictures/Screenshot Shelf`
  and appears on the shelf at the top-right of your screen.
- Hover a card: **Copy** (image), **Copy text** (on-device text recognition),
  **Pin**, **Move to Trash**. Drag a card straight into any app. Double-click to open.
- Menu bar icon: search the text inside every screenshot, see pinned ones,
  change auto-delete (1–30 days, default 7).
- **Clipboard history:** everything you copy (text and images) is saved. Press
  **⌃⌘V** anywhere to open it, type to search, click or press Return to copy an
  entry again, then ⌘V to paste. Pin entries you reuse. Copies from password
  managers are skipped. Also in the menu bar under the **Clipboard** tab.
- Unpinned screenshots older than the limit go to the Trash (recoverable);
  old clipboard entries are removed (max 200 kept).
- Screenshots already on your Desktop when the app starts are left alone.

## Start at login (optional)

Copy the app to /Applications, then System Settings → General → Login Items → +.
