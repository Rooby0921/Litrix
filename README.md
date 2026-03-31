[English](./README.en.md) | 简体中文

# Litrix

Litrix 是一个基于 SwiftUI 构建的原生 macOS 文献管理工具，用来导入 PDF / BibTeX / DOI、整理元数据、记录笔记，并将结果导出到写作或分析流程中。

它的目标不是做一个臃肿的一体化平台，而是提供一个轻量、本地优先、对 PDF 友好的研究工作台。

## 项目用途

- 管理论文 PDF 与元数据
- 通过文件名、DOI、Crossref 和 AI 模型补全文献信息
- 用分类、标签、评分、笔记整理阅读过程
- 导出 BibTeX、Markdown 详情和附件

## 当前功能

- 原生 macOS 三栏界面
- PDF 导入，并将附件整理到本地 Papers 目录
- BibTeX 导入
- DOI 导入，基于 Crossref 拉取元数据
- 基于 PDF 文本的 AI 元数据增强
- 支持 SiliconFlow 和阿里云百炼接口
- 分类、标签、评分、图片附件、纯文本笔记
- Quick Look 预览、默认应用打开 PDF、在 Finder 中定位
- 搜索与高级搜索
- BibTeX 导出、Markdown 详情导出、附件批量导出
- `library.json` 自动保存和历史备份

## 系统要求

- macOS 14 或更高版本
- Xcode 26.3+ 或 Swift 6.2+
- 如需 AI 元数据增强，需要在应用设置中填写 API Key

本仓库当前在本地环境中已通过 `Swift 6.2.4` 和 `Xcode 26.3` 检查。

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/<your-name>/<your-repo>.git
cd <your-repo>
```

### 2. 编译和运行

```bash
swift build
swift run Litrix
```

也可以直接用 Xcode 打开这个 Swift Package 后运行。

## 打包应用

项目已经包含 macOS 应用和 DMG 打包脚本：

```bash
chmod +x publish.sh build_dmg.sh
./publish.sh
```

如果本机已安装 `create-dmg`，脚本会额外生成 `Litrix-Installer.dmg`。

## 数据存储

- 应用设置与库文件：`~/Library/Application Support/Litrix/`
- 默认论文目录：`~/Litrix/Papers/`
- 备份目录：`~/Library/Application Support/Litrix/Backups/`

说明：论文目录可以在应用设置里修改。

## 截图预留

你可以把截图放到 `docs/images/` 目录，然后在 README 中加入类似下面的内容：

```md
![主界面](docs/images/main-window.png)
![元数据面板](docs/images/metadata-panel.png)
```

## 仓库说明

- `Sources/PaperDockApp/`：主应用源码
- `Package.swift`：Swift Package 配置
- `publish.sh` / `build_dmg.sh`：本地打包脚本
- `ApiCallTest/`：接口测试脚本

## 说明

- 这个仓库默认不提交 `.app`、`.dmg`、构建缓存和本地测试论文 PDF。
- 如果你准备公开发布，请确认示例论文、截图和图标都具备可公开分发权限。
