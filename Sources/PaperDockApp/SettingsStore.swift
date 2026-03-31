import AppKit
import Foundation

enum CitationPreset: String, CaseIterable, Codable, Identifiable {
    case apa7 = "apa-7"
    case gbt7714 = "gb-t-7714"
    case mla9 = "mla-9"
    case chicago17 = "chicago-17"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apa7:
            return "APA 7"
        case .gbt7714:
            return "GB/T 7714"
        case .mla9:
            return "MLA 9"
        case .chicago17:
            return "Chicago 17"
        case .custom:
            return "Custom"
        }
    }
}

struct CitationTemplatePair {
    var inText: String
    var reference: String
}

struct BibTeXExportFieldOptions: Codable, Equatable {
    var title = true
    var author = true
    var year = true
    var journal = true
    var doi = true
    var volume = true
    var number = true
    var pages = true
    var abstract = true
}

enum MetadataThinkingMode: String, CaseIterable, Codable, Identifiable {
    case nonThinking
    case thinking

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nonThinking:
            return "Non-Thinking"
        case .thinking:
            return "Thinking"
        }
    }
}

enum PDF2ZHEnvironmentKind: String, CaseIterable, Codable, Identifiable {
    case base
    case conda
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .base:
            return "Base"
        case .conda:
            return "Conda Env"
        case .custom:
            return "Other"
        }
    }
}

enum MetadataAPIProvider: String, CaseIterable, Codable, Identifiable {
    case siliconFlow
    case aliyunDashScope

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .siliconFlow:
            return "硅基流动"
        case .aliyunDashScope:
            return "阿里云百炼"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .siliconFlow:
            return "https://api.siliconflow.cn/v1/chat/completions"
        case .aliyunDashScope:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .siliconFlow:
            return "Qwen/Qwen3.5-27B"
        case .aliyunDashScope:
            return "qwen3.5-plus"
        }
    }
}

enum MCPClientType: String, CaseIterable, Codable, Identifiable {
    case codexCLI
    case claudeCode
    case claudeDesktop
    case clineVSCode
    case continueDev
    case cursor
    case cherryStudio
    case geminiCLI
    case chatbox
    case traeAI
    case qwenCode
    case customHTTP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codexCLI: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .clineVSCode: return "Cline (VS Code)"
        case .continueDev: return "Continue.dev"
        case .cursor: return "Cursor"
        case .cherryStudio: return "Cherry Studio"
        case .geminiCLI: return "Gemini CLI"
        case .chatbox: return "Chatbox"
        case .traeAI: return "Trae AI"
        case .qwenCode: return "Qwen Code"
        case .customHTTP: return "自定义 HTTP 客户端"
        }
    }

    var documentationTitle: String {
        switch self {
        case .codexCLI: return "Codex CLI MCP 配置指南"
        case .claudeCode: return "Claude Code MCP 配置指南"
        case .claudeDesktop: return "Claude Desktop MCP 配置指南"
        case .clineVSCode: return "Cline (VS Code) MCP 配置指南"
        case .continueDev: return "Continue.dev MCP 配置指南"
        case .cursor: return "Cursor MCP 配置指南"
        case .cherryStudio: return "Cherry Studio MCP 配置指南"
        case .geminiCLI: return "Gemini CLI MCP 配置指南"
        case .chatbox: return "Chatbox MCP 配置指南"
        case .traeAI: return "Trae AI MCP 配置指南"
        case .qwenCode: return "Qwen Code MCP 配置指南"
        case .customHTTP: return "自定义 HTTP MCP 配置指南"
        }
    }
}

enum TableRowHeightPreset: String, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high
    case max

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            return "Low (1x)"
        case .medium:
            return "Medium (3x)"
        case .high:
            return "High (6x)"
        case .max:
            return "Max (9x)"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .low:
            return 1
        case .medium:
            return 3
        case .high:
            return 6
        case .max:
            return 9
        }
    }
}

enum RecentReadingRange: String, CaseIterable, Codable, Identifiable {
    case oneDay
    case twoDays
    case oneWeek
    case oneMonth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneDay:
            return "1 Day"
        case .twoDays:
            return "2 Days"
        case .oneWeek:
            return "1 Week"
        case .oneMonth:
            return "1 Month"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .oneDay:
            return 24 * 60 * 60
        case .twoDays:
            return 2 * 24 * 60 * 60
        case .oneWeek:
            return 7 * 24 * 60 * 60
        case .oneMonth:
            return 30 * 24 * 60 * 60
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum ZombiePaperThreshold: String, CaseIterable, Codable, Identifiable {
    case threeDays
    case oneWeek
    case twoWeeks
    case threeWeeks
    case oneMonth
    case twoMonths
    case threeMonths
    case fourMonths
    case fiveMonths
    case sixMonths
    case sevenMonths
    case eightMonths
    case nineMonths
    case tenMonths
    case elevenMonths
    case twelveMonthsOrMore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeDays: return "3 Days"
        case .oneWeek: return "1 Week"
        case .twoWeeks: return "2 Weeks"
        case .threeWeeks: return "3 Weeks"
        case .oneMonth: return "1 Month"
        case .twoMonths: return "2 Months"
        case .threeMonths: return "3 Months"
        case .fourMonths: return "4 Months"
        case .fiveMonths: return "5 Months"
        case .sixMonths: return "6 Months"
        case .sevenMonths: return "7 Months"
        case .eightMonths: return "8 Months"
        case .nineMonths: return "9 Months"
        case .tenMonths: return "10 Months"
        case .elevenMonths: return "11 Months"
        case .twelveMonthsOrMore: return "12+ Months"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .threeDays: return 3 * 24 * 60 * 60
        case .oneWeek: return 7 * 24 * 60 * 60
        case .twoWeeks: return 14 * 24 * 60 * 60
        case .threeWeeks: return 21 * 24 * 60 * 60
        case .oneMonth: return 30 * 24 * 60 * 60
        case .twoMonths: return 60 * 24 * 60 * 60
        case .threeMonths: return 90 * 24 * 60 * 60
        case .fourMonths: return 120 * 24 * 60 * 60
        case .fiveMonths: return 150 * 24 * 60 * 60
        case .sixMonths: return 180 * 24 * 60 * 60
        case .sevenMonths: return 210 * 24 * 60 * 60
        case .eightMonths: return 240 * 24 * 60 * 60
        case .nineMonths: return 270 * 24 * 60 * 60
        case .tenMonths: return 300 * 24 * 60 * 60
        case .elevenMonths: return 330 * 24 * 60 * 60
        case .twelveMonthsOrMore: return 365 * 24 * 60 * 60
        }
    }

    static var sliderOrdered: [ZombiePaperThreshold] {
        [
            .threeDays,
            .oneWeek,
            .twoWeeks,
            .threeWeeks,
            .oneMonth,
            .twoMonths,
            .threeMonths,
            .fourMonths,
            .fiveMonths,
            .sixMonths,
            .sevenMonths,
            .eightMonths,
            .nineMonths,
            .tenMonths,
            .elevenMonths,
            .twelveMonthsOrMore
        ]
    }
}

struct PaperTableColumnVisibility: Codable, Equatable {
    var title = true
    var englishTitle = false
    var authors = true
    var authorsEnglish = false
    var year = true
    var source = true
    var addedTime = true
    var editedTime = true
    var tags = true
    var rating = true
    var image = true
    var attachmentStatus = false
    var note = true
    var rqs = false
    var conclusion = false
    var results = false
    var category = false
    var impactFactor = false
    var samples = false
    var participantType = false
    var variables = false
    var dataCollection = false
    var dataAnalysis = false
    var methodology = false
    var theoreticalFoundation = false
    var educationalLevel = false
    var country = false
    var keywords = false
    var limitations = false

    private enum CodingKeys: String, CodingKey {
        case title
        case englishTitle
        case authors
        case authorsEnglish
        case year
        case source
        case addedTime
        case editedTime
        case tags
        case rating
        case image
        case attachmentStatus
        case note
        case rqs
        case conclusion
        case results
        case category
        case impactFactor
        case samples
        case participantType
        case variables
        case dataCollection
        case dataAnalysis
        case methodology
        case theoreticalFoundation
        case educationalLevel
        case country
        case keywords
        case limitations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(Bool.self, forKey: .title) ?? true
        englishTitle = try container.decodeIfPresent(Bool.self, forKey: .englishTitle) ?? false
        authors = try container.decodeIfPresent(Bool.self, forKey: .authors) ?? true
        authorsEnglish = try container.decodeIfPresent(Bool.self, forKey: .authorsEnglish) ?? false
        year = try container.decodeIfPresent(Bool.self, forKey: .year) ?? true
        source = try container.decodeIfPresent(Bool.self, forKey: .source) ?? true
        addedTime = try container.decodeIfPresent(Bool.self, forKey: .addedTime) ?? true
        editedTime = try container.decodeIfPresent(Bool.self, forKey: .editedTime) ?? true
        tags = try container.decodeIfPresent(Bool.self, forKey: .tags) ?? true
        rating = try container.decodeIfPresent(Bool.self, forKey: .rating) ?? true
        image = try container.decodeIfPresent(Bool.self, forKey: .image) ?? true
        attachmentStatus = try container.decodeIfPresent(Bool.self, forKey: .attachmentStatus) ?? false
        note = try container.decodeIfPresent(Bool.self, forKey: .note) ?? true
        rqs = try container.decodeIfPresent(Bool.self, forKey: .rqs) ?? false
        conclusion = try container.decodeIfPresent(Bool.self, forKey: .conclusion) ?? false
        results = try container.decodeIfPresent(Bool.self, forKey: .results) ?? false
        category = try container.decodeIfPresent(Bool.self, forKey: .category) ?? false
        impactFactor = try container.decodeIfPresent(Bool.self, forKey: .impactFactor) ?? false
        samples = try container.decodeIfPresent(Bool.self, forKey: .samples) ?? false
        participantType = try container.decodeIfPresent(Bool.self, forKey: .participantType) ?? false
        variables = try container.decodeIfPresent(Bool.self, forKey: .variables) ?? false
        dataCollection = try container.decodeIfPresent(Bool.self, forKey: .dataCollection) ?? false
        dataAnalysis = try container.decodeIfPresent(Bool.self, forKey: .dataAnalysis) ?? false
        methodology = try container.decodeIfPresent(Bool.self, forKey: .methodology) ?? false
        theoreticalFoundation = try container.decodeIfPresent(Bool.self, forKey: .theoreticalFoundation) ?? false
        educationalLevel = try container.decodeIfPresent(Bool.self, forKey: .educationalLevel) ?? false
        country = try container.decodeIfPresent(Bool.self, forKey: .country) ?? false
        keywords = try container.decodeIfPresent(Bool.self, forKey: .keywords) ?? false
        limitations = try container.decodeIfPresent(Bool.self, forKey: .limitations) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(englishTitle, forKey: .englishTitle)
        try container.encode(authors, forKey: .authors)
        try container.encode(authorsEnglish, forKey: .authorsEnglish)
        try container.encode(year, forKey: .year)
        try container.encode(source, forKey: .source)
        try container.encode(addedTime, forKey: .addedTime)
        try container.encode(editedTime, forKey: .editedTime)
        try container.encode(tags, forKey: .tags)
        try container.encode(rating, forKey: .rating)
        try container.encode(image, forKey: .image)
        try container.encode(attachmentStatus, forKey: .attachmentStatus)
        try container.encode(note, forKey: .note)
        try container.encode(rqs, forKey: .rqs)
        try container.encode(conclusion, forKey: .conclusion)
        try container.encode(results, forKey: .results)
        try container.encode(category, forKey: .category)
        try container.encode(impactFactor, forKey: .impactFactor)
        try container.encode(samples, forKey: .samples)
        try container.encode(participantType, forKey: .participantType)
        try container.encode(variables, forKey: .variables)
        try container.encode(dataCollection, forKey: .dataCollection)
        try container.encode(dataAnalysis, forKey: .dataAnalysis)
        try container.encode(methodology, forKey: .methodology)
        try container.encode(theoreticalFoundation, forKey: .theoreticalFoundation)
        try container.encode(educationalLevel, forKey: .educationalLevel)
        try container.encode(country, forKey: .country)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(limitations, forKey: .limitations)
    }

    subscript(column: PaperTableColumn) -> Bool {
        get { self[keyPath: column.visibilityKeyPath] }
        set { self[keyPath: column.visibilityKeyPath] = newValue }
    }

    static var allVisible: PaperTableColumnVisibility {
        var visibility = PaperTableColumnVisibility()
        for column in PaperTableColumn.allCases {
            visibility[column] = true
        }
        return visibility
    }
}

enum PaperTableColumn: String, CaseIterable, Codable, Identifiable, Hashable {
    case title
    case englishTitle
    case authors
    case authorsEnglish
    case year
    case source
    case addedTime
    case editedTime
    case tags
    case rating
    case image
    case attachmentStatus
    case note
    case rqs
    case conclusion
    case results
    case category
    case impactFactor
    case samples
    case participantType
    case variables
    case dataCollection
    case dataAnalysis
    case methodology
    case theoreticalFoundation
    case educationalLevel
    case country
    case keywords
    case limitations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .englishTitle: return "English Title"
        case .authors: return "Authors"
        case .authorsEnglish: return "Authors (English)"
        case .year: return "Year"
        case .source: return "Source"
        case .addedTime: return "Added Time"
        case .editedTime: return "Edited Time"
        case .tags: return "Tags"
        case .rating: return "Rating"
        case .image: return "Image"
        case .attachmentStatus: return "Attachment"
        case .note: return "Note"
        case .rqs: return "RQs"
        case .conclusion: return "Conclusion"
        case .results: return "Results"
        case .category: return "Category"
        case .impactFactor: return "IF"
        case .samples: return "Samples"
        case .participantType: return "Participant Type"
        case .variables: return "Variables"
        case .dataCollection: return "Data Collection"
        case .dataAnalysis: return "Data Analysis"
        case .methodology: return "Methodology"
        case .theoreticalFoundation: return "Theoretical Foundation"
        case .educationalLevel: return "Educational Level"
        case .country: return "Country"
        case .keywords: return "Keywords"
        case .limitations: return "Limitations"
        }
    }

    var tableHeaderTitle: String {
        displayName
    }

    var defaultWidth: CGFloat {
        switch self {
        case .title: return 420
        case .englishTitle: return 420
        case .authors: return 260
        case .authorsEnglish: return 260
        case .year: return 90
        case .source: return 240
        case .addedTime: return 198
        case .editedTime: return 198
        case .tags: return 112
        case .rating: return 96
        case .image: return 220
        case .attachmentStatus: return 128
        case .note: return 180
        case .rqs: return 260
        case .conclusion: return 260
        case .results: return 260
        case .category: return 190
        case .impactFactor: return 100
        case .samples: return 180
        case .participantType: return 260
        case .variables: return 240
        case .dataCollection: return 260
        case .dataAnalysis: return 260
        case .methodology: return 240
        case .theoreticalFoundation: return 320
        case .educationalLevel: return 240
        case .country: return 160
        case .keywords: return 320
        case .limitations: return 320
        }
    }

    var visibilityKeyPath: WritableKeyPath<PaperTableColumnVisibility, Bool> {
        switch self {
        case .title: return \.title
        case .englishTitle: return \.englishTitle
        case .authors: return \.authors
        case .authorsEnglish: return \.authorsEnglish
        case .year: return \.year
        case .source: return \.source
        case .addedTime: return \.addedTime
        case .editedTime: return \.editedTime
        case .tags: return \.tags
        case .rating: return \.rating
        case .image: return \.image
        case .attachmentStatus: return \.attachmentStatus
        case .note: return \.note
        case .rqs: return \.rqs
        case .conclusion: return \.conclusion
        case .results: return \.results
        case .category: return \.category
        case .impactFactor: return \.impactFactor
        case .samples: return \.samples
        case .participantType: return \.participantType
        case .variables: return \.variables
        case .dataCollection: return \.dataCollection
        case .dataAnalysis: return \.dataAnalysis
        case .methodology: return \.methodology
        case .theoreticalFoundation: return \.theoreticalFoundation
        case .educationalLevel: return \.educationalLevel
        case .country: return \.country
        case .keywords: return \.keywords
        case .limitations: return \.limitations
        }
    }

    static var defaultOrder: [PaperTableColumn] {
        allCases
    }

    static func fromTableHeaderTitle(_ title: String) -> PaperTableColumn? {
        let normalized = normalizedColumnToken(title)
        return allCases.first {
            normalizedColumnToken($0.tableHeaderTitle) == normalized
                || normalizedColumnToken($0.rawValue) == normalized
        }
    }

    private static func normalizedColumnToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

enum InspectorMetadataField: String, CaseIterable, Codable, Identifiable {
    case year
    case source
    case doi
    case volume
    case issue
    case pages
    case paperType
    case rqs
    case conclusion
    case results
    case category
    case impactFactor
    case samples
    case participantType
    case variables
    case dataCollection
    case dataAnalysis
    case methodology
    case theoreticalFoundation
    case educationalLevel
    case country
    case keywords
    case limitations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .year: return "Year"
        case .source: return "Source"
        case .doi: return "DOI"
        case .volume: return "Volume"
        case .issue: return "Issue"
        case .pages: return "Pages"
        case .paperType: return "Paper Type"
        case .rqs: return "RQs"
        case .conclusion: return "Conclusion"
        case .results: return "Results"
        case .category: return "Category"
        case .impactFactor: return "IF"
        case .samples: return "Samples"
        case .participantType: return "Participant Type"
        case .variables: return "Variables"
        case .dataCollection: return "Data Collection"
        case .dataAnalysis: return "Data Analysis"
        case .methodology: return "Methodology"
        case .theoreticalFoundation: return "Theoretical Foundation"
        case .educationalLevel: return "Educational Level"
        case .country: return "Country"
        case .keywords: return "Keywords"
        case .limitations: return "Limitations"
        }
    }

    var placeholder: String {
        switch self {
        case .year:
            return "Not set"
        case .source:
            return "Add journal or venue"
        case .doi:
            return "Add DOI"
        case .volume, .issue, .pages, .paperType, .category, .impactFactor, .samples, .participantType,
             .variables, .dataCollection, .dataAnalysis, .methodology, .theoreticalFoundation,
             .educationalLevel, .country, .keywords, .limitations, .rqs, .conclusion, .results:
            return "Add \(displayName)"
        }
    }

    static var defaultOrder: [InspectorMetadataField] {
        allCases
    }
}

struct AppSettingsSnapshot: Codable {
    var metadataAPIProvider: MetadataAPIProvider?
    var metadataAPIBaseURL: String
    var metadataAPIKey: String
    var metadataModel: String
    var metadataThinkingMode: MetadataThinkingMode?
    var pdf2zhEnvironmentKind: PDF2ZHEnvironmentKind?
    var pdf2zhEnvironmentName: String?
    var pdf2zhCustomActivationCommand: String?
    var metadataPromptTemplate: String?
    var papersStorageDirectoryPath: String?
    var papersStorageBookmarkData: Data?
    var citationPreset: CitationPreset
    var inTextCitationTemplate: String
    var referenceCitationTemplate: String
    var exportBibTeXFields: BibTeXExportFieldOptions
    var tableRowHeightPreset: TableRowHeightPreset?
    var rowHeightScaleFactor: Double?
    var tableRowHeightMultiplier: Double?
    var recentReadingRange: RecentReadingRange?
    var zombiePapersThreshold: ZombiePaperThreshold?
    var appLanguage: AppLanguage?
    var mcpEnabled: Bool?
    var mcpServerName: String?
    var mcpServerHost: String?
    var mcpServerPort: Int?
    var mcpServerPath: String?
    var mcpMaxContentLength: Int?
    var mcpMaxAttachments: Int?
    var mcpMaxNotes: Int?
    var mcpKeywordLimit: Int?
    var mcpSearchResultLimit: Int?
    var mcpMaxNumericValues: Int?
    var autoRenameImportedPDFFiles: Bool?
    var imageThumbnailMaxSizeMultiplier: Double?
    var paperTableColumnVisibility: PaperTableColumnVisibility?
    var paperTableColumnOrder: [PaperTableColumn]?
    var paperTableColumnWidths: [String: Double]?
    var inspectorMetadataOrder: [InspectorMetadataField]?
    var metadataCustomRefreshFields: [MetadataField]?
    var tagQuickNumberMap: [String: Int]?
    var mainWindowWidth: Double?
    var mainWindowHeight: Double?
}

private struct LegacySettingsSnapshot: Codable {
    var siliconFlowAPIKey: String
    var siliconFlowModel: String
}

@MainActor
final class SettingsStore: ObservableObject {
    static let defaultAPIProvider: MetadataAPIProvider = .siliconFlow
    static let defaultAPIBaseURL = defaultAPIProvider.defaultEndpoint
    static let defaultModel = defaultAPIProvider.defaultModel
    static let defaultPDF2ZHEnvironmentKind: PDF2ZHEnvironmentKind = .conda
    static let defaultPDF2ZHEnvironmentName = "tools-dev"
    static let defaultMCPServerName = "Litrix-mcp"
    static let defaultMCPServerHost = "127.0.0.1"
    static let defaultMCPServerPort = 23120
    static let defaultMCPServerPath = "/mcp"
    static let defaultMCPMaxContentLength = 6_000
    static let defaultMCPMaxAttachments = 6
    static let defaultMCPMaxNotes = 8
    static let defaultMCPKeywordLimit = 24
    static let defaultMCPSearchResultLimit = 30
    static let defaultMCPMaxNumericValues = 120
    static let defaultPapersDirectoryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Litrix/Papers", isDirectory: true)
        .path
    static let defaultMetadataPromptTemplate = """
    你是文献元数据提取助手。你将收到“文件名”和“PDF 文本片段”。
    你的任务是提取和总结元数据（优先提取），并且只输出一个 JSON 对象，不允许输出 Markdown、解释或代码块。
    JSON 键必须严格为（键名不可增删、不可改名）：
    {"title":"","englishTitle":"","authors":"","authorsEnglish":"","year":"","source":"","doi":"","abstractText":"","volume":"","issue":"","pages":"","paperType":"","rqs":"","conclusion":"","results":"","category":"","impactFactor":"","samples":"","participantType":"","variables":"","dataCollection":"","dataAnalysis":"","methodology":"","theoreticalFoundation":"","educationalLevel":"","country":"","keywords":"","limitations":""}

    规则：
    1. 只能基于输入内容提取；不确定时填空字符串。
    2. authors 使用单个字符串，多个作者用 ", " 连接。
    2.1 englishTitle：从文献中提取文献的英语标题，优先从原文提取，原文不存在时，翻译中文标题。
    2.2 authorsEnglish：从文献中提取文献的所有作者的英语姓名，用 ", " 分割，优先从原文提取，原文不存在时，翻译中文姓名。
    3. year 优先返回四位数字，不确定则留空。
    4. keywords 用英文逗号分隔（例如 "teacher burnout, workload, wellbeing"）。
    5. IF包括JCR分区（中国期刊使用中文期刊等级，如北大核心，CSSCI），期刊分类（不同分类换行处理，如SCI，SSCI），期刊影响因子。该数据请你联网查询并整理。格式为：Q1, SCI, CSSCI, 17.3
    6. RQs即从原文摘取研究问题，并补充翻译。若原文无研究问题，从原文总结，在总结的问题后添加“🤖”表情包，表示是从原文总结的。格式如“1️⃣ 哪些因素导致教师对生成式人工智能产生依赖？What factors contribute to teachers' addiction to generative AI; 2️⃣ I-PACE模型在多大程度上能够解释教师对生成式人工智能的依赖？To what extent can the I-PACE model explain teachers' addiction to generative AI?🤖”
    7. Variables从原文提取，变量内部用“, ”隔开。英文变量名翻译成中文，但在括号内保留英语原文，下同。若文章包含干扰变量，调节变量，控制变量等，需以相同格式补充。示例如：
    1️⃣ 自变量：自我效能（Self-efficacy），认知需求（Need for cognition）；2️⃣因变量：生成式人工智能依赖（Generative AI addiction）
    8. Data collection 从原文提取，格式为“数据收集方式*数据样本量：数据内容”。是例如：1️⃣在线问卷*1750：教师人口学信息，AI使用行为，相关心理因素；2️⃣ 半结构访谈*25：使用AI的原因，AI存在的问题。
    9. Data analysis  从原文提取，格式如：描述性统计（Descriptive Statistics），验证性因子分析（Confirmatory Factor Analysis, CFA），结构方程模型（Structural Equation Modeling, SEM），Pearson 相关分析（Pearson Correlation Analysis）
    10. Methodology 为文章的方法论，如定量，定性，混合，行动研究，基于设计的研究...，格式为：定量研究（quantitative research），行动研究（action research）
    11. Theoretical foundation 为文章的理论基础，格式为：I-PACE模型（I-PACE model），认知学徒制（Cognitive Apprenticeship）
    12. Educational level 为文章中被试的教育水平，格式如：幼儿园（kindergarten），小学（primary school）
    13. Country 从文中提取，国家前面加国旗表情包，格式为：🇨🇳中国（China），🇸🇬新加坡（Singapore）
    14. Keywords 从文中提取，无关键词不添加。格式为：生成式人工智能（Generative AI），人工智能成瘾（AI addiction），I-PACE模型（I-PACE model），教育技术（educational technology），教师（teacher）
    15. Results  从文中提取，用富含语意密度的句子准确清晰地分点概述，每点50字以内，可分多点。句子不要空洞的陈述，要言之有物。格式为：1️⃣教师的认知需求（Need for Cognition）和AI自我效能（Self-efficacy）均对生成式AI成瘾具有显著负向预测作用，表明具备较强思辨能力和技术掌控感的教师更倾向于策略性、反思性地使用AI，而非陷入依赖。2️⃣...3️⃣ ...
    16. Conclusion 从文中提取，用富含语意密度的句子准确清晰地分点概述，每点50字以内，可分多点。格式为：1️⃣ 微游戏化设计（短任务单元、分散式计分）显著降低认知负荷。2️⃣ 微游戏化与传统设计在心理结果（游戏化体验、内在动机和参与度）上无显著差异。3️⃣ ...
    17. Participant type 从文中提取，用一句话或短语言简意赅地对文章的参与者类型进行总结并翻译，格式如：使用人工智能的一线在职教师（Frontline in-service teachers who use artificial intelligence）
    18. Samples  从文中提取，包括总样本数和组内样本数，理论研究，综述等则汇报文献数。格式为：N=1750人，n1=500人，n2=500人，n3=750人
    19. source为期刊，准确的记录期刊全称
    20. "volume":"","issue":"","pages"等从原文提取，回复数字或者如“231-239”
    21. Category从原文总结，如Empirical Research，Empirical Research, Literature Review; Methodological Paper; Theoretical Article
    22. paperType从原文总结，内容为文献类型，包括“期刊”“会议”“电子文献”等
    23. Limitations 从原文总结，用富含语意密度的句子准确清晰地分点概述，每点50字以内，可分多点。示例如：1️⃣采用横断面设计无法确立心理因素与生成式AI成瘾之间的因果关系，结构方程模型仅能揭示变量间的关联，难以判断影响方向。2️⃣...3️⃣...
    24. 输出必须是可被 JSON 解析器直接解析的合法 JSON。
    """

    @Published var metadataAPIProvider: MetadataAPIProvider {
        didSet { save() }
    }

    @Published var metadataAPIBaseURL: String {
        didSet { save() }
    }

    @Published var metadataAPIKey: String {
        didSet { save() }
    }

    @Published var metadataModel: String {
        didSet { save() }
    }

    @Published var metadataThinkingMode: MetadataThinkingMode {
        didSet { save() }
    }

    @Published var pdf2zhEnvironmentKind: PDF2ZHEnvironmentKind {
        didSet { save() }
    }

    @Published var pdf2zhEnvironmentName: String {
        didSet { save() }
    }

    @Published var pdf2zhCustomActivationCommand: String {
        didSet { save() }
    }

    @Published var metadataPromptTemplate: String {
        didSet { save() }
    }

    @Published var papersStorageDirectoryPath: String {
        didSet { save() }
    }

    @Published var citationPreset: CitationPreset {
        didSet { save() }
    }

    @Published var inTextCitationTemplate: String {
        didSet { save() }
    }

    @Published var referenceCitationTemplate: String {
        didSet { save() }
    }

    @Published var exportBibTeXFields: BibTeXExportFieldOptions {
        didSet { save() }
    }

    @Published var rowHeightScaleFactor: Double {
        didSet { save() }
    }

    @Published var tableRowHeightMultiplier: Double {
        didSet { save() }
    }

    @Published var recentReadingRange: RecentReadingRange {
        didSet { save() }
    }

    @Published var zombiePapersThreshold: ZombiePaperThreshold {
        didSet { save() }
    }

    @Published var appLanguage: AppLanguage {
        didSet { save() }
    }

    @Published var mcpEnabled: Bool {
        didSet { save() }
    }

    @Published var mcpServerName: String {
        didSet { save() }
    }

    @Published var mcpServerHost: String {
        didSet { save() }
    }

    @Published var mcpServerPort: Int {
        didSet { save() }
    }

    @Published var mcpServerPath: String {
        didSet { save() }
    }

    @Published var mcpMaxContentLength: Int {
        didSet { save() }
    }

    @Published var mcpMaxAttachments: Int {
        didSet { save() }
    }

    @Published var mcpMaxNotes: Int {
        didSet { save() }
    }

    @Published var mcpKeywordLimit: Int {
        didSet { save() }
    }

    @Published var mcpSearchResultLimit: Int {
        didSet { save() }
    }

    @Published var mcpMaxNumericValues: Int {
        didSet { save() }
    }

    @Published var autoRenameImportedPDFFiles: Bool {
        didSet { save() }
    }

    @Published var imageThumbnailMaxSizeMultiplier: Double {
        didSet { save() }
    }

    @Published var paperTableColumnVisibility: PaperTableColumnVisibility {
        didSet { save() }
    }

    @Published var paperTableColumnOrder: [PaperTableColumn] {
        didSet { save() }
    }

    @Published var paperTableColumnWidths: [String: Double] {
        didSet { save() }
    }

    @Published var inspectorMetadataOrder: [InspectorMetadataField] {
        didSet { save() }
    }

    @Published var metadataCustomRefreshFields: [MetadataField] {
        didSet { save() }
    }

    @Published var tagQuickNumberMap: [String: Int] {
        didSet { save() }
    }

    @Published private(set) var hasPapersStoragePermission = true

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var papersStorageBookmarkData: Data?
    private var activeSecurityScopedPapersURL: URL?
    private var mainWindowWidth: Double?
    private var mainWindowHeight: Double?
    private var pendingSaveTask: Task<Void, Never>?
    private var isLoadingSnapshot = false

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let env = ProcessInfo.processInfo.environment
        let envKey = env["PAPERDOCK_API_KEY"]
            ?? env["PAPERDOCK_SILICONFLOW_API_KEY"]
            ?? env["DASHSCOPE_API_KEY"]
            ?? ""
        let envEndpoint = env["PAPERDOCK_API_BASE_URL"] ?? Self.defaultAPIBaseURL
        let initialProvider = Self.inferAPIProvider(from: envEndpoint)

        metadataAPIProvider = initialProvider
        metadataAPIBaseURL = envEndpoint
        metadataAPIKey = envKey
        metadataModel = initialProvider.defaultModel
        metadataThinkingMode = .nonThinking
        pdf2zhEnvironmentKind = Self.defaultPDF2ZHEnvironmentKind
        pdf2zhEnvironmentName = Self.defaultPDF2ZHEnvironmentName
        pdf2zhCustomActivationCommand = ""
        metadataPromptTemplate = Self.defaultMetadataPromptTemplate
        papersStorageDirectoryPath = Self.defaultPapersDirectoryPath
        citationPreset = .apa7

        let defaultTemplate = Self.defaultCitationTemplate(for: .apa7)
        inTextCitationTemplate = defaultTemplate.inText
        referenceCitationTemplate = defaultTemplate.reference
        exportBibTeXFields = BibTeXExportFieldOptions()
        rowHeightScaleFactor = 9
        tableRowHeightMultiplier = 1
        recentReadingRange = .twoDays
        zombiePapersThreshold = .oneMonth
        appLanguage = .chinese
        mcpEnabled = false
        mcpServerName = Self.defaultMCPServerName
        mcpServerHost = Self.defaultMCPServerHost
        mcpServerPort = Self.defaultMCPServerPort
        mcpServerPath = Self.defaultMCPServerPath
        mcpMaxContentLength = Self.defaultMCPMaxContentLength
        mcpMaxAttachments = Self.defaultMCPMaxAttachments
        mcpMaxNotes = Self.defaultMCPMaxNotes
        mcpKeywordLimit = Self.defaultMCPKeywordLimit
        mcpSearchResultLimit = Self.defaultMCPSearchResultLimit
        mcpMaxNumericValues = Self.defaultMCPMaxNumericValues
        autoRenameImportedPDFFiles = true
        imageThumbnailMaxSizeMultiplier = 0.5
        paperTableColumnVisibility = PaperTableColumnVisibility()
        paperTableColumnOrder = PaperTableColumn.defaultOrder
        paperTableColumnWidths = [:]
        inspectorMetadataOrder = InspectorMetadataField.defaultOrder
        metadataCustomRefreshFields = MetadataField.allCases
        tagQuickNumberMap = [:]
        mainWindowWidth = nil
        mainWindowHeight = nil

        load()
        ensureMetadataPromptFileIfNeeded()
        restorePapersDirectoryAccessIfPossible()
    }

    var resolvedAPIKey: String {
        let key = metadataAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            return key
        }

        let env = ProcessInfo.processInfo.environment
        return env["PAPERDOCK_API_KEY"]
            ?? env["PAPERDOCK_SILICONFLOW_API_KEY"]
            ?? env["DASHSCOPE_API_KEY"]
            ?? ""
    }

    var resolvedAPIEndpoint: URL {
        let normalizedEndpoint = Self.normalizedAPIEndpointString(
            provider: metadataAPIProvider,
            rawEndpoint: metadataAPIBaseURL
        )
        return URL(string: normalizedEndpoint) ?? URL(string: metadataAPIProvider.defaultEndpoint)!
    }

    var resolvedAPIProvider: MetadataAPIProvider {
        metadataAPIProvider
    }

    var resolvedModel: String {
        let trimmed = metadataModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? metadataAPIProvider.defaultModel : trimmed
    }

    var resolvedThinkingEnabled: Bool {
        metadataThinkingMode == .thinking
    }

    var resolvedPDF2ZHEnvironmentName: String {
        let trimmed = pdf2zhEnvironmentName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch pdf2zhEnvironmentKind {
        case .base:
            return trimmed.isEmpty ? "base" : trimmed
        case .conda:
            return trimmed.isEmpty ? Self.defaultPDF2ZHEnvironmentName : trimmed
        case .custom:
            return trimmed
        }
    }

    var resolvedPDF2ZHCustomActivationCommand: String {
        pdf2zhCustomActivationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedPDF2ZHBaseURL: String {
        let endpointString = resolvedAPIEndpoint.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = "/chat/completions"
        if endpointString.lowercased().hasSuffix(suffix) {
            return String(endpointString.dropLast(suffix.count))
        }
        return endpointString
    }

    func pdf2zhActivationShellLines() -> [String]? {
        switch pdf2zhEnvironmentKind {
        case .base:
            guard let profilePath = pdf2zhCondaProfilePath() else { return nil }
            return [
                "source \(shellQuote(profilePath))",
                "conda activate \(shellQuote(resolvedPDF2ZHEnvironmentName))"
            ]
        case .conda:
            guard let profilePath = pdf2zhCondaProfilePath() else { return nil }
            let environmentName = resolvedPDF2ZHEnvironmentName
            guard !environmentName.isEmpty else { return nil }
            return [
                "source \(shellQuote(profilePath))",
                "conda activate \(shellQuote(environmentName))"
            ]
        case .custom:
            let command = resolvedPDF2ZHCustomActivationCommand
            guard !command.isEmpty else { return nil }
            return [command]
        }
    }

    func pdf2zhInstallInstructions() -> String {
        switch pdf2zhEnvironmentKind {
        case .base, .conda:
            let environmentName = resolvedPDF2ZHEnvironmentName
            let activation = [
                pdf2zhCondaProfilePath().map { "source \($0)" },
                "conda activate \(environmentName)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            return """
            \(activation)
            python -m pip install --upgrade pdf2zh
            """
        case .custom:
            let custom = resolvedPDF2ZHCustomActivationCommand
            let prefix = custom.isEmpty ? "# 先执行你的环境启动命令" : custom
            return """
            \(prefix)
            python -m pip install --upgrade pdf2zh
            """
        }
    }

    var resolvedMCPServerName: String {
        let trimmed = mcpServerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultMCPServerName : trimmed
    }

    var resolvedMCPServerHost: String {
        let trimmed = mcpServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultMCPServerHost : trimmed
    }

    var resolvedMCPServerPort: Int {
        let candidate = mcpServerPort
        if (1...65_535).contains(candidate) {
            return candidate
        }
        return Self.defaultMCPServerPort
    }

    var resolvedMCPServerPath: String {
        let trimmed = mcpServerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.defaultMCPServerPath }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    var resolvedMCPServerURLString: String {
        "http://\(resolvedMCPServerHost):\(resolvedMCPServerPort)\(resolvedMCPServerPath)"
    }

    var resolvedZombiePapersInterval: TimeInterval {
        zombiePapersThreshold.interval
    }

    var resolvedMainWindowSize: NSSize? {
        guard let mainWindowWidth, let mainWindowHeight else { return nil }
        guard mainWindowWidth.isFinite, mainWindowHeight.isFinite else { return nil }
        guard mainWindowWidth >= 320, mainWindowHeight >= 240 else { return nil }
        return NSSize(width: mainWindowWidth, height: mainWindowHeight)
    }

    var resolvedMetadataPromptTemplate: String {
        let trimmed = metadataPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultMetadataPromptTemplate : metadataPromptTemplate
    }

    var metadataPromptFileURL: URL {
        storageDirectory.appendingPathComponent("metadata-prompts.txt", isDirectory: false)
    }

    var resolvedMetadataPromptBlueprint: MetadataPromptBlueprint {
        ensureMetadataPromptFileIfNeeded()

        if let text = try? String(contentsOf: metadataPromptFileURL, encoding: .utf8),
           let parsed = MetadataPromptBlueprint.fromDocument(text) {
            return parsed
        }

        return .default
    }

    func openMetadataPromptFileInEditor() {
        ensureMetadataPromptFileIfNeeded()
        NSWorkspace.shared.open(metadataPromptFileURL)
    }

    var resolvedPapersDirectoryURL: URL {
        let trimmed = papersStorageDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPath = trimmed.isEmpty ? Self.defaultPapersDirectoryPath : trimmed
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
    }

    var resolvedTableRowHeight: CGFloat {
        let baseFontSize: CGFloat = 13
        return max(18, baseFontSize)
    }

    var resolvedMaximumTableRowHeight: CGFloat {
        max(resolvedTableRowHeight, resolvedTableRowHeight * resolvedTableRowHeightScaleFactor)
    }

    var resolvedExpandedTableLineLimit: Int {
        let estimatedLineHeight: CGFloat = 18
        let lines = Int(floor(resolvedMaximumTableRowHeight / estimatedLineHeight))
        return max(2, lines)
    }

    var resolvedTableRowHeightScaleFactor: CGFloat {
        let factor = CGFloat(rowHeightScaleFactor)
        if !factor.isFinite || factor < 1 {
            return 9
        }
        return factor
    }

    var resolvedTableRowHeightMultiplier: CGFloat {
        let multiplier = CGFloat(tableRowHeightMultiplier)
        if !multiplier.isFinite || multiplier <= 0 {
            return 1
        }
        return multiplier
    }

    var resolvedImageThumbnailMaxSizeMultiplier: CGFloat {
        let multiplier = CGFloat(imageThumbnailMaxSizeMultiplier)
        if !multiplier.isFinite {
            return 0.5
        }
        return min(max(multiplier, 0.1), 4)
    }

    func applyExpandedRowHeight() {
        tableRowHeightMultiplier = 2
    }

    func applyCompactRowHeight() {
        tableRowHeightMultiplier = 1
    }

    func applyCitationPreset(_ preset: CitationPreset) {
        citationPreset = preset
        guard preset != .custom else { return }
        let template = Self.defaultCitationTemplate(for: preset)
        inTextCitationTemplate = template.inText
        referenceCitationTemplate = template.reference
    }

    func applyMetadataAPIProvider(_ provider: MetadataAPIProvider) {
        metadataAPIProvider = provider
        metadataAPIBaseURL = provider.defaultEndpoint
        metadataModel = provider.defaultModel
    }

    func recordMainWindowSize(_ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite else { return }
        let normalizedWidth = Double(max(320, round(size.width)))
        let normalizedHeight = Double(max(240, round(size.height)))
        guard mainWindowWidth != normalizedWidth || mainWindowHeight != normalizedHeight else { return }
        mainWindowWidth = normalizedWidth
        mainWindowHeight = normalizedHeight
        save()
    }

    func quickNumber(forTag tag: String) -> Int? {
        tagQuickNumberMap[tag]
    }

    func assignQuickNumber(_ number: Int?, toTag tag: String) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }

        if let number {
            guard (1...9).contains(number) else { return }
            for (existingTag, mappedNumber) in tagQuickNumberMap where mappedNumber == number && existingTag != trimmedTag {
                tagQuickNumberMap.removeValue(forKey: existingTag)
            }
            tagQuickNumberMap[trimmedTag] = number
        } else {
            tagQuickNumberMap.removeValue(forKey: trimmedTag)
        }
    }

    func remapTagQuickNumber(from oldTag: String, to newTag: String) {
        guard let number = tagQuickNumberMap.removeValue(forKey: oldTag) else { return }
        assignQuickNumber(number, toTag: newTag)
    }

    func removeQuickNumber(forTag tag: String) {
        tagQuickNumberMap.removeValue(forKey: tag)
    }

    func resetExportFieldsToDefault() {
        exportBibTeXFields = BibTeXExportFieldOptions()
    }

    func applyPaperTableColumnOrder(_ order: [PaperTableColumn]) {
        let normalized = normalizedPaperTableColumnOrder(order)
        guard normalized != paperTableColumnOrder else { return }
        paperTableColumnOrder = normalized
    }

    func paperTableColumnWidth(for column: PaperTableColumn) -> CGFloat {
        let stored = paperTableColumnWidths[column.rawValue]
        let resolved = stored ?? Double(column.defaultWidth)
        return CGFloat(resolved)
    }

    func setPaperTableColumnWidth(_ width: CGFloat, for column: PaperTableColumn) {
        guard width.isFinite, width > 1 else { return }

        let normalized = Double(max(36, width))
        let current = paperTableColumnWidths[column.rawValue] ?? Double(column.defaultWidth)
        guard abs(current - normalized) > 0.5 else { return }

        var updated = paperTableColumnWidths
        updated[column.rawValue] = normalized
        paperTableColumnWidths = updated
    }

    func resetPaperTableColumns() {
        paperTableColumnVisibility = .allVisible
        paperTableColumnOrder = PaperTableColumn.defaultOrder
        paperTableColumnWidths = [:]
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(storageDirectory)
    }

    func openPapersStorageFolder() {
        let url = resolvedPapersDirectoryURL
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func generateMCPConfigurationFile() throws -> URL {
        let normalizedServerName = normalizedMCPServerName(mcpServerName, fallback: Self.defaultMCPServerName)
        let normalizedServerHost = normalizedMCPServerHost(mcpServerHost, fallback: Self.defaultMCPServerHost)
        let normalizedServerPort = normalizedMCPServerPort(mcpServerPort, fallback: Self.defaultMCPServerPort)
        let normalizedServerPath = normalizedMCPServerPath(mcpServerPath, fallback: Self.defaultMCPServerPath)
        let normalizedContentLength = normalizedMCPInt(
            mcpMaxContentLength,
            fallback: Self.defaultMCPMaxContentLength,
            range: 500...100_000
        )
        let normalizedMaxAttachments = normalizedMCPInt(
            mcpMaxAttachments,
            fallback: Self.defaultMCPMaxAttachments,
            range: 1...100
        )
        let normalizedMaxNotes = normalizedMCPInt(
            mcpMaxNotes,
            fallback: Self.defaultMCPMaxNotes,
            range: 1...200
        )
        let normalizedKeywordLimit = normalizedMCPInt(
            mcpKeywordLimit,
            fallback: Self.defaultMCPKeywordLimit,
            range: 1...200
        )
        let normalizedSearchResultLimit = normalizedMCPInt(
            mcpSearchResultLimit,
            fallback: Self.defaultMCPSearchResultLimit,
            range: 1...500
        )
        let normalizedNumericLimit = normalizedMCPInt(
            mcpMaxNumericValues,
            fallback: Self.defaultMCPMaxNumericValues,
            range: 1...2_000
        )

        mcpServerName = normalizedServerName
        mcpServerHost = normalizedServerHost
        mcpServerPort = normalizedServerPort
        mcpServerPath = normalizedServerPath
        mcpMaxContentLength = normalizedContentLength
        mcpMaxAttachments = normalizedMaxAttachments
        mcpMaxNotes = normalizedMaxNotes
        mcpKeywordLimit = normalizedKeywordLimit
        mcpSearchResultLimit = normalizedSearchResultLimit
        mcpMaxNumericValues = normalizedNumericLimit

        let capabilities = [
            "semantic_search",
            "search_library",
            "browse_library_structure",
            "read_item_metadata",
            "describe_metadata_fields",
            "update_item_metadata",
            "read_abstract",
            "read_fulltext",
            "search_annotations",
            "find_similar",
            "item_details",
            "fulltext_cache_stats",
            "semantic_index_status",
            "manage_collections",
            "create_or_update_items",
            "manage_tags",
            "create_or_append_notes"
        ]

        let config: [String: Any] = [
            "enabled": mcpEnabled,
            "provider": "litrix-mcp",
            "generated_at": ISO8601DateFormatter().string(from: .now),
            "server": [
                "name": normalizedServerName,
                "url": "http://\(normalizedServerHost):\(normalizedServerPort)\(normalizedServerPath)"
            ],
            "capabilities": capabilities,
            "limits": [
                "max_content_length": normalizedContentLength,
                "max_attachments": normalizedMaxAttachments,
                "max_notes": normalizedMaxNotes,
                "max_keywords": normalizedKeywordLimit,
                "search_result_limit": normalizedSearchResultLimit,
                "max_numeric_values": normalizedNumericLimit
            ]
        ]

        let mcpDirectory = storageDirectory.appendingPathComponent("mcp", isDirectory: true)
        try fileManager.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let fileURL = mcpDirectory.appendingPathComponent("litrix-mcp-config.json", isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func openMCPConfigurationDirectory() {
        let mcpDirectory = storageDirectory.appendingPathComponent("mcp", isDirectory: true)
        try? fileManager.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(mcpDirectory)
    }

    func mcpConfigurationSnippet(for client: MCPClientType) -> String {
        let serverName = resolvedMCPServerName
        let endpoint = resolvedMCPServerURLString

        switch client {
        case .codexCLI, .claudeCode, .geminiCLI:
            return """
            [mcp_servers."\(serverName)"]
            type = "http"
            url = "\(endpoint)"

            [mcp_servers."\(serverName)".headers]
            "Content-Type" = "application/json"
            """
        case .customHTTP:
            return """
            POST \(endpoint)
            Content-Type: application/json

            {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}
            """
        default:
            return """
            {
              "mcpServers": {
                "\(serverName)": {
                  "type": "http",
                  "url": "\(endpoint)",
                  "headers": {
                    "Content-Type": "application/json"
                  }
                }
              }
            }
            """
        }
    }

    func mcpUsageGuide(for client: MCPClientType) -> String {
        let serverName = resolvedMCPServerName
        let endpoint = resolvedMCPServerURLString
        let port = resolvedMCPServerPort

        return """
        # \(client.documentationTitle)

        ## 服务器信息
        - **服务名称**: \(serverName)
        - **端口**: \(port)
        - **端点**: \(endpoint)

        ## 能力说明
        - 查看任意文献元数据（标题、作者、年份、来源、DOI、摘要等）
        - 编辑任意文献元数据（支持更新字段并写回）
        - 检索文库、语义搜索、读取批注、管理标签与集合

        ## 使用步骤
        1. 在客户端打开 MCP 配置文件。
        2. 粘贴“配置内容”区域文本并保存。
        3. 重启客户端并连接 MCP。
        4. 先执行一次 `list tools` 或同等命令确认连接成功。
        """
    }

    func exportSnapshotForArchive() -> AppSettingsSnapshot {
        buildSnapshot(includeSecrets: false)
    }

    func exportCurrentSnapshot(includeSecrets: Bool = true) -> AppSettingsSnapshot {
        buildSnapshot(includeSecrets: includeSecrets)
    }

    func applyImportedSettings(_ snapshot: AppSettingsSnapshot, preserveAPIKey: Bool) {
        let preservedKey = metadataAPIKey
        let nextProvider = snapshot.metadataAPIProvider ?? Self.inferAPIProvider(from: snapshot.metadataAPIBaseURL)

        metadataAPIProvider = nextProvider
        metadataAPIBaseURL = Self.normalizedAPIEndpointString(
            provider: nextProvider,
            rawEndpoint: snapshot.metadataAPIBaseURL
        )
        if preserveAPIKey {
            metadataAPIKey = preservedKey
        } else {
            metadataAPIKey = snapshot.metadataAPIKey
        }
        metadataModel = snapshot.metadataModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nextProvider.defaultModel
            : snapshot.metadataModel
        metadataThinkingMode = snapshot.metadataThinkingMode ?? .nonThinking
        pdf2zhEnvironmentKind = snapshot.pdf2zhEnvironmentKind ?? Self.defaultPDF2ZHEnvironmentKind
        pdf2zhEnvironmentName = snapshot.pdf2zhEnvironmentName ?? Self.defaultPDF2ZHEnvironmentName
        pdf2zhCustomActivationCommand = snapshot.pdf2zhCustomActivationCommand ?? ""
        metadataPromptTemplate = snapshot.metadataPromptTemplate ?? metadataPromptTemplate

        let importedDirectoryPath = snapshot.papersStorageDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let importedDirectoryPath, !importedDirectoryPath.isEmpty {
            papersStorageDirectoryPath = importedDirectoryPath
        }
        papersStorageBookmarkData = snapshot.papersStorageBookmarkData
        updatePermissionState(for: resolvedPapersDirectoryURL)

        citationPreset = snapshot.citationPreset
        inTextCitationTemplate = snapshot.inTextCitationTemplate
        referenceCitationTemplate = snapshot.referenceCitationTemplate
        exportBibTeXFields = snapshot.exportBibTeXFields
        rowHeightScaleFactor = max(1, snapshot.rowHeightScaleFactor ?? rowHeightScaleFactor)
        if let tableMultiplier = snapshot.tableRowHeightMultiplier, tableMultiplier > 0 {
            tableRowHeightMultiplier = tableMultiplier
        } else if let legacyPreset = snapshot.tableRowHeightPreset {
            tableRowHeightMultiplier = Double(legacyPreset.multiplier)
        }
        recentReadingRange = snapshot.recentReadingRange ?? recentReadingRange
        zombiePapersThreshold = snapshot.zombiePapersThreshold ?? zombiePapersThreshold
        appLanguage = snapshot.appLanguage ?? appLanguage
        mcpEnabled = snapshot.mcpEnabled ?? mcpEnabled
        mcpServerName = normalizedMCPServerName(snapshot.mcpServerName, fallback: mcpServerName)
        mcpServerHost = normalizedMCPServerHost(snapshot.mcpServerHost, fallback: mcpServerHost)
        mcpServerPort = normalizedMCPServerPort(snapshot.mcpServerPort, fallback: mcpServerPort)
        mcpServerPath = normalizedMCPServerPath(snapshot.mcpServerPath, fallback: mcpServerPath)
        mcpMaxContentLength = normalizedMCPInt(
            snapshot.mcpMaxContentLength,
            fallback: mcpMaxContentLength,
            range: 500...100_000
        )
        mcpMaxAttachments = normalizedMCPInt(
            snapshot.mcpMaxAttachments,
            fallback: mcpMaxAttachments,
            range: 1...100
        )
        mcpMaxNotes = normalizedMCPInt(
            snapshot.mcpMaxNotes,
            fallback: mcpMaxNotes,
            range: 1...200
        )
        mcpKeywordLimit = normalizedMCPInt(
            snapshot.mcpKeywordLimit,
            fallback: mcpKeywordLimit,
            range: 1...200
        )
        mcpSearchResultLimit = normalizedMCPInt(
            snapshot.mcpSearchResultLimit,
            fallback: mcpSearchResultLimit,
            range: 1...500
        )
        mcpMaxNumericValues = normalizedMCPInt(
            snapshot.mcpMaxNumericValues,
            fallback: mcpMaxNumericValues,
            range: 1...2_000
        )
        autoRenameImportedPDFFiles = snapshot.autoRenameImportedPDFFiles ?? autoRenameImportedPDFFiles
        imageThumbnailMaxSizeMultiplier = normalizedImageThumbnailMaxSizeMultiplier(
            snapshot.imageThumbnailMaxSizeMultiplier,
            fallback: imageThumbnailMaxSizeMultiplier
        )
        paperTableColumnVisibility = snapshot.paperTableColumnVisibility ?? paperTableColumnVisibility
        paperTableColumnOrder = normalizedPaperTableColumnOrder(snapshot.paperTableColumnOrder)
        paperTableColumnWidths = normalizedPaperTableColumnWidths(snapshot.paperTableColumnWidths)
        inspectorMetadataOrder = normalizedInspectorMetadataOrder(snapshot.inspectorMetadataOrder)
        metadataCustomRefreshFields = normalizedMetadataCustomRefreshFields(snapshot.metadataCustomRefreshFields)
        tagQuickNumberMap = normalizedTagQuickNumberMap(snapshot.tagQuickNumberMap)
        mainWindowWidth = snapshot.mainWindowWidth
        mainWindowHeight = snapshot.mainWindowHeight

        save()
    }

    func readMetadataPromptDocument() -> String {
        ensureMetadataPromptFileIfNeeded()
        return (try? String(contentsOf: metadataPromptFileURL, encoding: .utf8))
            ?? MetadataPromptBlueprint.default.toDocument()
    }

    func writeMetadataPromptDocument(_ text: String) {
        ensureMetadataPromptFileIfNeeded()
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = normalized.isEmpty ? MetadataPromptBlueprint.default.toDocument() : text
        do {
            try target.write(to: metadataPromptFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("写入提示词文件失败: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func writeImportCheckpoint() -> URL? {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let snapshot = exportCurrentSnapshot(includeSecrets: true)
            let data = try encoder.encode(snapshot)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let fileURL = storageDirectory.appendingPathComponent(
                "pre-import-settings-\(formatter.string(from: .now)).json",
                isDirectory: false
            )
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("写入设置导入快照失败: \(error.localizedDescription)")
            return nil
        }
    }

    func updatePapersStorageDirectory(to url: URL) {
        papersStorageDirectoryPath = url.standardizedFileURL.path
        updatePermissionState(for: url)
    }

    func updatePapersStorageDirectory(to url: URL, bookmarkData: Data?) {
        if let bookmarkData {
            papersStorageBookmarkData = bookmarkData
            beginSecurityScopedAccess(using: bookmarkData)
            save()
        } else {
            updatePermissionState(for: url)
        }
        papersStorageDirectoryPath = url.standardizedFileURL.path
    }

    static func defaultCitationTemplate(for preset: CitationPreset) -> CitationTemplatePair {
        switch preset {
        case .apa7:
            return CitationTemplatePair(
                inText: "({{apaInTextAuthors}}, {{year}})",
                reference: "{{apaReferenceAuthors}} ({{year}}). {{title}}. {{journal}}, {{volume}}({{number}}), {{pages}}. https://doi.org/{{doi}}"
            )
        case .gbt7714:
            return CitationTemplatePair(
                inText: "（{{author}}，{{year}}）",
                reference: "{{author}}. {{title}}[J]. {{journal}}, {{year}}, {{volume}}({{number}}): {{pages}}. DOI: {{doi}}"
            )
        case .mla9:
            return CitationTemplatePair(
                inText: "({{author}} {{page}})",
                reference: "{{author}}. \"{{title}}.\" {{journal}}, vol. {{volume}}, no. {{number}}, {{year}}, pp. {{pages}}. https://doi.org/{{doi}}"
            )
        case .chicago17:
            return CitationTemplatePair(
                inText: "({{author}} {{year}}, {{page}})",
                reference: "{{author}}. \"{{title}}.\" {{journal}} {{volume}}, no. {{number}} ({{year}}): {{pages}}. https://doi.org/{{doi}}"
            )
        case .custom:
            return CitationTemplatePair(inText: "", reference: "")
        }
    }

    private func load() {
        isLoadingSnapshot = true
        defer { isLoadingSnapshot = false }

        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: settingsFileURL.path),
               fileManager.fileExists(atPath: legacySettingsFileURL.path) {
                try? fileManager.copyItem(at: legacySettingsFileURL, to: settingsFileURL)
            }
            guard fileManager.fileExists(atPath: settingsFileURL.path) else {
                return
            }

            let data = try Data(contentsOf: settingsFileURL)
            if let snapshot = try? decoder.decode(AppSettingsSnapshot.self, from: data) {
                metadataAPIProvider = snapshot.metadataAPIProvider ?? Self.inferAPIProvider(from: snapshot.metadataAPIBaseURL)
                metadataAPIBaseURL = Self.normalizedAPIEndpointString(
                    provider: metadataAPIProvider,
                    rawEndpoint: snapshot.metadataAPIBaseURL
                )
                metadataAPIKey = snapshot.metadataAPIKey
                metadataModel = snapshot.metadataModel
                metadataThinkingMode = snapshot.metadataThinkingMode ?? .nonThinking
                pdf2zhEnvironmentKind = snapshot.pdf2zhEnvironmentKind ?? Self.defaultPDF2ZHEnvironmentKind
                pdf2zhEnvironmentName = snapshot.pdf2zhEnvironmentName ?? Self.defaultPDF2ZHEnvironmentName
                pdf2zhCustomActivationCommand = snapshot.pdf2zhCustomActivationCommand ?? ""
                metadataPromptTemplate = snapshot.metadataPromptTemplate ?? Self.defaultMetadataPromptTemplate
                migrateMetadataPromptTemplateIfNeeded()
                papersStorageDirectoryPath = snapshot.papersStorageDirectoryPath ?? Self.defaultPapersDirectoryPath
                papersStorageBookmarkData = snapshot.papersStorageBookmarkData
                citationPreset = snapshot.citationPreset
                inTextCitationTemplate = snapshot.inTextCitationTemplate
                referenceCitationTemplate = snapshot.referenceCitationTemplate
                migrateCitationTemplateIfNeeded()
                exportBibTeXFields = snapshot.exportBibTeXFields
                rowHeightScaleFactor = max(1, snapshot.rowHeightScaleFactor ?? 9)
                if let savedMultiplier = snapshot.tableRowHeightMultiplier, savedMultiplier > 0 {
                    tableRowHeightMultiplier = savedMultiplier
                } else if let legacyPreset = snapshot.tableRowHeightPreset {
                    tableRowHeightMultiplier = Double(legacyPreset.multiplier)
                } else {
                    tableRowHeightMultiplier = 1
                }
                recentReadingRange = snapshot.recentReadingRange ?? .twoDays
                zombiePapersThreshold = snapshot.zombiePapersThreshold ?? .oneMonth
                appLanguage = snapshot.appLanguage ?? .chinese
                mcpEnabled = snapshot.mcpEnabled ?? false
                mcpServerName = normalizedMCPServerName(snapshot.mcpServerName, fallback: Self.defaultMCPServerName)
                mcpServerHost = normalizedMCPServerHost(snapshot.mcpServerHost, fallback: Self.defaultMCPServerHost)
                mcpServerPort = normalizedMCPServerPort(snapshot.mcpServerPort, fallback: Self.defaultMCPServerPort)
                mcpServerPath = normalizedMCPServerPath(snapshot.mcpServerPath, fallback: Self.defaultMCPServerPath)
                mcpMaxContentLength = normalizedMCPInt(
                    snapshot.mcpMaxContentLength,
                    fallback: Self.defaultMCPMaxContentLength,
                    range: 500...100_000
                )
                mcpMaxAttachments = normalizedMCPInt(
                    snapshot.mcpMaxAttachments,
                    fallback: Self.defaultMCPMaxAttachments,
                    range: 1...100
                )
                mcpMaxNotes = normalizedMCPInt(
                    snapshot.mcpMaxNotes,
                    fallback: Self.defaultMCPMaxNotes,
                    range: 1...200
                )
                mcpKeywordLimit = normalizedMCPInt(
                    snapshot.mcpKeywordLimit,
                    fallback: Self.defaultMCPKeywordLimit,
                    range: 1...200
                )
                mcpSearchResultLimit = normalizedMCPInt(
                    snapshot.mcpSearchResultLimit,
                    fallback: Self.defaultMCPSearchResultLimit,
                    range: 1...500
                )
                mcpMaxNumericValues = normalizedMCPInt(
                    snapshot.mcpMaxNumericValues,
                    fallback: Self.defaultMCPMaxNumericValues,
                    range: 1...2_000
                )
                autoRenameImportedPDFFiles = snapshot.autoRenameImportedPDFFiles ?? true
                imageThumbnailMaxSizeMultiplier = normalizedImageThumbnailMaxSizeMultiplier(
                    snapshot.imageThumbnailMaxSizeMultiplier,
                    fallback: 0.5
                )
                paperTableColumnVisibility = snapshot.paperTableColumnVisibility ?? PaperTableColumnVisibility()
                paperTableColumnOrder = normalizedPaperTableColumnOrder(snapshot.paperTableColumnOrder)
                paperTableColumnWidths = normalizedPaperTableColumnWidths(snapshot.paperTableColumnWidths)
                inspectorMetadataOrder = normalizedInspectorMetadataOrder(snapshot.inspectorMetadataOrder)
                metadataCustomRefreshFields = normalizedMetadataCustomRefreshFields(snapshot.metadataCustomRefreshFields)
                tagQuickNumberMap = normalizedTagQuickNumberMap(snapshot.tagQuickNumberMap)
                mainWindowWidth = snapshot.mainWindowWidth
                mainWindowHeight = snapshot.mainWindowHeight
                return
            }

            if let legacy = try? decoder.decode(LegacySettingsSnapshot.self, from: data) {
                metadataAPIKey = legacy.siliconFlowAPIKey
                metadataModel = legacy.siliconFlowModel
                return
            }
        } catch {
            print("读取设置失败: \(error.localizedDescription)")
        }
    }

    private func save() {
        guard !isLoadingSnapshot else { return }

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            flushPendingSaveNow()
        }
    }

    private func flushPendingSaveNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        writeSettingsSnapshot()
    }

    private func writeSettingsSnapshot() {
        let perfStart = PerformanceMonitor.now()
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let snapshot = buildSnapshot(includeSecrets: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: settingsFileURL, options: .atomic)
            PerformanceMonitor.logElapsed(
                "SettingsStore.writeSettingsSnapshot",
                from: perfStart,
                thresholdMS: 8
            ) {
                "bytes=\(data.count)"
            }
        } catch {
            print("保存设置失败: \(error.localizedDescription)")
        }
    }

    private var storageDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Litrix", isDirectory: true)
    }

    private var legacyStorageDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PaperDock", isDirectory: true)
    }

    private var settingsFileURL: URL {
        storageDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    private var legacySettingsFileURL: URL {
        legacyStorageDirectory.appendingPathComponent("settings.json", isDirectory: false)
    }

    private func restorePapersDirectoryAccessIfPossible() {
        guard let papersStorageBookmarkData else {
            hasPapersStoragePermission = true
            return
        }
        beginSecurityScopedAccess(using: papersStorageBookmarkData)
    }

    private func beginSecurityScopedAccess(using bookmarkData: Data) {
        var bookmarkIsStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            hasPapersStoragePermission = false
            return
        }

        let started = url.startAccessingSecurityScopedResource()
        hasPapersStoragePermission = started || fileManager.isWritableFile(atPath: url.path)

        if started {
            activeSecurityScopedPapersURL?.stopAccessingSecurityScopedResource()
            activeSecurityScopedPapersURL = url
        }

        if bookmarkIsStale,
           let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            papersStorageBookmarkData = refreshed
            save()
        }
    }

    private func updatePermissionState(for url: URL) {
        let target = url.standardizedFileURL
        let writable = fileManager.isWritableFile(atPath: target.path)
            || fileManager.isWritableFile(atPath: target.deletingLastPathComponent().path)
        hasPapersStoragePermission = writable
    }

    private func migrateMetadataPromptTemplateIfNeeded() {
        let normalized = metadataPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            metadataPromptTemplate = Self.defaultMetadataPromptTemplate
            return
        }

        let appearsToBeLegacyDefault = normalized.contains(#""paperType":""}"#)
            && (!normalized.contains(#""rqs":"""#) || !normalized.contains("IF包括JCR分区"))

        if appearsToBeLegacyDefault {
            metadataPromptTemplate = Self.defaultMetadataPromptTemplate
        }
    }

    private func ensureMetadataPromptFileIfNeeded() {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: metadataPromptFileURL.path) {
                if let existing = try? String(contentsOf: metadataPromptFileURL, encoding: .utf8),
                   Self.appearsLegacyPromptBlueprintDocument(existing) {
                    try MetadataPromptBlueprint.default.toDocument().write(
                        to: metadataPromptFileURL,
                        atomically: true,
                        encoding: .utf8
                    )
                }
                return
            }

            let legacyPrompt = metadataPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            let seed: MetadataPromptBlueprint
            if let parsed = MetadataPromptBlueprint.fromDocument(legacyPrompt) {
                seed = parsed
            } else {
                seed = .default
            }

            try seed.toDocument().write(to: metadataPromptFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("创建提示词文件失败: \(error.localizedDescription)")
        }
    }

    private static func appearsLegacyPromptBlueprintDocument(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("你是文献元数据提取助手。你将收到“文件名”和“PDF 文本片段”。")
            && normalized.contains("只能基于输入文本提取信息，不确定时返回空字符串。")
            && normalized.contains("输出必须是可直接解析的 JSON。")
    }

    private func migrateCitationTemplateIfNeeded() {
        guard citationPreset == .apa7 else { return }
        let normalizedInText = inTextCitationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReference = referenceCitationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let appearsLegacyAPA =
            normalizedInText == "({{author}}, {{year}})"
            || normalizedReference.contains("{{author}}.")

        if appearsLegacyAPA {
            let template = Self.defaultCitationTemplate(for: .apa7)
            inTextCitationTemplate = template.inText
            referenceCitationTemplate = template.reference
        }
    }

    private static func inferAPIProvider(from endpoint: String) -> MetadataAPIProvider {
        let normalized = endpoint.lowercased()
        if normalized.contains("dashscope.aliyuncs.com") {
            return .aliyunDashScope
        }
        return .siliconFlow
    }

    private static func normalizedAPIEndpointString(
        provider: MetadataAPIProvider,
        rawEndpoint: String
    ) -> String {
        let trimmed = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var url = URL(string: trimmed) else {
            return provider.defaultEndpoint
        }

        let lowerPath = url.path.lowercased()
        if lowerPath.hasSuffix("/chat/completions") {
            return url.absoluteString
        }

        switch provider {
        case .siliconFlow:
            if lowerPath.hasSuffix("/v1") || lowerPath.hasSuffix("/v1/") || lowerPath.isEmpty || lowerPath == "/" {
                url.append(path: "chat/completions")
                return url.absoluteString
            }
        case .aliyunDashScope:
            if lowerPath.hasSuffix("/compatible-mode/v1")
                || lowerPath.hasSuffix("/compatible-mode/v1/")
                || lowerPath.hasSuffix("/v1")
                || lowerPath.hasSuffix("/v1/") {
                url.append(path: "chat/completions")
                return url.absoluteString
            }
        }

        return url.absoluteString
    }

    private func pdf2zhCondaProfilePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/miniconda3/etc/profile.d/conda.sh",
            "\(home)/anaconda3/etc/profile.d/conda.sh"
        ]
        return candidates.first(where: fileManager.fileExists(atPath:))
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func buildSnapshot(includeSecrets: Bool) -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            metadataAPIProvider: metadataAPIProvider,
            metadataAPIBaseURL: metadataAPIBaseURL,
            metadataAPIKey: includeSecrets ? metadataAPIKey : "",
            metadataModel: metadataModel,
            metadataThinkingMode: metadataThinkingMode,
            pdf2zhEnvironmentKind: pdf2zhEnvironmentKind,
            pdf2zhEnvironmentName: pdf2zhEnvironmentName,
            pdf2zhCustomActivationCommand: pdf2zhCustomActivationCommand,
            metadataPromptTemplate: metadataPromptTemplate,
            papersStorageDirectoryPath: papersStorageDirectoryPath,
            papersStorageBookmarkData: includeSecrets ? papersStorageBookmarkData : nil,
            citationPreset: citationPreset,
            inTextCitationTemplate: inTextCitationTemplate,
            referenceCitationTemplate: referenceCitationTemplate,
            exportBibTeXFields: exportBibTeXFields,
            tableRowHeightPreset: nil,
            rowHeightScaleFactor: rowHeightScaleFactor,
            tableRowHeightMultiplier: tableRowHeightMultiplier,
            recentReadingRange: recentReadingRange,
            zombiePapersThreshold: zombiePapersThreshold,
            appLanguage: appLanguage,
            mcpEnabled: mcpEnabled,
            mcpServerName: resolvedMCPServerName,
            mcpServerHost: resolvedMCPServerHost,
            mcpServerPort: resolvedMCPServerPort,
            mcpServerPath: resolvedMCPServerPath,
            mcpMaxContentLength: normalizedMCPInt(mcpMaxContentLength, fallback: Self.defaultMCPMaxContentLength, range: 500...100_000),
            mcpMaxAttachments: normalizedMCPInt(mcpMaxAttachments, fallback: Self.defaultMCPMaxAttachments, range: 1...100),
            mcpMaxNotes: normalizedMCPInt(mcpMaxNotes, fallback: Self.defaultMCPMaxNotes, range: 1...200),
            mcpKeywordLimit: normalizedMCPInt(mcpKeywordLimit, fallback: Self.defaultMCPKeywordLimit, range: 1...200),
            mcpSearchResultLimit: normalizedMCPInt(mcpSearchResultLimit, fallback: Self.defaultMCPSearchResultLimit, range: 1...500),
            mcpMaxNumericValues: normalizedMCPInt(mcpMaxNumericValues, fallback: Self.defaultMCPMaxNumericValues, range: 1...2_000),
            autoRenameImportedPDFFiles: autoRenameImportedPDFFiles,
            imageThumbnailMaxSizeMultiplier: normalizedImageThumbnailMaxSizeMultiplier(
                imageThumbnailMaxSizeMultiplier,
                fallback: 0.5
            ),
            paperTableColumnVisibility: paperTableColumnVisibility,
            paperTableColumnOrder: normalizedPaperTableColumnOrder(paperTableColumnOrder),
            paperTableColumnWidths: normalizedPaperTableColumnWidths(paperTableColumnWidths),
            inspectorMetadataOrder: normalizedInspectorMetadataOrder(inspectorMetadataOrder),
            metadataCustomRefreshFields: normalizedMetadataCustomRefreshFields(metadataCustomRefreshFields),
            tagQuickNumberMap: normalizedTagQuickNumberMap(tagQuickNumberMap),
            mainWindowWidth: mainWindowWidth,
            mainWindowHeight: mainWindowHeight
        )
    }

    private func normalizedInspectorMetadataOrder(_ order: [InspectorMetadataField]?) -> [InspectorMetadataField] {
        let base = order ?? InspectorMetadataField.defaultOrder
        var result: [InspectorMetadataField] = []
        for field in base where !result.contains(field) {
            result.append(field)
        }
        for field in InspectorMetadataField.defaultOrder where !result.contains(field) {
            result.append(field)
        }
        return result
    }

    private func normalizedPaperTableColumnOrder(_ order: [PaperTableColumn]?) -> [PaperTableColumn] {
        let base = order ?? PaperTableColumn.defaultOrder
        var result: [PaperTableColumn] = []
        for column in base where !result.contains(column) {
            result.append(column)
        }
        for column in PaperTableColumn.defaultOrder where !result.contains(column) {
            result.append(column)
        }
        return result
    }

    private func normalizedPaperTableColumnWidths(_ widths: [String: Double]?) -> [String: Double] {
        guard let widths else { return [:] }

        var result: [String: Double] = [:]
        for column in PaperTableColumn.allCases {
            guard let width = widths[column.rawValue], width.isFinite, width > 1 else { continue }
            result[column.rawValue] = max(36, width)
        }
        return result
    }

    private func normalizedMetadataCustomRefreshFields(_ fields: [MetadataField]?) -> [MetadataField] {
        guard let fields else { return MetadataField.allCases }
        var result: [MetadataField] = []
        for field in fields where !result.contains(field) {
            result.append(field)
        }
        return result
    }

    private func normalizedTagQuickNumberMap(_ map: [String: Int]?) -> [String: Int] {
        guard let map else { return [:] }
        var result: [String: Int] = [:]
        var usedNumbers: Set<Int> = []
        for (tag, number) in map {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, (1...9).contains(number), !usedNumbers.contains(number) else {
                continue
            }
            result[trimmed] = number
            usedNumbers.insert(number)
        }
        return result
    }

    private func normalizedMCPServerName(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultMCPServerName : trimmed
    }

    private func normalizedMCPServerHost(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultMCPServerHost : trimmed
    }

    private func normalizedMCPServerPort(_ value: Int?, fallback: Int) -> Int {
        let candidate = value ?? fallback
        if (1...65_535).contains(candidate) {
            return candidate
        }
        return min(max(candidate, 1), 65_535)
    }

    private func normalizedMCPServerPath(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultMCPServerPath : trimmed
        return resolved.hasPrefix("/") ? resolved : "/\(resolved)"
    }

    private func normalizedMCPInt(
        _ value: Int?,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        let candidate = value ?? fallback
        if range.contains(candidate) {
            return candidate
        }
        return min(max(candidate, range.lowerBound), range.upperBound)
    }

    private func normalizedImageThumbnailMaxSizeMultiplier(
        _ value: Double?,
        fallback: Double
    ) -> Double {
        let candidate = value ?? fallback
        guard candidate.isFinite else { return 0.5 }
        return min(max(candidate, 0.1), 4)
    }
}
