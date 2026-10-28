<p align="center">
  <img src="docs/images/logo.png" width="112" alt="HaloDock 歪头屏 Logo" />
</p>

<h1 align="center">HaloDock</h1>

<p align="center">
  <strong>菜单栏里的轻量工具箱，你的 Mac 小助手。</strong><br />
  查看系统状态、找回刚复制的内容、完成常用操作，一个入口就够。
</p>

<p align="center">
  macOS 13+ · Apple Silicon · SwiftUI + AppKit · 中文界面
</p>

<p align="center">
  <a href="https://github.com/huangzhuangjia/halodock/releases/latest">下载最新版本</a> ·
  <a href="#界面预览">界面预览</a> ·
  <a href="#安装与更新">安装说明</a> ·
  <a href="https://github.com/huangzhuangjia/halodock/issues">反馈问题</a>
</p>

## 界面预览

<table>
  <tr>
    <th>菜单栏面板</th>
    <th>偏好设置</th>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/panel.png" width="390" alt="HaloDock 中文面板：系统状态、保持唤醒、截图、废纸篓和最近复制" /></td>
    <td align="center"><img src="docs/images/settings.png" width="460" alt="HaloDock 设置：开机启动、主题、强调色及面板显示选项" /></td>
  </tr>
</table>

界面图由当前 App 的 SwiftUI 视图渲染，状态数值来自本机；剪贴板为空状态，不包含私人内容。设置页面可向下滚动查看权限说明。

## 可以做什么

| 功能 | 使用方式 |
| --- | --- |
| 实时状态 | 电池、内存占用、网络连接、硬盘可用空间，每 2 秒刷新 |
| 保持唤醒 | 一键保持屏幕点亮，记住上次选择并在下次启动恢复 |
| 截取屏幕 | 选择区域后复制到剪贴板；界面提供系统截图快捷键说明 |
| 清空废纸篓 | 确认后交由 Finder 清空；缺少权限时引导至系统设置 |
| 专注模式 | 快速打开系统专注模式设置 |
| 最近复制 | 记录运行期间复制的文本和文件，点击即可重新复制 |
| 开机启动 | 默认开启，安装到“应用程序”后首次启动注册系统登录项 |
| 外观设置 | 跟随系统、浅色、深色；提供珊瑚橙、蓝色、绿色强调色 |

“歪头屏”是 HaloDock 的品牌形象，菜单栏、面板和设置页使用同一份矢量图形。

## 安装与更新

1. 前往 [GitHub Releases](https://github.com/huangzhuangjia/halodock/releases/latest)，下载 `HaloDock-<版本>-macos-arm64.dmg`。
2. 打开安装包，将 **HaloDock.app** 拖到右侧 **Applications**。
3. 从“应用程序”打开 HaloDock，点击菜单栏里的“歪头屏”图标。
4. 更新前先退出旧版，再用新版替换“应用程序”中的 HaloDock。

当前发布包适用于 **Apple Silicon Mac，macOS 13 及以上**。仓库为私有，下载需要登录有权限的 GitHub 账号。

<img src="docs/images/installer.png" width="680" alt="HaloDock DMG 实际安装窗口：暖白品牌背景、歪头屏图标与拖拽安装引导" />

当前版本使用 **ad-hoc 签名，尚未进行 Apple Developer ID 签名与公证**。如果 macOS 阻止打开，请查看“系统设置 → 隐私与安全性”中的对应提示。

每版安装包附带 `.sha256` 文件。将 DMG 和校验文件放到同一目录后，可以检查下载完整性：

```sh
shasum -a 256 -c HaloDock-0.1.3-macos-arm64.dmg.sha256
```

## 权限与数据

**清空废纸篓**需要允许 HaloDock 控制 Finder。首次确认清空时，系统会请求自动化授权；若已拒绝，可从 App 设置中的权限入口前往 **隐私与安全性 → 自动化 → HaloDock → Finder**。清空属于永久删除，操作前会再次确认。

**开机启动**使用 macOS 系统登录项。在“应用程序”中首次启动后注册；若系统要求批准，设置页提供登录项入口。开发目录运行时只保存偏好，不注册临时构建路径。

**剪贴板历史**仅保存在内存，退出后清空，不会发送到服务器：

- 最多保留 20 条，面板显示最近 3 条；重复内容移至最前。
- 支持文本和文件；一次复制多个文件时，目前只记录第一个。
- 暂不支持图片和超过 100 KB 的文本。
- 跳过带保密、临时或自动生成标记的内容；未带这些标记的敏感文本仍可能被记录。
- 只记录 HaloDock 启动后的新复制，不读取之前的历史。

**系统指标**来自本机。网络只表示系统路径连接状态，不代表互联网速度或可达性；内存占用由虚拟内存统计估算，不代表内存压力。读取失败会显示不可用。

## 本地开发

需要 Xcode 或对应的 Swift 工具链。

```sh
git clone https://github.com/huangzhuangjia/halodock.git
cd halodock
swift build
./Scripts/build-app.sh
open .build/HaloDock.app
```

生成 DMG：

```sh
DMG_PYTHON=python3.12 ./Scripts/build-dmg.sh
```

首次打包需要 Python 3.10+。脚本在 `.build/dmg-tools/` 中安装独立的 dmgbuild 1.6.7，不修改系统 Python。产物输出到 `dist/`，安装包作为 GitHub Release 附件管理，不提交到 Git。

| 目录 | 内容 |
| --- | --- |
| `Sources/HaloDock/` | 状态栏、SwiftUI 界面与本机能力 |
| `Resources/` | 应用元数据 |
| `Scripts/` | App、图标、DMG 与文档截图生成脚本 |
| `docs/images/` | README 品牌图与界面演示 |
| `Design/` | 图标方案与设计探索 |

遇到问题，可以在 [Issues](https://github.com/huangzhuangjia/halodock/issues) 中描述 macOS 版本、HaloDock 版本和复现步骤；截图前请隐藏私人内容。
