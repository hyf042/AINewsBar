#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
APP_NAME="AINewsBar"
DISPLAY_NAME="AI NewsBar"
BUNDLE_ID="com.ainewsbar.app"
MIN_MACOS="14.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
ZIP_NAME="$APP_NAME-${VERSION}.zip"

cd "$PROJECT_DIR"

echo "==> Stopping existing instance..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "==> Building (release)..."
swift build -c release

echo "==> Creating bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "==> Writing Info.plist..."
cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "==> Copying binary..."
cp ".build/release/$APP_NAME" "$BINARY"
chmod +x "$BINARY"

echo "==> Signing (ad-hoc)..."
codesign --sign - --force --deep "$APP_BUNDLE"

echo "==> Packaging $ZIP_NAME..."
cd "$PROJECT_DIR/build"
rm -f "$ZIP_NAME"
zip -qr "$ZIP_NAME" "$APP_NAME.app"
cd "$PROJECT_DIR"

echo ""
echo "Done: build/$ZIP_NAME"
echo "Run:  $BINARY &"
