#!/usr/bin/env bash
set -euo pipefail

VERSION="2.0.1"
BUILD_NUMBER="2"                 # CFBundleVersion 单调递增，每次发版 +1
APP_NAME="AINewsBar"             # binary 文件名 / Bundle 路径（与 Package.swift target 一致，不改）
DISPLAY_NAME="资讯助手"            # 用户可见名（CFBundleName + CFBundleDisplayName 共用）
BUNDLE_ID="com.ainewsbar.app"    # Bundle ID 保留 — 改了 UserDefaults domain 会变导致 API Key 丢失
MIN_MACOS="14.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
DMG_NAME="$APP_NAME-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/build/$DMG_NAME"
DMG_STAGE="$PROJECT_DIR/build/dmg-stage"
DMG_VOLUME="$DISPLAY_NAME ${VERSION}"

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
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
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
# ad-hoc 签名只在本机 + 无 quarantine 时可信。GitHub release 下载后必然带
# `com.apple.quarantine` xattr，Gatekeeper 拒绝运行（"已损坏"对话框）。
# 朋友首次安装需要按 README "朋友安装指南"右键打开授权一次。
# 长期方案是 Apple Developer ID + Notarization（$99/年），见 README 末段。
codesign --sign - --force --deep "$APP_BUNDLE"

echo "==> Packaging DMG $DMG_NAME..."
# DMG vs ZIP：DMG 内 .app + Applications 软链让朋友"拖进 Applications"安装，
# 比 zip 散落 .app 体感更像"正经安装包"。DMG 文件本身仍会带 quarantine xattr，
# 但里面 .app 一旦拖出来用户已经走过 Finder 安装动作，比直接双击解压更稳健。
# -fs HFS+ 必需，否则 Applications 软链会被打平成空文件夹。
rm -rf "$DMG_STAGE"
rm -f "$DMG_PATH"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
    -volname "$DMG_VOLUME" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" > /dev/null

rm -rf "$DMG_STAGE"

echo ""
echo "Done: build/$DMG_NAME"
echo "Run:  $BINARY &"
echo ""
echo "分发: 把 $DMG_NAME 上传 GitHub release；朋友安装指南见 README。"
