# Changelog

All notable changes to Clipp will be documented in this file.

## 2.7.1 — 2026-09-08

- Settings now use one resizable window that keeps its size when switching categories and remembers the last size, position, and category.
- Fix clipped General instructions with native, scrolling forms shared by General, Appearance, and History.
- Let Pins, Snippets, and Time saved adapt to the available space. Keep snippet Save/Revert controls visible while scrolling advanced options and previews.
- Cap window height to the current display’s usable area and restore off-screen Settings windows when displays change.

## 2.7.0 — 2026-09-07

- Build 62 fixes the legacy Sparkle public-key mismatch, adds pre-publication signature verification, and uses a dedicated Clipp Homebrew tap to avoid conflicts.

### Added
- Native Snippets settings with editable shortcuts, preview, starter examples, and import/export.
- Local text expansion with case and boundary rules, immediate or Space-delimited triggers, app exclusions, and explicit permission status.
- Date, time, timestamp, relative-day, and clipboard fields. Date/time formats, locale, and time zone are configurable per snippet.
- A Snippets filter in the popup and Create snippet, Paste as plain text, and full-preview context actions.
- Optional expansion sound and visual feedback that does not take focus.
- Local Time saved statistics with reuse/expansion counts, adjustable estimates, a calculation legend, and pause/reset controls.

### Changed
- Plain numbers always search. Command-1 through Command-9 activate visible history results, following the existing copy/paste preference.
- Search excerpts keep the first match visible and use a softer highlight.
- Debug builds use a separate application identifier and cannot install public updates.

### Quality and distribution
- Preserve user preferences during updates; login launch is no longer forced on.
- Restore History settings and group capture/privacy choices there.
- Validate ignore expressions; an invalid old rule no longer disables valid rules.
- Make Skip next copy independent of persistent capture pause.
- Explain missing paste permission and offer copy mode.
- Recover from database errors without discarding existing data.
- Preserve existing container data when moving to Developer ID distribution outside App Sandbox.
- Simplify snippet options, add readable date presets, and confirm snippet deletion.
- Keep library navigation visible when the search field is hidden.
- Remove unused review/shortcut helpers and clipboard-content logging.
- Separate CI from explicit release publication; use a single increasing production build number.
- Add Homebrew installation and update its cask from each signed release ZIP.
- Re-enable the history regression suite and test migration, privacy, and storage failures.

### Fixed
- Keep OCR work off the UI thread while applying recognized text to SwiftData on the main actor.
- Finish pending filtering before keyboard selection and clear stale selections when a search has no results.
- Space-delimited expansion verifies the shortcut before the destination can autocorrect it.
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
