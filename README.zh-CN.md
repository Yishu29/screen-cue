# ScreenCue

[English](./README.en.md) | [中文](./README.zh-CN.md)

一个用于 macOS 的轻量录屏辅助工具：支持摄像头悬浮窗、提词器、录屏选区与麦克风选择。

## 仓库内容

本仓库主要包含以下内容：

- `ScreenCue/`：主应用源码（Swift + AppKit + ScreenCaptureKit）
- `Tests/`：核心逻辑测试
- `build_screencue.sh`：本地构建并安装 App 的脚本
- `build_installer_dmg.sh`：生成安装包（DMG）的脚本
- [ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg)：可直接安装的内测包

## macOS 版本要求

- 建议系统：**macOS 14+（Sonoma 及以上）**
- 最低建议：**macOS 13+（Ventura）**
- 需要系统支持 ScreenCaptureKit（用于录屏）

## 如何安装（内测版）

1. 打开 DMG 安装包（[ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg)）
2. 把 App（`ScreenCue.app`）拖到 `Applications` 文件夹
3. 去 `Applications` 里找到 App 并打开

## 如果提示“无法验证开发者”或无法打开

1. 先关闭弹窗
2. 打开 `系统设置 -> 隐私与安全性`
3. 在页面下方找到被拦截的 App 提示
4. 点击 `仍要打开`
5. 再回到 `Applications` 重新打开 App

## 首次使用权限

首次使用时，系统可能请求以下权限，请选择允许：

- 摄像头
- 麦克风
- 屏幕与系统录制

如果录屏功能不可用，优先检查：

- `系统设置 -> 隐私与安全性 -> 屏幕与系统录制`
- 确认已为 `ScreenCue` 打开权限

## 问题反馈

如果遇到任何问题，请直接发送：

- 报错弹窗截图
- 系统版本（macOS 版本号）
- 你使用的安装包名称（[ScreenCue.dmg](https://github.com/Yishu29/screen-cue/releases/latest/download/ScreenCue.dmg)）
