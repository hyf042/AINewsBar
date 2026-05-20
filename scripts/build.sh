#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/AINewsBar.app"
BINARY="$APP_BUNDLE/Contents/MacOS/AINewsBar"
ZIP_NAME="AINewsBar-${VERSION}.zip"
ZIP_PATH="$PROJECT_DIR/build/$ZIP_NAME"

cd "$PROJECT_DIR"

echo "==> Stopping existing instance..."
pkill -x AINewsBar 2>/dev/null || true
sleep 0.5

echo "==> Building (release)..."
swift build -c release

echo "==> Copying binary..."
cp ".build/release/AINewsBar" "$BINARY"

echo "==> Signing..."
codesign --sign - --force "$APP_BUNDLE"

echo "==> Packaging $ZIP_NAME..."
cd "$PROJECT_DIR/build"
rm -f "$ZIP_NAME"
zip -qr "$ZIP_NAME" AINewsBar.app
cd "$PROJECT_DIR"

echo ""
echo "Done: build/$ZIP_NAME"
echo "Run:  $BINARY &"
