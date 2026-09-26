# Changelog

All notable changes to Snapgrid. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). `scripts/release.sh` publishes each version's section as its GitHub release notes.

## [Unreleased]

## [0.3.1] - 2026-09-26

### Added
- A notification when an update is found (once per version), with an Install and Restart button. macOS asks once whether Snapgrid may send notifications.

### Changed
- The update dot on the menu-bar icon is now in your accent colour, so it's easier to spot.

## [0.3.0] - 2026-09-26

### Added
- Screen margins separate from the gap between windows (Settings › General › Grid, or `margin` in the config), like Divvy's screen and window margins.
- The grid panel has + and − buttons for its columns and rows, and remembers the size you picked until you change the grid in Settings.
- With several displays, pressing the leader key again moves the grid panel to the next display, and the window is placed on the display where the panel is. After the last display, the panel closes.
- The Divvy import also brings over Divvy's default grid size and margins.

## [0.2.3] - 2026-09-26

### Added
- A dot on the menu-bar icon shows that an update is waiting.
- "Install updates automatically" in Settings › General › Updates (off by default). The update installs once the Mac has been idle for 10 minutes, but never while the grid panel is open or Settings has unsaved changes.

## [0.2.2] - 2026-09-26

### Changed
- Settings says which options apply immediately (iCloud sync, launch at login) and which need Save (shortcuts, grid, leader key).

## [0.2.1] - 2026-09-26

### Added
- A gear button at the top right of the grid panel opens Settings, like Divvy's.

## [0.2.0] - 2026-09-26

### Added
- Divvy's panel: the leader key opens a translucent grid over the focused window's display. Drag across it and release to place the window, or press a leader shortcut. Esc, a click elsewhere or the leader key again closes it.
- `show_grid` setting (on by default), with a toggle in Settings › General.

### Fixed
- Check for Updates now says whether you're up to date, shows the available version, or explains why the check failed, instead of opening Settings.

## [0.1.0] - 2026-09-26

### Added
- Grid window placement with global shortcuts, a grid size per shortcut, an optional gap, and moving windows to the next or previous display.
- Leader key for Divvy's panel-only shortcuts.
- Divvy import (`snapgrid import-divvy`, and in the app), including Divvy's panel hotkey as the leader.
- Settings window: record shortcuts, pick cells on a grid, and set the grid, gap, leader key and launch at login.
- Setup assistant on first launch: Accessibility permission, then keep your config, import from Divvy, use iCloud Drive settings or start with examples.
- Sync with iCloud Drive.
- Check for Updates with in-app install, which only accepts updates signed by the same developer.

[Unreleased]: https://github.com/smee-dee/snapgrid/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/smee-dee/snapgrid/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/smee-dee/snapgrid/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/smee-dee/snapgrid/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/smee-dee/snapgrid/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/smee-dee/snapgrid/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/smee-dee/snapgrid/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/smee-dee/snapgrid/releases/tag/v0.1.0
