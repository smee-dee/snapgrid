# Notes for agents

Swift package, Apple frameworks only (no third-party packages). `Sources/SnapgridCore` is platform-independent and unit-tested; `Sources/snapgrid` is the macOS app and CLI. The README's "Config reference" and "Share a build and publish updates" sections are the user-facing docs; keep them in sync with changes.

## Build and test

- Run `swift build` / `swift test` outside the agent sandbox. Inside it, SwiftPM fails with `sandbox_apply: Operation not permitted`.
- The Command Line Tools have no XCTest, and the repo may sit in iCloud-synced `~/Documents` (codesign rejects iCloud's file attributes). Tests:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path ~/Library/Caches/snapgrid-build`
- `scripts/build-app.sh` already signs in a temp dir outside iCloud; don't move signing back into `build/`.

## Publish an update

1. Tests pass (command above) and the working tree is clean.
2. Bump `static let version` in `Sources/snapgrid/CLI.swift` (semver; must be higher than the latest release) and commit.
3. Find the signing identity: `security find-identity -v -p codesigning`, use the "Apple Development: …" identity of team `8NQ55VC3K2`. **Never release with another certificate or ad hoc**: installed copies only accept updates signed by that team, and Accessibility permission is tied to it.
4. `SIGN_IDENTITY="<identity>" NOTES="<what changed>" scripts/release.sh`. It pushes `HEAD` to `main` on `origin` (GitHub, `smee-dee/snapgrid`), builds and signs `build/Snapgrid-<version>.zip`, and creates release `v<version>`. This is public: get the user's go-ahead first.
5. Verify:
   - `curl -fsSL https://api.github.com/repos/smee-dee/snapgrid/releases/latest` shows the new tag with a `Snapgrid-<version>.zip` asset.
   - Download and unzip it with `ditto -x -k`, then
     `codesign --verify --strict -R='anchor apple generic and identifier "dev.snapgrid.Snapgrid" and certificate leaf[subject.OU] = "8NQ55VC3K2"' Snapgrid.app` (the updater's own check).
6. Optionally install it locally: `SIGN_IDENTITY=… scripts/build-app.sh --install`.

## Git

- `origin` is GitHub. The `cursor` remote (origin.cursor.com) is retired; don't push to it.
- Never commit the user's config (`~/.config/snapgrid/`, possibly symlinked into iCloud Drive) or anything from Divvy's preferences, which contain a licence key.
