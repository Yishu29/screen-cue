#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$ROOT_DIR/ScreenCue"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="ScreenCue"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INSTALL_TARGET_SYSTEM="/Applications/$APP_NAME.app"
INSTALL_TARGET_USER="$HOME/Applications/$APP_NAME.app"
BUILD_MODE="${BUILD_MODE:-development}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
INSTALL_APP="${INSTALL_APP:-1}"
RESTART_APP="${RESTART_APP:-0}"
DESIGNATED_REQUIREMENT='designated => identifier "com.local.screencue"'

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
  echo "示例：BUILD_MODE=release SIGN_IDENTITY=\"Developer ID Application: Your Name (TEAMID)\" ./build_screencue.sh"
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

swiftc \
  "$APP_ROOT/Sources/main.swift" \
  "$APP_ROOT/Sources/AppBrand.swift" \
  "$APP_ROOT/Sources/AppDelegate.swift" \
  "$APP_ROOT/Sources/OverlayWindow.swift" \
  "$APP_ROOT/Sources/OverlayCameraView.swift" \
  "$APP_ROOT/Sources/TeleprompterWindow.swift" \
  "$APP_ROOT/Sources/TeleprompterView.swift" \
  "$APP_ROOT/Sources/LayoutState.swift" \
  "$APP_ROOT/Sources/MicrophoneSelection.swift" \
  "$APP_ROOT/Sources/RecordingLaunchPolicy.swift" \
  "$APP_ROOT/Sources/RecordingRegionWindow.swift" \
  "$APP_ROOT/Sources/RecordingDimOverlay.swift" \
  "$APP_ROOT/Sources/RegionPickerWindow.swift" \
  "$APP_ROOT/Sources/ScreenRecorder.swift" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ScreenCaptureKit \
  -o "$MACOS_DIR/$APP_NAME"

cp "$APP_ROOT/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$APP_ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

if [[ "$BUILD_MODE" == "release" ]]; then
  codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" -r="$DESIGNATED_REQUIREMENT" "$APP_BUNDLE"
else
  codesign --force --deep --sign - -r="$DESIGNATED_REQUIREMENT" "$APP_BUNDLE"
fi

if [[ "$INSTALL_APP" == "1" ]]; then
  if [[ -w "/Applications" ]]; then
    INSTALL_TARGET="$INSTALL_TARGET_SYSTEM"
  else
    mkdir -p "$HOME/Applications"
    INSTALL_TARGET="$INSTALL_TARGET_USER"
  fi
  rm -rf "$INSTALL_TARGET"
  cp -R "$APP_BUNDLE" "$INSTALL_TARGET"
  echo "Installed to: $INSTALL_TARGET"
fi

if [[ "$RESTART_APP" == "1" ]]; then
  pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
  if [[ "$INSTALL_APP" == "1" ]]; then
    open "$INSTALL_TARGET"
  else
    open "$APP_BUNDLE"
  fi
fi

echo "Build success: $APP_BUNDLE"
echo "Build mode: $BUILD_MODE"
if [[ "${INSTALL_TARGET:-}" != "" ]]; then
  echo "Run with: open \"$INSTALL_TARGET\""
else
  echo "Run with: open \"$APP_BUNDLE\""
fi
if [[ "$BUILD_MODE" == "development" ]]; then
  echo "Note: development mode uses ad hoc signing and is not suitable for external distribution."
fi
