# Changelog

All notable changes to Clipp will be documented in this file.

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
