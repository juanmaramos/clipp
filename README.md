# Clipp

A lightweight clipboard manager for macOS with instant paste shortcuts.

**Clipp** is an actively maintained clipboard manager for macOS, based on [Maccy](https://github.com/p0deje/Maccy), with enhanced features and improved UX.

## Features

* **Quick selection** - Press `⌘1`–`⌘9` to activate a visible clipboard item; plain numbers search
* **Text expansion** - Create personal snippets with typed shortcuts, date/time fields, and local storage
* **Keyboard-first** - Navigate with arrows, search, and select without touching the mouse
* **Lightweight and fast** - Native SwiftUI with minimal resource usage
* **Secure and private** - All data stays local, no cloud sync
* **Modern UI** - Rich previews for images, colors, and formatted text
* **Open source and free** - MIT licensed

## Requirements

macOS Sonoma 14 or higher

## Install

Download the latest version (`Clipp.dmg` or `Clipp.zip`) from the [releases](https://github.com/juanmaramos/clipp/releases) page.

## Why Clipp

Clipp is a fast, open-source alternative for people looking for a modern macOS clipboard history app.

If you searched for:
- CopyClip alternative
- Paste app alternative
- Maccy alternative
- macOS clipboard manager open source
- clipboard history manager for Mac

you are in the right place.

## Usage

### Basic Operations

1. Press <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>V</kbd> to open Clipp
2. **Quick selection**: Press `⌘1`–`⌘9` to activate that visible result
3. **Navigate**: Use arrow keys or type to search
4. Press <kbd>Enter</kbd> to paste the selected item
5. Press <kbd>Esc</kbd> to close

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Clipp | <kbd>⇧⌘V</kbd> |
| Activate result 1–9 | `⌘1`–`⌘9` |
| Navigate | <kbd>↑</kbd> <kbd>↓</kbd> |
| Search | Start typing |
| Paste selected | <kbd>Enter</kbd> |
| Pin item | <kbd>⌥P</kbd> |
| Delete item | <kbd>⌥⌫</kbd> |
| Clear history | <kbd>⌥⌘⌫</kbd> |
| Preferences | <kbd>⌘,</kbd> |
| Quit | <kbd>⌘Q</kbd> |

### Advanced Features

**Pin Important Items**
- Press <kbd>⌥P</kbd> on any item to keep it at the top permanently
- Pinned items won't be removed when history fills up
- Great for frequently used snippets

**Search**
- Start typing to filter items instantly
- Supports fuzzy search mode in preferences
- Search works across all clipboard history

**Paste Automatically**
- Enable "Paste automatically" in Preferences → General
- Selecting an item will paste it immediately
- No need to press <kbd>⌘V</kbd> after selection

## Configuration

### Ignore Sensitive Data

Temporarily disable clipboard tracking:
```sh
defaults write org.p0deje.Maccy ignoreEvents true
# Copy sensitive data
defaults write org.p0deje.Maccy ignoreEvents false
```

Or click the menu bar icon with <kbd>⌥</kbd> pressed.

### Ignore Specific Apps

Add apps to the ignore list in Preferences → Ignore → Applications.

### Custom Keyboard Shortcut

Change the main shortcut in Preferences → General → Open.

## FAQ

### Why doesn't auto-paste work?

1. Enable "Paste automatically" in Preferences → General
2. Grant Accessibility permissions: System Settings → Privacy & Security → Accessibility
3. Add Clipp to the list and enable it

### How do I change the menu bar icon?

Preferences → Appearance → Menu Bar Icon

Choose from: Clipboard, Scissors, or Paperclip

### How do I clear all history?

Press <kbd>⇧⌥⌘⌫</kbd> or select "Clear all" from the footer menu with <kbd>⌥</kbd> held.

## Building from Source

```sh
git clone https://github.com/juanmaramos/clipp.git
cd clipp
open Maccy.xcodeproj
```

Build with Xcode 15+ and Swift 5.9+

## Support

If Clipp saves you time, you can support development:

- Buy Me a Coffee: https://buymeacoffee.com/jmramos86k

## Releasing

The current workflow publishes on every push to `main` (except appcast-only changes), or a manual workflow dispatch on `main`. Keep unverified work on a feature branch. Update the marketing version and changelog before merging a release.

GitHub Actions builds, signs, notarizes, and packages Clipp, signs the update with Sparkle, creates a release tag using the workflow run number, uploads ZIP/DMG downloads, and updates `appcast.xml`.

Existing users can enable automatic update checks or choose **Settings → General → Check Now**. New users and users of older builds without the correct update feed can download from [GitHub Releases](https://github.com/juanmaramos/clipp/releases). A manually uploaded ZIP alone does not update the Sparkle feed.

For code signing and notarization setup, see [DISTRIBUTION.md](./DISTRIBUTION.md)

## Snippets

**Development status:** the native library, popup selection, and in-app expansion test are available. System-wide expansion is disabled in the current sandboxed build. Apple does not support the required Accessibility APIs inside App Sandbox; switching the distribution build and preserving existing user data remains a release prerequisite. See [Apple’s explanation](https://developer.apple.com/forums/thread/794253).

Open **Settings → Snippets**, choose **Add examples…** from the library menu, or create a snippet from a text item’s context menu. Personal placeholders remain disabled until edited and enabled. A disabled snippet can still be selected manually from the popup’s Snippets filter.

Supported fields are `{{date}}`, `{{time}}`, `{{datetime}}`, and `{{clipboard}}`. The date/time options configure formatting, locale, time zone, and a calendar-day offset. Clipboard content is inserted literally; it is never evaluated as a template or script.

In a build outside App Sandbox, enable text expansion and allow Clipp in **System Settings → Privacy & Security → Accessibility** and **Input Monitoring**. Then click **Check again**. Password fields, active input-method composition, excluded apps, and fields that cannot verify the text at the caret are skipped. The keyboard buffer is temporary and is not logged. Snippets are stored separately from clipboard history and survive clearing it.

Use **Try it here** to test a draft without granting global keyboard access. For system-wide expansion, Clipp selects the verified abbreviation and pastes the expansion. It preserves all available clipboard items and formats, restores them only if no newer copy replaced them, and excludes its temporary payload from clipboard history. Undo behavior and Accessibility support depend on the destination editor; test the apps you use before relying on automatic expansion.

Debug builds use `futurialabs.clipp.dev`, a separate sandbox and preferences, and do not check for or install public updates.

## Credits

Clipp is a fork of [Maccy](https://github.com/p0deje/Maccy).

## License

[MIT](./LICENSE)
