#!/bin/zsh
# 构建 OmniView Release 并打包为 DMG
# 用法: ./scripts/build_dmg.sh [输出路径]
# 默认仅打包 arm64；如需其他架构: ARCH=x86_64 ./scripts/build_dmg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 目标架构，默认 arm64
TARGET_ARCH=${ARCH:-arm64}

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" OmniView/Info.plist 2>/dev/null || echo "0.2.1")
# Info.plist 中是 $(MARKETING_VERSION)，解析不到时用 project.yml 中的版本
if [[ "$VERSION" == *'$('* ]]; then
    VERSION=$(grep -E 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*: *"([^"]+)".*/\1/')
fi
OUTPUT_PATH=${1:-"$ROOT_DIR/build/OmniView-$VERSION-$TARGET_ARCH.dmg"}
STAGING_DIR="$ROOT_DIR/build/dmg-root"

echo "==> 1/3 构建 Release 版本 ($VERSION, 架构: $TARGET_ARCH)"
xcodebuild -project OmniView.xcodeproj -scheme OmniView \
    -configuration Release -derivedDataPath "build/Release-$TARGET_ARCH" \
    build ARCHS="$TARGET_ARCH" ONLY_ACTIVE_ARCH=YES >/dev/null

APP_PATH="$ROOT_DIR/build/Release-$TARGET_ARCH/Build/Products/Release/OmniView.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "错误：未找到构建产物 $APP_PATH" >&2
    exit 1
fi

echo "==> 2/3 整理 DMG 内容"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "${OUTPUT_PATH:h}"
ditto "$APP_PATH" "$STAGING_DIR/OmniView.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> 3/3 生成 DMG"
rm -f "$OUTPUT_PATH"
hdiutil create \
    -volname "OmniView" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH"

rm -rf "$STAGING_DIR"
echo ""
echo "✅ DMG 已生成: $OUTPUT_PATH"
