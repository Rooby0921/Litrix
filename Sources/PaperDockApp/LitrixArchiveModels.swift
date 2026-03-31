import Foundation

struct LitrixArchiveManifest: Codable {
    var formatIdentifier: String
    var formatVersion: Int
    var exportedAt: Date
    var library: LibrarySnapshot
    var settings: AppSettingsSnapshot?
    var metadataPromptDocument: String?

    init(
        formatIdentifier: String = "litrix-archive",
        formatVersion: Int = 1,
        exportedAt: Date = .now,
        library: LibrarySnapshot,
        settings: AppSettingsSnapshot?,
        metadataPromptDocument: String?
    ) {
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.library = library
        self.settings = settings
        self.metadataPromptDocument = metadataPromptDocument
    }
}

struct LitrixImportSelection: Equatable {
    var includeSettings = true
    var includePapers = true
    var includeNotes = true
    var includeAttachments = true

    static let all = LitrixImportSelection()
}

enum LitrixImportSelectionItem: CaseIterable, Identifiable {
    case settings
    case papers
    case notes
    case attachments

    var id: String {
        switch self {
        case .settings:
            return "settings"
        case .papers:
            return "papers"
        case .notes:
            return "notes"
        case .attachments:
            return "attachments"
        }
    }

    var title: String {
        switch self {
        case .settings:
            return "设置"
        case .papers:
            return "文献"
        case .notes:
            return "笔记"
        case .attachments:
            return "附件（PDF/图片）"
        }
    }
}

enum LitrixDuplicateResolution: String, CaseIterable {
    case overwrite
    case skip
    case rename

    var title: String {
        switch self {
        case .overwrite:
            return "覆盖"
        case .skip:
            return "跳过"
        case .rename:
            return "重命名（自动追加 (2)）"
        }
    }
}

enum LitrixDuplicateReason: String {
    case doi
    case title
    case doiAndTitle

    var descriptionText: String {
        switch self {
        case .doi:
            return "DOI 重复"
        case .title:
            return "标题重复"
        case .doiAndTitle:
            return "DOI 和标题均重复"
        }
    }
}

struct LitrixDuplicateCandidate {
    var existingPaper: Paper
    var incomingPaper: Paper
    var reason: LitrixDuplicateReason
}

struct LitrixImportReport {
    var added = 0
    var overwritten = 0
    var skipped = 0
    var renamed = 0
    var duplicateConflicts = 0
    var orphanCreated = 0
    var failedTitles: [String] = []

    var summaryText: String {
        var lines: [String] = []
        lines.append("导入完成")
        lines.append("新增：\(added)")
        lines.append("覆盖：\(overwritten)")
        lines.append("跳过：\(skipped)")
        lines.append("重命名导入：\(renamed)")
        lines.append("重复冲突：\(duplicateConflicts)")
        lines.append("因缺失目标而新建文献：\(orphanCreated)")
        if !failedTitles.isEmpty {
            let preview = failedTitles.prefix(6).joined(separator: "、")
            let suffix = failedTitles.count > 6 ? "…" : ""
            lines.append("失败：\(preview)\(suffix)")
        }
        return lines.joined(separator: "\n")
    }
}

enum LitrixArchiveError: LocalizedError {
    case invalidArchive
    case invalidManifest
    case unsupportedFormat
    case unsupportedVersion(Int)
    case packFailed(String)
    case unpackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "无效的 Litrix 导入文件。"
        case .invalidManifest:
            return "导入文件缺少 manifest。"
        case .unsupportedFormat:
            return "文件格式不受支持。"
        case .unsupportedVersion(let version):
            return "导入文件版本不受支持（v\(version)）。"
        case .packFailed(let message):
            return "打包失败：\(message)"
        case .unpackFailed(let message):
            return "解包失败：\(message)"
        }
    }
}
