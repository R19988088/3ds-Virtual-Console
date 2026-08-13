#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/release"
DEST="${1:-$ROOT/dist}"
APP="$DEST/vcoven.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/VcovenApp" "$APP/Contents/MacOS/vcoven"
cp -R "$BUILD/VcovenApp_VcovenApp.bundle" "$APP/Contents/Resources/"
cp "$ROOT/Sources/VcovenApp/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>vcoven</string>
  <key>CFBundleIdentifier</key><string>com.r19988088.vcoven</string>
  <key>CFBundleName</key><string>vcoven</string>
  <key>CFBundleDisplayName</key><string>vcoven</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Supported ROM</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>CFBundleTypeExtensions</key><array><string>gba</string><string>sfc</string><string>smc</string></array>
  </dict></array>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
ditto -c -k --keepParent "$APP" "$DEST/vcoven-macOS.zip"
du -sh "$APP" "$DEST/vcoven-macOS.zip"
