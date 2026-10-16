<p align="center">
  <img src="docs/images/clipboard-shelf-icon.png" width="88" alt="Clipboard Shelf app icon">
</p>

<h1 align="center">Clipboard Shelf</h1>

<p align="center">A quiet macOS menu-bar clipboard history with search, pins, and a pause switch.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/clipboard-shelf/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+ · Apple silicon and Intel</p>

<p align="center">
  <a href="https://github.com/9phfr6dsw4-dotcom/clipboard-shelf/releases/latest"><img src="https://img.shields.io/github/v/release/9phfr6dsw4-dotcom/clipboard-shelf?style=flat-square" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-111111?style=flat-square&amp;logo=apple" alt="macOS 26 or later">
  <a href="https://github.com/9phfr6dsw4-dotcom/clipboard-shelf/actions/workflows/macos-ci.yml"><img src="https://github.com/9phfr6dsw4-dotcom/clipboard-shelf/actions/workflows/macos-ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/9phfr6dsw4-dotcom/clipboard-shelf?style=flat-square" alt="MIT License"></a>
</p>

<p align="center"><img src="docs/images/clipboard-shelf-popover.png" width="420" alt="Clipboard Shelf: search, All and Pinned, a pause button, pinned items with gold pins, and recent items with their copy times"></p>

## Features

- **Everything you copy, one click away.** Click the clipboard icon in the menu bar to see the text you've copied recently, newest first, with how long ago you copied it ("Copied 8 minutes ago"). Click an item to copy it again.
- **Pin what you reuse.** Pinned items sit at the top with a gold pin and never fall off the list. Switch between **All** and **Pinned**.
- **Search as you type** through everything on the shelf.
- **Keep 20, 50 or 100 recent items**, chosen from the ⋯ menu. Pins don't count toward the limit.
- **Pause anytime.** The round pause button stops saving new copies (the menu-bar icon changes so you can tell), and **Clear recent** empties the list while keeping your pins.
- **Private by design.** Items marked as concealed, temporary or auto-generated (for example by password managers, or text EchoFlow pastes for you) are skipped, and nothing is saved while Apple Passwords or Keychain Access is in front.
- **Quiet.** It lives in the menu bar, with no Dock icon and no windows to manage.

## Install

1. Download the ZIP from the latest release and unzip it.
2. Move **Clipboard Shelf.app** to your **Applications** folder before opening it (choose **Replace** when updating).
3. Open it once.
4. Click its clipboard icon in the menu bar to search or use your history.

<details>
<summary>First launch on macOS</summary>

The release is ad-hoc signed and not notarized. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**, confirm, then reopen Clipboard Shelf from Applications. No additional macOS privacy permission is required.

</details>

## Privacy

Clipboard history and preferences are stored locally in macOS `UserDefaults`. Clipboard Shelf has no networking or analytics code. Press the pause button whenever you do not want new copies saved.

<details>
<summary>Build and test</summary>

On a Mac with macOS 26 and Xcode 26 (the app icon is compiled from `Resources/AppIcon.icon`):

```sh
bash Scripts/test.sh
bash Scripts/build.sh
```

The build creates a Universal 2 app and validates its bundle, signature, architectures, and packaged self-test.

</details>
