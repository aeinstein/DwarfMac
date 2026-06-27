#!/usr/bin/env bash
# Baut DwarfMac als .app-Bundle und erstellt eine DMG.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DwarfMac"
BUNDLE="$APP_NAME.app"
VERSION="${1:-1.0}"

echo "→ Release-Build …"
swift build -c release

BINPATH="$(swift build -c release --show-bin-path)"
BINARY="$BINPATH/$APP_NAME"

# VLCKit.framework lokalisieren
FW="$(find .build/artifacts -path '*macos-arm64*/VLCKit.framework' -type d 2>/dev/null | head -1)"
if [ -z "$FW" ]; then
  echo "Fehler: VLCKit.framework nicht gefunden — 'swift package resolve' ausführen." >&2
  exit 1
fi

echo "→ Bundle zusammenbauen …"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Frameworks"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"

# VLCKit einbetten (kopieren, nicht symlinken — für Distribution)
cp -R "$FW" "$BUNDLE/Contents/Frameworks/VLCKit.framework"

# Resources (astronomy_data.db etc.)
if [ -d "$BINPATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BINPATH/${APP_NAME}_${APP_NAME}.bundle" "$BUNDLE/Contents/Resources/"
fi
# Einzelne Resource-Dateien
for f in astronomy_data.db; do
  [ -f "$BINPATH/$f" ] && cp "$BINPATH/$f" "$BUNDLE/Contents/Resources/" || true
done

# Info.plist aufbauen
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>          <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>   <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>    <string>de.dwarfmac.app</string>
    <key>CFBundleVersion</key>       <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleExecutable</key>    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>   <string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>DwarfMac benötigt den Standort für die Teleskop-Kalibrierung.</string>
</dict>
</plist>
PLIST

# rpath der Binary auf das eingebettete Framework zeigen
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "→ Ad-hoc signieren …"
codesign --force --deep --sign - "$BUNDLE"

echo "→ DMG erstellen …"
DMG="${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$BUNDLE" \
  -ov -format UDZO \
  "$DMG"

echo ""
echo "✓ Fertig: $DMG"
