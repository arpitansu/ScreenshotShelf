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
- Hover a card: **Copy** (image), **Copy text**, **Pin**, **Move to Trash**.
  Drag a card straight into any app. Double-click to open.
- Menu bar icon: search the text inside your screenshots, see pinned ones,
  change auto-delete (1–30 days, default 7).
- **Clipboard history:** everything you copy (text and images) is saved. Press
  **⌃⌘V** anywhere to open it, type to search, click or press Return to copy an
  entry again, then ⌘V to paste. Pin entries you reuse. Copies from password
  managers are skipped.
- **Pause clipboard history** when copying something sensitive: the **Pause** link
  at the bottom of the shelf's Clipboard tab, or the **Pause history** checkbox in
  the menu bar's Clipboard tab. While paused, nothing you copy is saved (not even
  after you resume). It stays paused until you press **Resume**, even across restarts.
- Unpinned screenshots older than the limit go to the Trash (recoverable);
  old clipboard entries are removed (max 200 kept).
- Screenshots already on your Desktop when the app starts are left alone.

## How it stays light

- **No polling for screenshots.** macOS wakes the app only when the screenshot
  folder changes.
- **Text is read only when you need it** — when you press Copy text or search.
  Each screenshot is read once and the result is saved.
- **Text reading runs in a separate helper** (an XPC service inside the app,
  shown as "Screenshot Shelf Text Reader"). It starts on demand and quits about
  5 seconds after its last job, handing all its memory back to the system.
  The main app never loads Apple's text-recognition engine.
- The shelf's views and thumbnails are freed whenever it's hidden.
- The clipboard is checked twice a second (macOS has no "copied" notification);
  each check reads a single number.
- "AutoFill (Screenshot Shelf)" in Activity Monitor is a macOS system helper that
  appears for any app's text box. It isn't part of this app.

## Start at login (optional)

Copy the app to /Applications, then System Settings → General → Login Items → +.
