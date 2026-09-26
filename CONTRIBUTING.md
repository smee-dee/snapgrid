# Contributing to Snapgrid

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Issues

- **Bugs:** say what you did, what you expected and what happened, plus your macOS version and Snapgrid version (menu bar › Settings, or `snapgrid version`). If it's about a shortcut or placement, include the relevant part of your `config.toml`.
- **Bigger changes:** open an issue first, so we can agree on the approach before you spend time on it.

## Build and test

You need Xcode (the Command Line Tools alone have no XCTest).

```bash
git clone https://github.com/smee-dee/snapgrid.git && cd snapgrid
swift test
scripts/build-app.sh            # builds build/Snapgrid.app, signed ad hoc
```

- If Xcode isn't the selected developer directory, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- If the repo sits in an iCloud-synced folder such as `~/Documents`, add `--scratch-path ~/Library/Caches/snapgrid-build` to `swift test`, because codesign rejects the file attributes iCloud adds.
- An ad hoc build needs Accessibility permission again after every rebuild. With your own free Apple Development certificate (`SIGN_IDENTITY="Apple Development: …"`) the permission survives rebuilds. Quit any installed Snapgrid first, so the two don't compete for the same hotkeys.

## How the code is organised

- `Sources/SnapgridCore` holds all the rules: config parsing, grid geometry and placement, the grid panel's behaviour, the Divvy import, update policy, setup choices. It's platform-independent and unit-tested.
- `Sources/snapgrid` is the macOS app and CLI. It only connects the core to AppKit, SwiftUI, Carbon hotkeys and the Accessibility API.

## Pull requests

- **Apple frameworks only.** No third-party packages.
- **Logic goes in `SnapgridCore`, with tests.** Every feature or fix gets a test for its logic. Core line coverage stays at 95% or more: `scripts/coverage.sh` checks it, and GitHub Actions runs it on every pull request.
- **Changelog:** add a line under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) for anything users will notice, written for users (Keep a Changelog headings: Added, Changed, Fixed, Removed).
- **Docs:** if you add or change a config option, update the README's "Config reference".
- **Keep it small and readable,** and match the style of the surrounding code.
- **Try it by hand** for anything the tests can't reach: hotkeys register, the grid panel places windows (including + and − and moving across displays), Settings saves and records keys, the setup assistant.
- **Don't** bump the version, move the changelog section to a release, or touch the release scripts' signing settings.

## Releases

Releases are made by the maintainer: version bump, signing with the project's certificate, and publishing on GitHub. Installed copies only accept updates signed by that certificate, so contributors never need it. Your change ships in the next release after it's merged. For bigger changes, the maintainer may publish a beta from your pull request first; testers get it with "Get beta versions" in Settings, and the pull request gets a comment with the link.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
