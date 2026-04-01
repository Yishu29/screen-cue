# ScreenCue

[English](./README.en.md) | [中文](./README.zh-CN.md)

A lightweight macOS screen recording helper with camera overlay, teleprompter, region capture, and microphone selection.

## Repository Contents

- `ScreenCue/`: main app source code (Swift + AppKit + ScreenCaptureKit)
- `Tests/`: core logic tests
- `build_screencue.sh`: local build and install script
- `build_installer_dmg.sh`: DMG packaging script
- [ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg): installable beta package

## macOS Requirements

- Recommended: **macOS 14+ (Sonoma or newer)**
- Minimum suggested: **macOS 13+ (Ventura)**
- ScreenCaptureKit support is required for recording

## Install (Beta)

1. Open [ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg)
2. Drag `ScreenCue.app` into `Applications`
3. Launch the app from `Applications`

## If macOS blocks the app ("unverified developer")

1. Close the warning dialog
2. Open `System Settings -> Privacy & Security`
3. Find the blocked app notice near the bottom
4. Click `Open Anyway`
5. Launch the app again

## First-Run Permissions

Allow these permissions when prompted:

- Camera
- Microphone
- Screen & System Audio Recording

If recording does not work, check:

- `System Settings -> Privacy & Security -> Screen & System Audio Recording`
- Ensure permission is enabled for `ScreenCue`

## Feedback

If you hit any issue, please share:

- Screenshot of the error dialog
- Your macOS version
- Installer package name ([ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg))
