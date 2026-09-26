#!/bin/bash
# Publishes the current version as a GitHub release, which "Check for Updates" picks up.
#
#   1. Bump `static let version` in Sources/snapgrid/CLI.swift, rename CHANGELOG.md's
#      "## [Unreleased]" to "## [<version>] - <date>" (plus a fresh empty Unreleased), commit.
#   2. SIGN_IDENTITY="Apple Development: …" scripts/release.sh
#      The release notes are that version's CHANGELOG.md section.
#
# Needs the GitHub CLI (`gh auth login`) and `origin` pointing at the GitHub repo. Always sign with the
# same certificate: installed copies refuse updates signed by a different team.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/snapgrid/CLI.swift)
TAG=v$VERSION
REPO=$(git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')

[[ -n "$REPO" ]] || die "origin is not a GitHub repo (git remote set-url origin https://github.com/OWNER/snapgrid.git)"
[[ -n "${SIGN_IDENTITY:-}" ]] || die "set SIGN_IDENTITY; ad-hoc builds can't be verified by the updater"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "$TAG already exists; bump the version in Sources/snapgrid/CLI.swift"
fi

NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
awk -v heading="## [$VERSION]" '
  /^## \[/ { if (found) exit; if (index($0, heading) == 1) { found = 1; next } }
  found && /^\[[^]]+\]: / { exit }
  found { print }
' CHANGELOG.md > "$NOTES_FILE"
grep -q '[^[:space:]]' "$NOTES_FILE" ||
  die "CHANGELOG.md has no entries under '## [$VERSION] - YYYY-MM-DD'; move the Unreleased entries there"

git push origin HEAD:refs/heads/main
UPDATE_REPO=$REPO scripts/build-app.sh --zip

gh release create "$TAG" "build/Snapgrid-$VERSION.zip" --repo "$REPO" \
  --target "$(git rev-parse HEAD)" --title "Snapgrid $VERSION" --notes-file "$NOTES_FILE"
echo "Released $TAG: https://github.com/$REPO/releases/tag/$TAG"
