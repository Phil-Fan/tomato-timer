#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="番茄钟"
BUNDLE_NAME="TomatoTimer.app"
# GitHub Release 的资产名必须是 ASCII，否则会被上传成 default.dmg / default.zip。
ARTIFACT_NAME="TomatoTimer"
DIST="dist"

# 本机直接运行时不设这些变量：走 ad-hoc 签名，和以前一样只适合自己用。
# CI 会把它们注入进来做 Developer ID 签名 + 公证。
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

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

echo "生成 Xcode 工程…"
xcodegen generate

# Info.plist 由 xcodegen 按 project.yml 重写，版本号要在生成之后再覆盖。
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Support/Info.plist
fi
if [ -n "$BUILD_NUMBER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Support/Info.plist
fi

BUILD_ARGS=(
  -project TomatoTimer.xcodeproj
  -scheme TomatoTimer
  -configuration Release
  -derivedDataPath .build
)

# 交给外部签名时先产出未签名包，最后统一 codesign，避免 Xcode 用错身份。
if [ -n "$SIGN_IDENTITY" ]; then
  BUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO)
fi

echo "构建 Release…"
xcodebuild "${BUILD_ARGS[@]}" build

APP_PATH=".build/Build/Products/Release/$BUNDLE_NAME"

if [ -n "$SIGN_IDENTITY" ]; then
  echo "使用 Developer ID 签名：$SIGN_IDENTITY"
  # Hardened Runtime + 安全时间戳是公证的硬性要求。
  # 日历权限需要 personal-information.calendars entitlement，否则 TCC 会静默拒绝授权。
  codesign --force --options runtime --timestamp \
    --entitlements Support/TomatoTimer.entitlements \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

echo "校验签名…"
codesign --verify --deep --strict "$APP_PATH"

# 公证凭据：CI 用 App Store Connect API Key；本地可以用 notarytool 的 keychain profile。
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
HAS_NOTARY_CREDS=0
if [ -n "$NOTARY_PROFILE" ] || [ -n "$API_KEY_PATH" ]; then
  HAS_NOTARY_CREDS=1
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  HAS_NOTARY_CREDS=1
fi

if [ "$HAS_NOTARY_CREDS" = "1" ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "错误：配置了公证凭据，但没有 APPLE_SIGNING_IDENTITY。" >&2
  echo "     未签名的包无法公证，请设置 Developer ID 证书后再试。" >&2
  exit 1
fi

notarize() {
  local file="$1"

  if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "$API_KEY_PATH" ]; then
    xcrun notarytool submit "$file" \
      --key "$API_KEY_PATH" \
      --key-id "${APPLE_API_KEY:?APPLE_API_KEY missing}" \
      --issuer "${APPLE_API_ISSUER:?APPLE_API_ISSUER missing}" \
      --wait
  else
    xcrun notarytool submit "$file" \
      --apple-id "${APPLE_ID:?}" \
      --password "${APPLE_PASSWORD:?}" \
      --team-id "${APPLE_TEAM_ID:?}" \
      --wait
  fi
}

rm -rf "$DIST"
mkdir -p "$DIST"

if [ "$HAS_NOTARY_CREDS" = "1" ]; then
  echo "公证 App…"
  # notarytool 只接受 zip/dmg/pkg 等容器，先打包 App 再提交。
  ditto -c -k --keepParent "$APP_PATH" "$DIST/notarize.zip"
  notarize "$DIST/notarize.zip"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$DIST/notarize.zip"
else
  echo "未配置公证凭据，跳过 notarize（ad-hoc 包只适合本机使用）。"
fi

mkdir -p "$DIST/dmg-root"
# 公证后 ticket 已经写进 bundle，必须在 staple 之后再复制进 DMG。
cp -R "$APP_PATH" "$DIST/dmg-root/$APP_NAME.app"
ln -s /Applications "$DIST/dmg-root/Applications"

echo "生成 DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST/dmg-root" \
  -ov -format UDZO \
  "$DIST/$ARTIFACT_NAME.dmg" >/dev/null

if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$ARTIFACT_NAME.dmg"
fi

if [ "$HAS_NOTARY_CREDS" = "1" ]; then
  echo "公证 DMG…"
  notarize "$DIST/$ARTIFACT_NAME.dmg"
  xcrun stapler staple "$DIST/$ARTIFACT_NAME.dmg"
  xcrun stapler validate "$DIST/$ARTIFACT_NAME.dmg"
fi

echo "生成 ZIP…"
ditto -c -k --keepParent "$DIST/dmg-root/$APP_NAME.app" "$DIST/$ARTIFACT_NAME.zip"

echo "生成 SHA256…"
(
  cd "$DIST"
  shasum -a 256 "$ARTIFACT_NAME.dmg" "$ARTIFACT_NAME.zip" > SHA256SUMS.txt
)

echo
echo "完成："
echo "  $DIST/$ARTIFACT_NAME.dmg"
echo "  $DIST/$ARTIFACT_NAME.zip"
echo "  $DIST/SHA256SUMS.txt"
