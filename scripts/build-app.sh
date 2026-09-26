#!/bin/bash
# Builds Snapgrid.app (arm64) and optionally installs it.
#
#   scripts/build-app.sh             # build to build/Snapgrid.app
#   scripts/build-app.sh --install   # also copy to /Applications and link the CLI
#
# Signing: macOS ties the Accessibility grant to the code signature. Ad-hoc signing
# (the fallback) changes on every build, so you'd have to re-grant after each rebuild.
# Set SIGN_IDENTITY to a stable identity, e.g. your free "Apple Development: …" cert
# (list them with: security find-identity -v -p codesigning).
set -euo pipefail

cd "$(dirname "$0")/.."
APP=build/Snapgrid.app
BUNDLE_ID=dev.snapgrid.Snapgrid
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/snapgrid/CLI.swift)

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
</dict>
</plist>
PLIST

IDENTITY=${SIGN_IDENTITY:--}
if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing; Accessibility must be re-granted after every rebuild (set SIGN_IDENTITY to avoid this)" >&2
fi
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/snapgrid"))"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Snapgrid"' 2>/dev/null || true
  rm -rf /Applications/Snapgrid.app
  cp -R "$APP" /Applications/
  LINK_DIR=/opt/homebrew/bin
  [[ -d "$LINK_DIR" && -w "$LINK_DIR" ]] || LINK_DIR="$HOME/.local/bin"
  mkdir -p "$LINK_DIR"
  ln -sf /Applications/Snapgrid.app/Contents/MacOS/snapgrid "$LINK_DIR/snapgrid"
  echo "Installed /Applications/Snapgrid.app; CLI linked at $LINK_DIR/snapgrid"
  open /Applications/Snapgrid.app
fi
