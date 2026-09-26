#!/bin/bash
# Publishes the current version as a GitHub release, which "Check for Updates" picks up.
#
#   1. Bump `static let version` in Sources/snapgrid/CLI.swift and commit.
#   2. SIGN_IDENTITY="Apple Development: …" scripts/release.sh
#      (optional: NOTES="What changed" instead of GitHub's generated notes)
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

git push origin HEAD:refs/heads/main
UPDATE_REPO=$REPO scripts/build-app.sh --zip

NOTE_ARGS=(--generate-notes)
[[ -n "${NOTES:-}" ]] && NOTE_ARGS=(--notes "$NOTES")
gh release create "$TAG" "build/Snapgrid-$VERSION.zip" --repo "$REPO" \
  --target "$(git rev-parse HEAD)" --title "Snapgrid $VERSION" "${NOTE_ARGS[@]}"
echo "Released $TAG: https://github.com/$REPO/releases/tag/$TAG"
