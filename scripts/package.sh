#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="番茄钟"
BUNDLE_NAME="TomatoTimer.app"
DIST="dist"

if [ ! -f Support/AppIcon.icns ]; then
  echo "生成 App 图标…"
  mkdir -p .build/icon .build/AppIcon.iconset
  swift scripts/make-icon.swift .build/icon/icon_1024.png
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" .build/icon/icon_1024.png \
      --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" .build/icon/icon_1024.png \
      --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns .build/AppIcon.iconset -o Support/AppIcon.icns
fi

echo "构建 Release…"
xcodegen generate
xcodebuild \
  -project TomatoTimer.xcodeproj \
  -scheme TomatoTimer \
  -configuration Release \
  -derivedDataPath .build \
  build

APP_PATH=".build/Build/Products/Release/$BUNDLE_NAME"

echo "校验签名…"
codesign --verify --deep --strict "$APP_PATH"

rm -rf "$DIST"
mkdir -p "$DIST/dmg-root"
cp -R "$APP_PATH" "$DIST/dmg-root/$APP_NAME.app"
ln -s /Applications "$DIST/dmg-root/Applications"

echo "生成 DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST/dmg-root" \
  -ov -format UDZO \
  "$DIST/$APP_NAME.dmg" >/dev/null

echo "生成 ZIP…"
ditto -c -k --keepParent "$DIST/dmg-root/$APP_NAME.app" "$DIST/$APP_NAME.zip"

echo
echo "完成："
echo "  $DIST/$APP_NAME.dmg"
echo "  $DIST/$APP_NAME.zip"
