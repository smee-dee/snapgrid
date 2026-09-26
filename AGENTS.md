# Notes for agents

Swift package, Apple frameworks only (no third-party packages). `Sources/SnapgridCore` is platform-independent and unit-tested; `Sources/snapgrid` is the macOS app and CLI. The README's "Config reference" and "Share a build and publish updates" sections are the user-facing docs; keep them in sync with changes. `CONTRIBUTING.md` repeats the build, test and pull request rules for human contributors; update it when those rules change.

## Build and test

- Run `swift build` / `swift test` outside the agent sandbox. Inside it, SwiftPM fails with `sandbox_apply: Operation not permitted`.
- The Command Line Tools have no XCTest, and the repo may sit in iCloud-synced `~/Documents` (codesign rejects iCloud's file attributes). Tests:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path ~/Library/Caches/snapgrid-build`
- `scripts/build-app.sh` already signs in a temp dir outside iCloud; don't move signing back into `build/`.

## Tests

Decisions go in `SnapgridCore` with tests: config rules, geometry and placement, panel behaviour, update policy, setup choices, file writes. The `snapgrid` target should only connect them to AppKit, SwiftUI, Carbon and Accessibility, which can't be unit-tested. Every new feature or fix gets a test for its logic. Keep core line coverage at 95% or more: `scripts/coverage.sh` (same `DEVELOPER_DIR` and `--scratch-path` as above) runs the tests and fails below that. CI (`.github/workflows/tests.yml`) runs it on every push and on pull requests from forks.

What stays manual, for the user after updating: hotkeys register, the grid panel places windows (including + and −, and the leader key moving it across displays), Settings saves and records keys, the setup assistant, iCloud sync and the updater.

## Changelog

Every user-visible change gets a line in `CHANGELOG.md` under `## [Unreleased]`, in the same commit as the change. Use Keep a Changelog headings (`### Added`, `### Changed`, `### Fixed`, `### Removed`) and write for users, not in commit-message style. Internal-only changes (tests, refactors, agent docs) don't need an entry.

## Publish an update

1. Tests pass (command above) and the working tree is clean.
2. Bump `static let version` in `Sources/snapgrid/CLI.swift` (semver; must be higher than the latest release). In `CHANGELOG.md`, rename `## [Unreleased]` to `## [<version>] - <YYYY-MM-DD>`, add a new empty `## [Unreleased]` above it, and update the compare links at the bottom. Commit both.
3. Find the signing identity: `security find-identity -v -p codesigning`, use the "Apple Development: …" identity of team `8NQ55VC3K2`. **Never release with another certificate or ad hoc**: installed copies only accept updates signed by that team, and Accessibility permission is tied to it.
4. `SIGN_IDENTITY="<identity>" scripts/release.sh`. The release notes are the version's `CHANGELOG.md` section; the script refuses to run without one. It must run on `main`: it pushes `main` to `origin` (GitHub, `smee-dee/snapgrid`), waits for CI on that commit, builds and signs `build/Snapgrid-<version>.zip`, and creates release `v<version>`. This is public: get the user's go-ahead first.

   **Betas** come from a branch, not `main`: version `X.Y.Z-beta.N` (the next release's number), changelog entries stay under `## [Unreleased]` (they're the notes; don't add a version section or date). The same script then pushes the branch, waits for CI, publishes a GitHub pre-release and comments on the branch's pull request. Only copies with "Get beta versions" on install it. Before the stable release, set the version on `main` to `X.Y.Z`.
5. Verify:
   - `curl -fsSL https://api.github.com/repos/smee-dee/snapgrid/releases/latest` shows the new tag with a `Snapgrid-<version>.zip` asset (for a beta: `gh release view v<version>` shows it as a pre-release, and `releases/latest` is unchanged).
   - Download and unzip it with `ditto -x -k`, then
     `codesign --verify --strict -R='anchor apple generic and identifier "dev.snapgrid.Snapgrid" and certificate leaf[subject.OU] = "8NQ55VC3K2"' Snapgrid.app` (the updater's own check).
6. Don't install builds on the user's Mac (`build-app.sh --install`); the user updates through the app's own updater, which also tests the release.

## Git

- `origin` is GitHub. The `cursor` remote (origin.cursor.com) is retired; don't push to it.
- `main` is protected: pull requests need the `test` check and one approval. GitHub doesn't let authors approve their own pull requests, so the owner merges with the admin bypass (`gh pr merge <n> --admin`, only when the user asks). Admins may also push to `main` directly, which `release.sh` relies on.
- Never commit the user's config (`~/.config/snapgrid/`, possibly symlinked into iCloud Drive) or anything from Divvy's preferences, which contain a licence key.
