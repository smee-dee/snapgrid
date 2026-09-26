#!/bin/bash
# Builds GridKeys.app (arm64) and optionally installs it.
#
#   scripts/build-app.sh             # build to build/GridKeys.app
#   scripts/build-app.sh --install   # also copy to /Applications and link the CLI
#
# Signing: macOS ties the Accessibility grant to the code signature. Ad-hoc signing
# (the fallback) changes on every build, so you'd have to re-grant after each rebuild.
# Set SIGN_IDENTITY to a stable identity, e.g. your free "Apple Development: …" cert
# (list them with: security find-identity -v -p codesigning).
set -euo pipefail

cd "$(dirname "$0")/.."
APP=build/GridKeys.app
BUNDLE_ID=dev.gridkeys.GridKeys
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/gridkeys/CLI.swift)

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/gridkeys

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/gridkeys"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>GridKeys</string>
  <key>CFBundleExecutable</key><string>gridkeys</string>
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
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/gridkeys"))"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "GridKeys"' 2>/dev/null || true
  rm -rf /Applications/GridKeys.app
  cp -R "$APP" /Applications/
  LINK_DIR=/opt/homebrew/bin
  [[ -d "$LINK_DIR" && -w "$LINK_DIR" ]] || LINK_DIR="$HOME/.local/bin"
  mkdir -p "$LINK_DIR"
  ln -sf /Applications/GridKeys.app/Contents/MacOS/gridkeys "$LINK_DIR/gridkeys"
  echo "Installed /Applications/GridKeys.app; CLI linked at $LINK_DIR/gridkeys"
  open /Applications/GridKeys.app
fi
