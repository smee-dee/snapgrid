#!/bin/bash
# Publishes the current version as a GitHub release, which "Check for Updates" picks up.
#
# Stable (on main):
#   1. Bump `static let version` in Sources/snapgrid/CLI.swift to e.g. 0.4.0, rename CHANGELOG.md's
#      "## [Unreleased]" to "## [<version>] - <date>" (plus a fresh empty Unreleased), commit.
#   2. SIGN_IDENTITY="Apple Development: …" scripts/release.sh
#      The release notes are that version's CHANGELOG.md section.
#
# Beta (on a feature branch, usually the one behind a pull request):
#   1. Set the version to the next release plus a beta number, e.g. 0.4.0-beta.1, and commit.
#      Leave CHANGELOG.md's entries under "## [Unreleased]"; they become the beta's notes.
#   2. SIGN_IDENTITY="Apple Development: …" scripts/release.sh
#      Publishes a GitHub pre-release that only copies with "Get beta versions" on install,
#      and comments on the branch's pull request.
#
# Either way the commit is pushed first and must pass CI (.github/workflows/tests.yml);
# SKIP_CI=1 skips that wait. Needs the GitHub CLI (`gh auth login`) and `origin` pointing at
# the GitHub repo. Always sign with the same certificate: installed copies refuse updates
# signed by a different team.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { echo "release: $*" >&2; exit 1; }

VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/snapgrid/CLI.swift)
TAG=v$VERSION
BRANCH=$(git branch --show-current)
SHA=$(git rev-parse HEAD)
REPO=$(git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] ||
  die "version '$VERSION' must look like 1.2.3 or 1.2.3-beta.1"
BETA=0; [[ "$VERSION" == *-* ]] && BETA=1
[[ -n "$REPO" ]] || die "origin is not a GitHub repo (git remote set-url origin https://github.com/OWNER/snapgrid.git)"
[[ -n "${SIGN_IDENTITY:-}" ]] || die "set SIGN_IDENTITY; ad-hoc builds can't be verified by the updater"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "$TAG already exists; bump the version in Sources/snapgrid/CLI.swift"
fi

NOTES_FILE=$(mktemp)
trap 'rm -f "$NOTES_FILE"' EXIT
changelog_section() {
  awk -v heading="## [$1]" '
    /^## \[/ { if (found) exit; if (index($0, heading) == 1) { found = 1; next } }
    found && /^\[[^]]+\]: / { exit }
    found { print }
  ' CHANGELOG.md
}
if (( BETA )); then
  [[ "$BRANCH" != main && -n "$BRANCH" ]] || die "betas come from a branch (e.g. the one behind a pull request), not main"
  { echo "Beta for testing; it only reaches copies with \"Get beta versions\" turned on."
    echo "Changes since the last release:"
    changelog_section Unreleased; } > "$NOTES_FILE"
  changelog_section Unreleased | grep -q '[^[:space:]]' ||
    die "CHANGELOG.md has no entries under '## [Unreleased]' to use as the beta's notes"
else
  [[ "$BRANCH" == main ]] || die "stable releases come from main; merge the pull request first (or use a -beta.N version)"
  changelog_section "$VERSION" > "$NOTES_FILE"
  grep -q '[^[:space:]]' "$NOTES_FILE" ||
    die "CHANGELOG.md has no entries under '## [$VERSION] - YYYY-MM-DD'; move the Unreleased entries there"
fi

git push origin "HEAD:refs/heads/$BRANCH"

if [[ -z "${SKIP_CI:-}" ]]; then
  echo "Waiting for CI on ${SHA:0:7}…"
  RUN=""
  for _ in $(seq 1 30); do
    RUN=$(gh run list --repo "$REPO" --workflow tests.yml --commit "$SHA" --json databaseId --jq '.[0].databaseId // empty')
    [[ -n "$RUN" ]] && break
    sleep 5
  done
  [[ -n "$RUN" ]] || die "no CI run found for $SHA (is .github/workflows/tests.yml on this branch?)"
  gh run watch "$RUN" --repo "$REPO" --exit-status >/dev/null ||
    die "CI failed for ${SHA:0:7}: https://github.com/$REPO/actions/runs/$RUN"
fi

UPDATE_REPO=$REPO scripts/build-app.sh --zip

FLAGS=(--latest)
(( BETA )) && FLAGS=(--prerelease --latest=false)
gh release create "$TAG" "build/Snapgrid-$VERSION.zip" --repo "$REPO" "${FLAGS[@]}" \
  --target "$SHA" --title "Snapgrid $VERSION" --notes-file "$NOTES_FILE"
URL="https://github.com/$REPO/releases/tag/$TAG"
echo "Released $TAG: $URL"

if (( BETA )); then
  PR=$(gh pr view "$BRANCH" --repo "$REPO" --json number --jq .number 2>/dev/null || true)
  if [[ -n "$PR" ]]; then
    gh pr comment "$PR" --repo "$REPO" --body "Beta [$VERSION]($URL) is out. To test it: Snapgrid Settings › General › Updates › turn on **Get beta versions**, then **Check Now**."
    echo "Commented on pull request #$PR"
  fi
fi
