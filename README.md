# Clipp

A lightweight clipboard manager for macOS with instant paste shortcuts.

**Clipp** is a fork of [Maccy](https://github.com/p0deje/Maccy) with enhanced features and improved UX.

## Features

* **Instant number paste** - Press `1-9` to instantly paste clipboard items (Clipy-style)
* **Keyboard-first** - Navigate with arrows, search, and select without touching the mouse
* **Lightweight and fast** - Native SwiftUI with minimal resource usage
* **Secure and private** - All data stays local, no cloud sync
* **Modern UI** - Rich previews for images, colors, and formatted text
* **Open source and free** - MIT licensed

## Requirements

macOS Sonoma 14 or higher

## Install

Download the latest version from the [releases](https://github.com/juanmaramos/clipp/releases) page.

## Usage

### Basic Operations

1. Press <kbd>⇧</kbd> + <kbd>⌘</kbd> + <kbd>V</kbd> to open Clipp
2. **Instant paste**: Press `1-9` to instantly paste that item
3. **Navigate**: Use arrow keys or type to search
4. Press <kbd>Enter</kbd> to paste the selected item
5. Press <kbd>Esc</kbd> to close

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open Clipp | <kbd>⇧⌘V</kbd> |
| Instant paste | `1-9` (just the number) |
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

## Releasing

To create a new release:

```sh
# Update version in CHANGELOG.md
# Commit your changes
git add .
git commit -m "Release v1.0.0"

# Create and push tag
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will automatically:
1. Build the app
2. Create a .zip package
3. Generate SHA-256 checksum
4. Create a GitHub Release
5. Attach downloadable files

Users can then download from: https://github.com/juanmaramos/clipp/releases

For code signing and notarization setup, see [DISTRIBUTION.md](./DISTRIBUTION.md)

## Credits

Clipp is a fork of [Maccy](https://github.com/p0deje/Maccy) by Alex Rodionov.

## License

[MIT](./LICENSE)
