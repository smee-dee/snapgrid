#!/bin/bash
# Runs the tests with code coverage and fails if SnapgridCore's line coverage is below MIN (default 95).
# Extra arguments go to SwiftPM, e.g. --scratch-path ~/Library/Caches/snapgrid-build.
set -euo pipefail
cd "$(dirname "$0")/.."
MIN=${MIN:-95}

swift test --enable-code-coverage "$@"
PROFILE="$(dirname "$(swift test --show-codecov-path "$@")")/default.profdata"
BUNDLE=$(find "$(swift build --show-bin-path "$@")" -maxdepth 1 -name '*.xctest' | head -1)
REPORT=$(xcrun llvm-cov report "$BUNDLE/Contents/MacOS/$(basename "$BUNDLE" .xctest)" \
  -instr-profile "$PROFILE" -ignore-filename-regex '(Tests|DerivedSources)/')
echo "$REPORT"
TOTAL=$(echo "$REPORT" | awk '/^TOTAL/ { print $(NF-3) }' | tr -d %)
awk -v total="$TOTAL" -v min="$MIN" 'BEGIN { exit !(total + 0 >= min + 0) }' ||
  { echo "coverage: SnapgridCore line coverage is $TOTAL%, below $MIN%" >&2; exit 1; }
echo "coverage: $TOTAL% of SnapgridCore lines (minimum $MIN%)"
