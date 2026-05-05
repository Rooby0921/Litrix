# WPS（mac）桥接脚本

WPS for macOS 的“WPS 加载项”入口对 Office Web Add-in 兼容性有限，常见现象是“可用加载项”空白。

Litrix 在 mac 上提供桥接脚本方案：

1. 在 Litrix 中触发快速引用（默认 `left ⌘ + right ⌘`），结果会复制到剪贴板。
2. 回到 WPS 光标位置。
3. 运行以下脚本之一：

- `insert-citation-inline.command`：直接粘贴行内引用。
- `insert-citation-footnote.command`：先触发 `⌘⌥F` 再粘贴（适用于支持该快捷键的文档窗口）。

## 使用前准备

- 第一次运行时，macOS 可能要求为 Terminal 授予“辅助功能”权限。
- 若脚注快捷键在你的 WPS 版本不可用，请使用行内脚本。
