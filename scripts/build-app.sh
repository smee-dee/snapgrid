#!/bin/bash
# Builds Snapgrid.app (arm64) and optionally installs it.
#
#   scripts/build-app.sh             # build to build/Snapgrid.app
#   scripts/build-app.sh --install   # also copy to /Applications and link the CLI
#   scripts/build-app.sh --zip       # also write build/Snapgrid-<version>.zip to share
#
# Signing: macOS ties the Accessibility grant to the code signature. Ad-hoc signing
# (the fallback) changes on every build, so you'd have to re-grant after each rebuild.
# Set SIGN_IDENTITY to a stable identity, e.g. your free "Apple Development: …" cert
# (list them with: security find-identity -v -p codesigning).
set -euo pipefail

INSTALL=0 ZIP=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --zip) ZIP=1 ;;
    *) echo "unknown option: $arg (use --install and/or --zip)" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
OUT=build/Snapgrid.app
# Assembled and signed outside the repo: codesign rejects the extended attributes
# that iCloud Drive keeps adding to files under ~/Documents.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP=$STAGE/Snapgrid.app
BUNDLE_ID=dev.snapgrid.Snapgrid
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/snapgrid/CLI.swift)
# "owner/repo" whose GitHub Releases the app checks for updates; defaults to the `origin` remote.
UPDATE_REPO=${UPDATE_REPO:-$(git remote get-url origin 2>/dev/null | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')}

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/snapgrid

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/snapgrid"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Snapgrid</string>
  <key>CFBundleExecutable</key><string>snapgrid</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Personal build</string>
  <key>SnapgridUpdateRepo</key><string>${UPDATE_REPO}</string>
</dict>
</plist>
PLIST

IDENTITY=${SIGN_IDENTITY:--}
if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing; Accessibility must be re-granted after every rebuild (set SIGN_IDENTITY to avoid this)" >&2
fi
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
ditto "$APP" "$OUT"
echo "Built $OUT ($(lipo -archs "$APP/Contents/MacOS/snapgrid"), updates from: ${UPDATE_REPO:-none})"

if (( ZIP )); then
  ZIPFILE=build/Snapgrid-$VERSION.zip
  rm -f "$ZIPFILE"
  ditto -c -k --keepParent "$APP" "$ZIPFILE"
  echo "Packaged $ZIPFILE"
fi

if (( INSTALL )); then
  osascript -e 'quit app "Snapgrid"' 2>/dev/null || true
  rm -rf /Applications/Snapgrid.app
  ditto "$APP" /Applications/Snapgrid.app
  LINK_DIR=/opt/homebrew/bin
  [[ -d "$LINK_DIR" && -w "$LINK_DIR" ]] || LINK_DIR="$HOME/.local/bin"
  mkdir -p "$LINK_DIR"
  ln -sf /Applications/Snapgrid.app/Contents/MacOS/snapgrid "$LINK_DIR/snapgrid"
  echo "Installed /Applications/Snapgrid.app; CLI linked at $LINK_DIR/snapgrid"
  open /Applications/Snapgrid.app
fi
