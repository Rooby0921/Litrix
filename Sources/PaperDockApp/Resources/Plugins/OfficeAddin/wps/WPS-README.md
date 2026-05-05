# WPS 安装说明

## Windows / Linux

1. 运行上一级目录中的 `start-local-server.command`。
2. 在 WPS 加载项或开发工具入口中侧载本目录的 `LitrixWPSManifest.xml`。
3. 功能区出现 `Litrix` 标签页后，点击 `引文格式` 或 `引用格式`。

## macOS

WPS（mac）的“WPS 加载项”入口对 Office Web Add-in 兼容性有限，常见现象是“可用加载项”空白。

请改用 Litrix 提供的 `Plugins/WPSMacBridge` 桥接脚本：

1. 在 Litrix 里复制快速引用。
2. 在 WPS 光标位置运行桥接脚本进行粘贴（行内/脚注）。
