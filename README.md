# Mini Clipboard（macOS）

[English](README.en.md) | [中文](README.md)

轻量、好看的 macOS 剪贴板管理器：采集历史、时间线浏览、收藏分组、直接粘贴、快速粘贴、即时搜索等能力，帮助你更快地跨应用粘贴内容。

## 功能特性
- 历史采集：自动捕获文本、链接、图片、文件、颜色等类型
- 时间线浏览：横向列表与网格两种布局，可快速预览与重命名
- 收藏分组：Pinboards 创建/重命名/颜色标记，历史与收藏独立
- 直接粘贴：双击快速复制，写入系统剪贴板，支持纯文本粘贴
- 搜索与过滤：关键词 + 类型/来源应用过滤，输入即搜
- 设置与快捷键：历史保留周期、布局切换、快捷键映射

## 按键
- 面板：`⇧+⌘+P`（可设置修改）
- 直接粘贴：双击或回车键
- 快速预览：空格键
- 移动：方向键
- 搜索：任意键

## 界面预览
![列表布局](docs/image/list_mode.png)
![演示](docs/video/demo2.mp4)

## 环境要求
- macOS 12+（Apple Silicon 原生）
- Xcode 15+，Swift 5.9+

## 快速开始
### 使用 Xcode
- 打开 `MiniClipboard.xcodeproj`，选择 `mini-clipboard` Scheme，直接运行。

### 使用 Makefile
- 构建 Debug：
  - `make build`
- 生成可分发的 `.app`：
  - `make app` → 输出到 `dist/Mini Clipboard.app`
- 生成未签名 DMG：
  - `make dmg-unsigned` → 输出到 `dist/Mini-Clipboard.dmg`
- 全流程签名与公证（需开发者证书/账号）：
  - 配置 `DEVELOPER_ID`、`TEAM_ID`、`APPLE_ID`、`APP_PASSWORD` 或 `NOTARY_PROFILE`
  - `make package-signed`
- 清理：
  - `make clean`

### 应用图标（可选）
- 在 `public/` 放置源图 `logo.png` 后可一键生成 iconset 与 `logo.icns`：
  - `make icon`
- 若系统安装了 ImageMagick，将自动生成圆角矩形；否则使用方形。

## 权限与隐私
- 直接粘贴和顺序粘贴栈需要启用“辅助功能”权限。首次运行会弹窗引导打开系统设置。
- 历史保留期默认 30 天，可在设置中调整；到期自动清理未收藏的历史。

## 默认快捷键（可在设置中修改）
- 面板：`⇧+⌘+P`

## 目录结构
- `App/`：应用入口、委托与面板窗口控制
- `Services/`：剪贴板监听、快捷键、粘贴、搜索、隐私规则
- `Storage/`：历史索引与设置持久化
- `UI/`：面板根视图、历史时间线、设置页与控件
- `Models/`：数据模型与枚举
- `dist/`：构建产物（`.app` 与 `.dmg`）
- `public/`：应用图标资源
- `docs/`：需求与技术设计文档

## 开发者提示
- 本地数据目录：`~/Library/Application Support/MiniClipboard/`（索引与持久内容）。
- 重要模块：
  - 剪贴板监听（`Services/ClipboardMonitor.swift`）
  - 直接/栈式粘贴（`Services/PasteService.swift`）
  - 快捷键注册（`Services/HotkeyService.swift`）
  - 历史索引与清理（`Storage/IndexStore.swift`）
  - 时间线 UI（`UI/HistoryTimelineView.swift`）

## 许可协议
- 开源协议：Apache License 2.0（见 `LICENSE`）。
