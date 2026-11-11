#!/bin/bash
# Builds ThirdTimer.app into ./build. Needs a Mac with Xcode or the
# Xcode Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ThirdTimer"

APP="build/ThirdTimer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ThirdTimer"

# The bell recording, if one has been added (see Resources/README.md).
mkdir -p "$APP/Contents/Resources"
for sound in Resources/bell.m4a Resources/bell.wav Resources/bell.mp3 Resources/bell.aiff; do
  if [ -f "$sound" ]; then cp "$sound" "$APP/Contents/Resources/"; break; fi
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ThirdTimer</string>
    <key>CFBundleDisplayName</key><string>Third Timer</string>
    <key>CFBundleIdentifier</key><string>app.thirdtimer.ThirdTimer</string>
    <key>CFBundleExecutable</key><string>ThirdTimer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign for this Mac only (no Apple developer account needed).
codesign --force --sign - "$APP"
echo "Built $APP"
