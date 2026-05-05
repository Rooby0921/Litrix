# Safari 安装说明（macOS）

Litrix 的 Safari 插件通过 Apple 的 Safari Web Extension 转换器生成本机宿主 App。

## 推荐流程

1. 打开 Litrix。
2. 进入设置 > 引用 > 插件 > 网页插件。
3. 点击“检查 Safari”。
4. Litrix 会自动生成、命令行编译并打开 `Litrix Safari Importer`。
5. 在 Safari 设置 > 扩展 中启用 `Litrix Safari Importer`。

## 没有 Apple Developer Team ID 时

可以本机使用，但属于未签名/本机调试安装。若 Safari 扩展列表没有出现 Litrix：

1. 打开 Safari。
2. 在 Safari 设置 > 高级 中显示开发功能。
3. 在 Safari 菜单栏 > 开发 中启用“允许未签名扩展”。
4. 回到 Litrix 再点一次“检查 Safari”。

## 说明

- 日常使用不需要持续打开 Xcode。
- 安装器优先使用 `xcodebuild`，不打开 Xcode 界面。
- 如果命令行编译失败，安装器会打开生成的 Xcode 工程，此时再按 Xcode 的运行按钮即可。
- 生成文件位于 `~/Library/Application Support/Litrix/SafariWebImporter`。
