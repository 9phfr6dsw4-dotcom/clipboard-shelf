# Clipboard Shelf

Clipboard Shelf is a private, native macOS menu-bar app that keeps a searchable history of copied text.

## Features

- Remembers the 20 most recent text copies.
- Pins favorites so they are not removed when newer items arrive.
- Searches copied text instantly and without case sensitivity.
- Copies an item back to the clipboard with one click.
- Clears recent items while preserving pins.
- Skips clipboard items marked concealed, transient, auto-generated, or by known password-manager pasteboard types.
- Saves everything locally in macOS `UserDefaults`; it has no networking or analytics.
- Runs only in the menu bar, without a Dock icon.
- Supports Apple silicon and Intel Macs running macOS 13 or newer.

## Install

1. Download `Clipboard-Shelf-1.0.0.zip` from the private GitHub release.
2. Double-click the ZIP and move **Clipboard Shelf.app** into Applications.
3. The first time, Control-click the app, choose **Open**, then choose **Open** again. This is required because the private build is ad-hoc signed rather than Apple-notarized.
4. Look for the clipboard icon in the menu bar.

## Build and test

On a Mac with Apple Command Line Tools or Xcode installed:

```bash
bash Scripts/test.sh
bash Scripts/build.sh
```

The build script creates a Universal 2 application and ZIP in `dist/`, validates the bundle, verifies the signature and architectures, and runs the packaged app's self-test.
