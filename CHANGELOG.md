# Changelog

All notable changes to Clipp will be documented in this file.

## Unreleased

### Added
- Native Snippets settings with editable shortcuts, preview, starter examples, and import/export.
- Local text expansion with case and boundary rules, immediate or Space-delimited triggers, app exclusions, and explicit permission status.
- Date, time, timestamp, relative-day, and clipboard fields. Date/time formats, locale, and time zone are configurable per snippet.
- A Snippets filter in the popup and Create snippet, Paste as plain text, and full-preview context actions.
- Optional expansion sound and visual feedback that does not take focus.

### Changed
- Plain numbers always search. Command-1 through Command-9 activate visible history results, following the existing copy/paste preference.
- Search excerpts keep the first match visible and use a softer highlight.
- Debug builds use a separate application identifier and cannot install public updates.

### Fixed
- Keyboard shortcuts are handled before the search field editor.
- Sparkle updater initialization compiles with current Swift Observation.
- The test suite imports the renamed Clipp module.

## [1.0.1] - 2026-02-06

### Fixed
- Fixed instant number paste - numbers now work correctly (1-9)
- Search auto-focuses when typing letters (maintains search usability)
- Fixed window positioning to appear below menu bar icon
- Fixed max window height (500px instead of full screen)

## [1.0.0] - 2026-02-06

### Added
- **Instant number paste** - Press `1-9` to instantly paste clipboard items (Clipy-style)
- Fixed keyboard shortcut display showing correct modifier symbols (⌘, ⌥, etc.)
- Improved window positioning - menu always stays within screen bounds
- Static shortcut display (no dynamic swapping on modifier press)
- Added clear descriptions for settings shortcuts

### Changed
- Renamed from Maccy to Clipp
- Changed default menu bar icon from arrow to clipboard
- Removed Storage settings tab
- Updated About panel with new branding
- Simplified footer with essential actions only

### Fixed
- Cmd+, shortcut now works correctly even when search is focused
- Viewport bounds checking prevents menu from going off-screen
- Number shortcuts now display as bare numbers (not with modifiers)

### Removed
- Removed downward arrow menu bar icon option
- Removed special thanks from About panel

---

Based on [Maccy](https://github.com/p0deje/Maccy) by Alex Rodionov
