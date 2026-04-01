# ScreenCue

一个用于 macOS 的轻量录屏辅助工具：支持摄像头悬浮窗、提词器、录屏选区与麦克风选择。  
This is a lightweight macOS screen recording helper with camera overlay, teleprompter, region capture, and microphone selection.

---

## 中文说明（主）

### 仓库内容

本仓库主要包含以下内容：

- `ScreenCue/`：主应用源码（Swift + AppKit + ScreenCaptureKit）
- `Tests/`：核心逻辑测试
- `build_screencue.sh`：本地构建并安装 App 的脚本
- `build_installer_dmg.sh`：生成安装包（DMG）的脚本
- `release/ScreenCue.dmg`：可直接安装的内测包

### macOS 版本要求

- 建议系统：**macOS 14+（Sonoma 及以上）**
- 最低建议：**macOS 13+（Ventura）**
- 需要系统支持 ScreenCaptureKit（用于录屏）

### 如何安装（内测版）

你可以按下面步骤安装：

1. 打开 DMG 安装包（`ScreenCue.dmg`）
2. 把 App（`ScreenCue.app`）拖到 `Applications` 文件夹
3. 去 `Applications` 里找到 App 并打开

### 如果提示“无法验证开发者”或无法打开

1. 先关闭弹窗
2. 打开 `系统设置 -> 隐私与安全性`
3. 在页面下方找到被拦截的 App 提示
4. 点击 `仍要打开`
5. 再回到 `Applications` 重新打开 App

### 首次使用权限

首次使用时，系统可能请求以下权限，请选择允许：

- 摄像头
- 麦克风
- 屏幕与系统录制

如果录屏功能不可用，优先检查：

- `系统设置 -> 隐私与安全性 -> 屏幕与系统录制`
- 确认已为 `ScreenCue` 打开权限

### 问题反馈

如果遇到任何问题，请直接发送：

- 报错弹窗截图
- 系统版本（macOS 版本号）
- 你使用的安装包名称（`ScreenCue.dmg`）

---

## English (Quick Guide)

### What is in this repository

- `ScreenCue/`: main app source code (Swift + AppKit + ScreenCaptureKit)
- `Tests/`: core logic tests
- `build_screencue.sh`: build/install script for local development
- `build_installer_dmg.sh`: DMG packaging script
- `release/ScreenCue.dmg`: installable beta package

### macOS requirement

- Recommended: **macOS 14+ (Sonoma or newer)**
- Minimum suggested: **macOS 13+ (Ventura)**
- ScreenCaptureKit support is required for recording

### Install (beta)

1. Open the DMG file
2. Drag `ScreenCue.app` into `Applications`
3. Open the app from `Applications`

### If macOS blocks the app (“unverified developer”)

1. Close the warning dialog
2. Go to `System Settings -> Privacy & Security`
3. Find the blocked app notice near the bottom
4. Click `Open Anyway`
5. Launch the app again

### First-run permissions

Please allow when prompted:

- Camera
- Microphone
- Screen & System Audio Recording

If recording still does not work, check:

- `System Settings -> Privacy & Security -> Screen & System Audio Recording`
- Make sure permission is enabled for this app.
