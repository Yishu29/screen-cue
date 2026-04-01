#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/build/ScreenCue.app"
RELEASE_DIR="$ROOT_DIR/release"
STAGE_DIR="$ROOT_DIR/.dmg-stage"
RW_DMG="$RELEASE_DIR/ScreenCue-rw.dmg"
FINAL_DMG="$RELEASE_DIR/ScreenCue.dmg"
VOLUME_NAME="ScreenCue Installer"
BUILD_MODE="${BUILD_MODE:-development}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"

case "$BUILD_MODE" in
  development|release)
    ;;
  *)
    echo "不支持的 BUILD_MODE：$BUILD_MODE"
    echo "可选值：development、release"
    exit 1
    ;;
esac

if [[ "$BUILD_MODE" == "release" && -z "$SIGN_IDENTITY" ]]; then
  echo "发布模式需要提供 SIGN_IDENTITY（Developer ID Application）。"
  echo "示例：BUILD_MODE=release SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./build_installer_dmg.sh"
  exit 1
fi

if [[ "$NOTARIZE" == "1" && "$BUILD_MODE" != "release" ]]; then
  echo "NOTARIZE=1 仅支持在 BUILD_MODE=release 下使用。"
  exit 1
fi

submit_for_notarization() {
  local target_path="$1"

  if [[ -n "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    xcrun notarytool submit "$target_path" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    return
  fi

  if [[ -n "$APPLE_ID" && -n "$APPLE_TEAM_ID" && -n "$APP_SPECIFIC_PASSWORD" ]]; then
    xcrun notarytool submit "$target_path" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APP_SPECIFIC_PASSWORD" \
      --wait
    return
  fi

  echo "缺少公证凭据。"
  echo "请提供以下任一方式："
  echo "1) NOTARY_KEYCHAIN_PROFILE=<profile>"
  echo "2) APPLE_ID / APPLE_TEAM_ID / APP_SPECIFIC_PASSWORD"
  exit 1
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到 App：$APP_PATH"
  echo "请先运行 ./build_screencue.sh"
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$RELEASE_DIR"
rm -f "$RW_DMG" "$FINAL_DMG"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG" -nobrowse -readwrite)"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $3; exit}')"

if [[ -z "$MOUNT_POINT" ]]; then
  echo "挂载 DMG 失败"
  exit 1
fi

osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 660, 420}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "ScreenCue.app" of container window to {160, 150}
    set position of item "Applications" of container window to {430, 150}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

hdiutil detach "$MOUNT_POINT" >/dev/null

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

if [[ "$BUILD_MODE" == "release" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$FINAL_DMG"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  submit_for_notarization "$FINAL_DMG"
  xcrun stapler staple "$FINAL_DMG"
fi

rm -f "$RW_DMG"
rm -rf "$STAGE_DIR"

echo "Installer ready: $FINAL_DMG"
echo "Build mode: $BUILD_MODE"
if [[ "$BUILD_MODE" == "development" ]]; then
  echo "Note: development-mode DMG is not suitable for external distribution."
fi
