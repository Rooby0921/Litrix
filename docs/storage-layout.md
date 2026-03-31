# Litrix 存储结构说明

本文档描述当前 Litrix 已实现的本地数据结构与磁盘布局，重点覆盖元数据、PDF、Note、图片附件以及兼容迁移规则。

## 1. 设计目标

当前存储层围绕这几个目标组织：

1. 元数据与附件分离，避免每次界面刷新都扫描整个附件目录。
2. 每篇文献保持独立目录，便于复制、导出、迁移与故障隔离。
3. 附件路径固定化，减少运行时兜底探测逻辑。
4. 对旧版本目录结构保持向后兼容，并在加载时做一次性修复。

## 2. 根路径

Litrix 当前使用两个根目录：

1. 应用支持目录
   默认路径：`~/Library/Application Support/Litrix`

2. 文献附件目录
   默认路径：`~/Litrix/Papers`
   实际以 `SettingsStore.resolvedPapersDirectoryURL` 为准，可由用户修改。

### 2.1 应用支持目录内容

`~/Library/Application Support/Litrix`

- `library.json`
  主元数据快照文件。
- `settings.json`
  应用设置。
- `metadata-prompts.txt`
  元数据提取提示模板。
- `Backups/`
  主元数据备份目录。
- `mcp/`
  MCP 相关配置输出目录。
- `PDFs/`
  旧版遗留目录，当前主要用于兼容历史数据。

## 3. 逻辑数据模型

### 3.1 LibrarySnapshot

主元数据文件 `library.json` 对应 `LibrarySnapshot`：

```swift
struct LibrarySnapshot: Codable {
    var papers: [Paper]
    var collections: [String]
    var tags: [String]
    var tagColorHexes: [String: String]
}
```

说明：

- `papers` 是文献主列表。
- `collections` 和 `tags` 是全局分类集合。
- `tagColorHexes` 是标签颜色映射。

### 3.2 Paper

每篇文献对应 `Paper` 结构，包含：

- 基础信息：`title`、`englishTitle`、`authors`、`authorsEnglish`、`year`、`source`、`doi`
- 评价与归类：`rating`、`collections`、`tags`、`paperType`、`category`
- 学术元数据：`abstractText`、`keywords`、`volume`、`issue`、`pages`
- 研究字段：`rqs`、`results`、`conclusion`、`samples`、`variables`、`methodology`、`theoreticalFoundation`、`limitations` 等
- 附件定位字段：`storageFolderName`、`storedPDFFileName`、`originalPDFFileName`、`preferredOpenPDFFileName`、`imageFileNames`
- 时间字段：`addedAtMilliseconds`、`importedAt`、`lastOpenedAt`、`lastEditedAtMilliseconds`
- 搜索辅助字段：`searchMetadata`
- 运行时 note 文本：`notes`

## 4. 物理目录结构

当前每篇带附件的文献采用“一个 UUID 目录”：

```text
Papers/
  <paper-storage-folder-uuid>/
    <stored-pdf-file-name>.pdf
    note.txt
    images/
      <image-file-name-1>.png
      <image-file-name-2>.jpg
```

### 4.1 PDF

- PDF 仍位于文献目录根部。
- 文件名由 `storedPDFFileName` 显式记录。
- `originalPDFFileName` 用于保留原始导入文件名语义。
- `preferredOpenPDFFileName` 用于多 PDF 场景下的优先打开文件。

### 4.2 Note

- Note 统一存放为固定文件名：`note.txt`
- 对于 `storageFolderName != nil` 的文献，`note.txt` 是 note 的磁盘真源。
- `library.json` 中这类文献的 `notes` 字段在持久化时会被清空，以减小主元数据体积并避免双写冗余。
- 对于没有附件目录的纯元数据文献，`notes` 仍保留在 `library.json` 中。

### 4.3 图片

- 图片统一存放在固定子目录：`images/`
- `imageFileNames` 保存的是图片文件名数组，不含目录前缀。
- 运行时路径解析规则为：
  1. 先查 `<paper-folder>/images/<fileName>`
  2. 兼容旧结构时，再查 `<paper-folder>/<fileName>`

## 5. 路径字段含义

### 5.1 `storageFolderName`

- 指向 `Papers/` 下的文献目录名。
- 推荐保持 UUID，不直接使用标题或作者名。
- 该字段是附件路径解析的根锚点。

### 5.2 `storedPDFFileName`

- 指向文献目录根部的实际 PDF 文件名。
- 热路径不再依赖目录扫描找 PDF；优先相信这个字段。

### 5.3 `originalPDFFileName`

- 记录原始导入文件名或历史文件名。
- 主要用于展示、兼容和迁移恢复。

### 5.4 `imageFileNames`

- 保存图片文件名数组。
- 逻辑上这些文件应位于 `images/` 子目录。

## 6. 运行时约束

当前实现遵守这些约束：

1. 热路径不再通过扫描文献目录来推断 PDF 路径。
2. 缺失的 PDF 名称只在加载修复阶段做一次兜底扫描。
3. Note 文件名固定为 `note.txt`，不再由作者与标题动态拼接。
4. 图片目录固定为 `images/`，不再默认散落在文献目录根部。
5. `library.json` 是主元数据索引，不再承担附件 note 正文的长期存储职责。

## 7. 加载与保存流程

### 7.1 加载

启动加载流程：

1. 读取 `library.json`
2. 对每篇文献执行兼容迁移与资产规范化
3. 从 `note.txt` 载入 note 正文到内存中的 `Paper.notes`
4. 修复旧版图片位置与旧 note 文件名
5. 必要时回写更新后的主元数据

### 7.2 保存

保存 `library.json` 时：

1. 构建 `LibrarySnapshot`
2. 对有附件目录的文献，把 `notes` 清空后再编码
3. 将快照写回 `library.json`
4. 周期性写入 `Backups/`

这样做的结果是：

- note 正文仍可在运行时正常使用
- 主元数据文件更轻
- 大量 note 编辑不会重复把正文同时写到 JSON 和 txt 两份

## 8. 向后兼容与迁移规则

当前实现会在加载时自动兼容旧数据：

### 8.1 旧 Note 文件

兼容以下旧格式：

- `Note.txt`
- 旧版按标题生成的 `*.txt`

迁移策略：

1. 若 `note.txt` 已存在，则优先使用它
2. 若只有旧 note 文件，则迁移为 `note.txt`
3. 若磁盘 note 缺失但内存 `notes` 不为空，则创建 `note.txt`

### 8.2 旧图片位置

兼容旧版图片直接放在文献目录根部的结构。

迁移策略：

1. 加载时发现根部图片文件
2. 自动移动到 `images/`
3. 更新 `imageFileNames`

### 8.3 旧 PDF 元数据缺失

如果 `storedPDFFileName` 或 `originalPDFFileName` 缺失或失效：

1. 先尝试已有显式字段
2. 再在文献目录中做一次兜底扫描
3. 将扫描结果回填到元数据字段

## 9. 性能收益点

这次结构调整主要优化了这些问题：

1. 降低了主元数据写入体积，因为 note 正文不再长期重复存到 `library.json`
2. 减少了运行时目录扫描，因为 PDF 路径优先走显式字段
3. 固定了 note 与图片的位置，避免每次都靠猜测或枚举目录恢复路径
4. 图片迁移到 `images/` 子目录后，文献目录根部结构更稳定，路径解析更简单
5. 导入 PDF 时改为直接 `copyItem`，减少整文件读入内存的开销

## 10. 目前未完成的部分

当前仍然保留了集中式 `library.json`，尚未迁移到 SQLite。

这意味着：

- 大量元数据修改仍然会重写整个主快照文件
- `searchMetadata` 仍作为冗余索引存放在快照中
- 更细粒度的增量写入和事务能力还没有引入

如果后续继续优化，下一步最合适的方向是：

1. 把 `library.json` 迁移到 SQLite
2. 让搜索索引与主元数据分层
3. 为 note 和附件增加更明确的版本或 manifest 信息
