import Foundation
import PDFKit

struct PDFTranslationBlock: Identifiable, Codable, Hashable {
    var id: Int
    var source: String
    var target: String
}

struct MetadataSuggestion: Codable {
    var title: String
    var englishTitle: String
    var authors: String
    var authorsEnglish: String
    var year: String
    var source: String
    var doi: String
    var abstractText: String
    var chineseAbstract: String
    var volume: String
    var issue: String
    var pages: String
    var paperType: String
    var rqs: String
    var conclusion: String
    var results: String
    var category: String
    var impactFactor: String
    var samples: String
    var participantType: String
    var variables: String
    var dataCollection: String
    var dataAnalysis: String
    var methodology: String
    var theoreticalFoundation: String
    var educationalLevel: String
    var country: String
    var keywords: String
    var limitations: String

    init(
        title: String = "",
        englishTitle: String = "",
        authors: String = "",
        authorsEnglish: String = "",
        year: String = "",
        source: String = "",
        doi: String = "",
        abstractText: String = "",
        chineseAbstract: String = "",
        volume: String = "",
        issue: String = "",
        pages: String = "",
        paperType: String = "",
        rqs: String = "",
        conclusion: String = "",
        results: String = "",
        category: String = "",
        impactFactor: String = "",
        samples: String = "",
        participantType: String = "",
        variables: String = "",
        dataCollection: String = "",
        dataAnalysis: String = "",
        methodology: String = "",
        theoreticalFoundation: String = "",
        educationalLevel: String = "",
        country: String = "",
        keywords: String = "",
        limitations: String = ""
    ) {
        self.title = title
        self.englishTitle = englishTitle
        self.authors = authors
        self.authorsEnglish = authorsEnglish
        self.year = year
        self.source = source
        self.doi = doi
        self.abstractText = abstractText
        self.chineseAbstract = chineseAbstract
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.paperType = paperType
        self.rqs = rqs
        self.conclusion = conclusion
        self.results = results
        self.category = category
        self.impactFactor = impactFactor
        self.samples = samples
        self.participantType = participantType
        self.variables = variables
        self.dataCollection = dataCollection
        self.dataAnalysis = dataAnalysis
        self.methodology = methodology
        self.theoreticalFoundation = theoreticalFoundation
        self.educationalLevel = educationalLevel
        self.country = country
        self.keywords = keywords
        self.limitations = limitations
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case englishTitle
        case authors
        case authorsEnglish
        case year
        case source
        case doi
        case abstractText
        case chineseAbstract
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            englishTitle: try container.decodeIfPresent(String.self, forKey: .englishTitle) ?? "",
            authors: try container.decodeIfPresent(String.self, forKey: .authors) ?? "",
            authorsEnglish: try container.decodeIfPresent(String.self, forKey: .authorsEnglish) ?? "",
            year: try container.decodeIfPresent(String.self, forKey: .year) ?? "",
            source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
            doi: try container.decodeIfPresent(String.self, forKey: .doi) ?? "",
            abstractText: try container.decodeIfPresent(String.self, forKey: .abstractText) ?? "",
            chineseAbstract: try container.decodeIfPresent(String.self, forKey: .chineseAbstract) ?? "",
            volume: try container.decodeIfPresent(String.self, forKey: .volume) ?? "",
            issue: try container.decodeIfPresent(String.self, forKey: .issue) ?? "",
            pages: try container.decodeIfPresent(String.self, forKey: .pages) ?? "",
            paperType: try container.decodeIfPresent(String.self, forKey: .paperType) ?? "",
            rqs: try container.decodeIfPresent(String.self, forKey: .rqs) ?? "",
            conclusion: try container.decodeIfPresent(String.self, forKey: .conclusion) ?? "",
            results: try container.decodeIfPresent(String.self, forKey: .results) ?? "",
            category: try container.decodeIfPresent(String.self, forKey: .category) ?? "",
            impactFactor: try container.decodeIfPresent(String.self, forKey: .impactFactor) ?? "",
            samples: try container.decodeIfPresent(String.self, forKey: .samples) ?? "",
            participantType: try container.decodeIfPresent(String.self, forKey: .participantType) ?? "",
            variables: try container.decodeIfPresent(String.self, forKey: .variables) ?? "",
            dataCollection: try container.decodeIfPresent(String.self, forKey: .dataCollection) ?? "",
            dataAnalysis: try container.decodeIfPresent(String.self, forKey: .dataAnalysis) ?? "",
            methodology: try container.decodeIfPresent(String.self, forKey: .methodology) ?? "",
            theoreticalFoundation: try container.decodeIfPresent(String.self, forKey: .theoreticalFoundation) ?? "",
            educationalLevel: try container.decodeIfPresent(String.self, forKey: .educationalLevel) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            keywords: try container.decodeIfPresent(String.self, forKey: .keywords) ?? "",
            limitations: try container.decodeIfPresent(String.self, forKey: .limitations) ?? ""
        )
    }
}

enum MetadataEnrichmentError: LocalizedError {
    case missingAPIKey
    case missingModel
    case missingPDF
    case requestFailed(String)
    case invalidResponse
    case unparseableResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有配置 API Key，请先打开设置填写。"
        case .missingModel:
            return "还没有配置模型名称，请先打开设置填写。"
        case .missingPDF:
            return "没有可用于分析的附件或条目信息。"
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "元数据服务返回的内容无法解析。"
        case .unparseableResponse:
            return "元数据服务返回的内容无法解析。"
        }
    }

    var rawReturnedContent: String? {
        switch self {
        case .unparseableResponse(let content):
            return content
        default:
            return nil
        }
    }
}

enum MetadataEnrichmentService {
    private static let transientHTTPStatusCodes: Set<Int> = [408, 409, 425, 429, 500, 502, 503, 504]
    private static let maxMetadataRequestAttempts = 8
    private static let metadataRetryBaseDelay: TimeInterval = 20
    private static let metadataRetryMaxDelay: TimeInterval = 180

    private static let fallbackPromptTemplate = """
    你是文献元数据提取助手。你将收到“文件名”和“文献文本片段/已有条目信息”。
    你的任务是提取和总结元数据（优先提取），并且只输出一个 JSON 对象，不允许输出 Markdown、解释或代码块。
    JSON 键必须严格为（键名不可增删、不可改名）：
    {"title":"","englishTitle":"","authors":"","authorsEnglish":"","year":"","source":"","doi":"","abstractText":"","chineseAbstract":"","volume":"","issue":"","pages":"","paperType":"","rqs":"","conclusion":"","results":"","category":"","impactFactor":"","samples":"","participantType":"","variables":"","dataCollection":"","dataAnalysis":"","methodology":"","theoreticalFoundation":"","educationalLevel":"","country":"","keywords":"","limitations":""}

    规则：
    1. 只能基于输入内容提取；不确定时填空字符串。
    2. authors 使用单个字符串，多个作者用 ", " 连接。
    2.1 englishTitle：从文献中提取文献的英语标题，优先从原文提取，原文不存在时，翻译中文标题。
    2.2 authorsEnglish：从文献中提取文献的所有作者的英语姓名，用 ", " 分割，优先从原文提取，原文不存在时，翻译中文姓名。
    3. year 优先返回四位数字，不确定则留空。
    4. abstractText 保留原文摘要语言：原文是中文就中文，原文是英文就英文，不要为了 abstractText 翻译成英文。chineseAbstract 必须输出中文摘要；若原文摘要已是中文，可复用或整理为中文；若原文是英文，翻译/概述成中文。
    4.1 keywords 用英文逗号分隔（例如 "teacher burnout, workload, wellbeing"）。
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
    25. 字段值中若需要引用英文短语，优先使用中文弯引号 “ ”；不要在字符串内部直接输出未转义的英文双引号。
    26. 若必须保留英文双引号，必须写成 JSON 转义形式 \\\"；字段值中的换行必须写成 \\n，不要在字符串内部输出真实换行。
    27. 所有字段必须输出纯文本；删除 HTML/XML 标签和上标标记，例如 <scp>Al</scp> 应输出为 Al。
    """

    static func checkConnection(
        apiProvider: MetadataAPIProvider,
        apiEndpoint: URL,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool
    ) async throws -> String {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw MetadataEnrichmentError.missingAPIKey
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedModel.isEmpty else {
            throw MetadataEnrichmentError.missingModel
        }

        let payload = ChatRequest(
            apiProvider: apiProvider,
            model: resolvedModel,
            enableThinking: thinkingEnabled,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "You are a connection check assistant."
                ),
                ChatMessage(
                    role: "user",
                    content: "Return one short sentence containing the word CONNECTED."
                )
            ]
        )

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await performRequestWithRetry(
            request,
            maxAttempts: 3,
            baseDelay: 5,
            maxDelay: 20
        )

        if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
           let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            throw MetadataEnrichmentError.invalidResponse
        }
        return raw
    }

    static func enrichMetadata(
        apiProvider: MetadataAPIProvider,
        pdfURL: URL?,
        originalFileName: String?,
        fallbackText: String?,
        apiEndpoint: URL,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool,
        promptBlueprint: MetadataPromptBlueprint,
        requestedFields: [MetadataField]
    ) async throws -> MetadataSuggestion {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw MetadataEnrichmentError.missingAPIKey
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedModel.isEmpty else {
            throw MetadataEnrichmentError.missingModel
        }

        let documentExcerpt = pdfURL.map { extractDocumentExcerpt(from: $0) } ?? ""
        let fallbackExcerpt = normalizedExcerpt(fallbackText ?? "", charLimit: 2500)
        let sourceSections = [
            documentExcerpt.isEmpty ? nil : "文献文本片段：\n\(documentExcerpt)",
            fallbackExcerpt.isEmpty ? nil : "已有条目信息：\n\(fallbackExcerpt)"
        ]
        .compactMap { $0 }

        guard !sourceSections.isEmpty else {
            throw MetadataEnrichmentError.missingPDF
        }

        let targetFields = requestedFields.isEmpty ? MetadataField.allCases : requestedFields
        let resolvedPrompt = promptBlueprint.composedPrompt(for: targetFields)
        let fileName = originalFileName ?? pdfURL?.lastPathComponent ?? "无附件条目"

        let payload = ChatRequest(
            apiProvider: apiProvider,
            model: resolvedModel,
            enableThinking: thinkingEnabled,
            messages: [
                ChatMessage(
                    role: "system",
                    content: resolvedPrompt
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    文件名：\(fileName)

                    \(sourceSections.joined(separator: "\n\n"))
                    """
                )
            ]
        )

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await performRequestWithRetry(
            request,
            maxAttempts: maxMetadataRequestAttempts,
            baseDelay: metadataRetryBaseDelay,
            maxDelay: metadataRetryMaxDelay
        )
        let response: ChatResponse
        do {
            response = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            let rawResponse = rawResponseText(from: data)
            guard !rawResponse.isEmpty else {
                throw MetadataEnrichmentError.invalidResponse
            }
            throw MetadataEnrichmentError.unparseableResponse(rawResponse)
        }

        guard let content = response.choices.first?.message.content else {
            let rawResponse = rawResponseText(from: data)
            guard !rawResponse.isEmpty else {
                throw MetadataEnrichmentError.invalidResponse
            }
            throw MetadataEnrichmentError.unparseableResponse(rawResponse)
        }

        if let direct = tryDecodeSuggestion(from: content) {
            return direct
        }

        if let jsonRange = content.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            let json = String(content[jsonRange])
            if let extracted = tryDecodeSuggestion(from: json) {
                return extracted
            }
        }

        throw MetadataEnrichmentError.unparseableResponse(content)
    }

    static func translateTextBlocks(
        apiProvider: MetadataAPIProvider,
        apiEndpoint: URL,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool,
        blocks: [String]
    ) async throws -> [PDFTranslationBlock] {
        let resolvedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedKey.isEmpty else {
            throw MetadataEnrichmentError.missingAPIKey
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedModel.isEmpty else {
            throw MetadataEnrichmentError.missingModel
        }

        let normalizedBlocks = blocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedBlocks.isEmpty else {
            return []
        }

        let requestBody: [String: Any] = ["blocks": normalizedBlocks]
        let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [.prettyPrinted, .sortedKeys])
        let requestJSON = String(data: requestData, encoding: .utf8) ?? "{\"blocks\":[]}"

        let payload = ChatRequest(
            apiProvider: apiProvider,
            model: resolvedModel,
            enableThinking: thinkingEnabled,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是学术论文翻译助手。请将输入的英文段落翻译为简体中文。
                    你只能返回一个 JSON 对象，禁止输出解释和 Markdown。
                    输出格式必须是：
                    {"translations":[{"index":0,"target":""}]}

                    规则：
                    1. 必须保留 index。
                    2. 专业术语译文尽量准确，必要时可保留英文原词。
                    3. 不得省略任何段落。
                    4. 输出必须是可直接解析的合法 JSON。
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    请翻译下面 JSON 里的 blocks：
                    \(requestJSON)
                    """
                )
            ]
        )

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await performRequestWithRetry(
            request,
            maxAttempts: 6,
            baseDelay: 8,
            maxDelay: 40
        )
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw MetadataEnrichmentError.invalidResponse
        }

        guard let translated = tryDecodeTranslations(from: content, sourceBlocks: normalizedBlocks) else {
            throw MetadataEnrichmentError.invalidResponse
        }
        return translated
    }

    static func translateAbstract(
        apiProvider: MetadataAPIProvider,
        apiEndpoint: URL,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool,
        text: String,
        targetLanguage: AbstractDisplayLanguage
    ) async throws -> String {
        let resolvedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedKey.isEmpty else {
            throw MetadataEnrichmentError.missingAPIKey
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedModel.isEmpty else {
            throw MetadataEnrichmentError.missingModel
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw MetadataEnrichmentError.invalidResponse
        }

        let targetDescription: String
        switch targetLanguage {
        case .chinese:
            targetDescription = "简体中文"
        case .english:
            targetDescription = "英文"
        case .original:
            return normalizedText
        }

        let payload = ChatRequest(
            apiProvider: apiProvider,
            model: resolvedModel,
            enableThinking: thinkingEnabled,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是学术摘要翻译助手。请将用户提供的摘要准确翻译为\(targetDescription)。
                    只返回译文正文，不要输出标题、说明、项目符号、代码块或引号。
                    保留原有段落结构；术语以学术表达为准。
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: normalizedText
                )
            ]
        )

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await performRequestWithRetry(
            request,
            maxAttempts: 4,
            baseDelay: 6,
            maxDelay: 30
        )

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw MetadataEnrichmentError.invalidResponse
        }
        return content
    }

    static func translateTitle(
        apiProvider: MetadataAPIProvider,
        apiEndpoint: URL,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool,
        text: String,
        targetLanguage: AbstractDisplayLanguage
    ) async throws -> String {
        let resolvedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedKey.isEmpty else {
            throw MetadataEnrichmentError.missingAPIKey
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedModel.isEmpty else {
            throw MetadataEnrichmentError.missingModel
        }

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw MetadataEnrichmentError.invalidResponse
        }

        let targetDescription: String
        switch targetLanguage {
        case .chinese:
            targetDescription = "简体中文"
        case .english:
            targetDescription = "英文"
        case .original:
            return normalizedText
        }

        let payload = ChatRequest(
            apiProvider: apiProvider,
            model: resolvedModel,
            enableThinking: thinkingEnabled,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    你是学术标题翻译助手。请将用户提供的论文标题准确翻译为\(targetDescription)。
                    只返回译文标题，不要输出说明、项目符号、代码块或引号。
                    保留专有名词和缩写的学术表达。
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: normalizedText
                )
            ]
        )

        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await performRequestWithRetry(
            request,
            maxAttempts: 4,
            baseDelay: 6,
            maxDelay: 30
        )

        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw MetadataEnrichmentError.invalidResponse
        }
        return MetadataValueNormalizer.normalizeTitle(content)
    }

    private static func tryDecodeSuggestion(from jsonString: String) -> MetadataSuggestion? {
        if let decoded = decodeSuggestionJSON(jsonString) {
            return decoded.normalized()
        }

        guard let repaired = repairJSONStringContent(jsonString),
              repaired != jsonString else {
            return nil
        }

        return decodeSuggestionJSON(repaired)?.normalized()
    }

    private static func decodeSuggestionJSON(_ jsonString: String) -> MetadataSuggestion? {
        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MetadataSuggestion.self, from: data)
    }

    private enum JSONStringContext {
        case key
        case value
        case unknown
    }

    private static func repairJSONStringContent(_ jsonString: String) -> String? {
        let characters = Array(jsonString)
        guard !characters.isEmpty else { return nil }

        var output = ""
        output.reserveCapacity(jsonString.count + 16)

        var isInString = false
        var isEscaped = false
        var stringContext: JSONStringContext = .unknown
        var didRepair = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isInString {
                if isEscaped {
                    output.append(character)
                    isEscaped = false
                    index += 1
                    continue
                }

                if character == "\\" {
                    output.append(character)
                    isEscaped = true
                    index += 1
                    continue
                }

                if character == "\"" {
                    if shouldCloseJSONString(in: characters, quoteIndex: index, context: stringContext) {
                        output.append(character)
                        isInString = false
                        stringContext = .unknown
                    } else {
                        output.append("\\\"")
                        didRepair = true
                    }
                    index += 1
                    continue
                }

                if character == "\n" {
                    output.append("\\n")
                    didRepair = true
                    index += 1
                    continue
                }

                if character == "\r" {
                    output.append("\\n")
                    didRepair = true
                    if index + 1 < characters.count, characters[index + 1] == "\n" {
                        index += 1
                    }
                    index += 1
                    continue
                }

                if character == "\t" {
                    output.append("\\t")
                    didRepair = true
                    index += 1
                    continue
                }

                output.append(character)
                index += 1
                continue
            }

            if character == "\"" {
                isInString = true
                isEscaped = false
                stringContext = contextForOpeningJSONString(in: characters, quoteIndex: index)
            }

            output.append(character)
            index += 1
        }

        return didRepair ? output : nil
    }

    private static func contextForOpeningJSONString(
        in characters: [Character],
        quoteIndex: Int
    ) -> JSONStringContext {
        guard let previousIndex = previousNonWhitespaceIndex(in: characters, before: quoteIndex) else {
            return .unknown
        }

        switch characters[previousIndex] {
        case ":":
            return .value
        case "{", ",":
            return .key
        case "[":
            return .value
        default:
            return .unknown
        }
    }

    private static func shouldCloseJSONString(
        in characters: [Character],
        quoteIndex: Int,
        context: JSONStringContext
    ) -> Bool {
        guard let nextIndex = nextNonWhitespaceIndex(in: characters, after: quoteIndex) else {
            return context != .key
        }

        let nextCharacter = characters[nextIndex]

        switch context {
        case .key:
            return nextCharacter == ":"
        case .value:
            return nextCharacter == "}"
                || nextCharacter == "]"
                || (nextCharacter == "," && commaLooksLikeValueSeparator(in: characters, commaIndex: nextIndex))
        case .unknown:
            return nextCharacter == ":"
                || nextCharacter == "}"
                || nextCharacter == "]"
                || (nextCharacter == "," && commaLooksLikeValueSeparator(in: characters, commaIndex: nextIndex))
        }
    }

    private static func commaLooksLikeValueSeparator(
        in characters: [Character],
        commaIndex: Int
    ) -> Bool {
        guard let nextIndex = nextNonWhitespaceIndex(in: characters, after: commaIndex),
              characters[nextIndex] == "\"" else {
            return false
        }

        return quotedStringLooksLikeObjectKey(in: characters, startIndex: nextIndex)
    }

    private static func quotedStringLooksLikeObjectKey(
        in characters: [Character],
        startIndex: Int
    ) -> Bool {
        guard startIndex < characters.count, characters[startIndex] == "\"" else {
            return false
        }

        var isEscaped = false
        var index = startIndex + 1
        while index < characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
                index += 1
                continue
            }

            if character == "\\" {
                isEscaped = true
                index += 1
                continue
            }

            if character == "\"" {
                guard let afterQuoteIndex = nextNonWhitespaceIndex(in: characters, after: index) else {
                    return false
                }
                return characters[afterQuoteIndex] == ":"
            }

            index += 1
        }

        return false
    }

    private static func previousNonWhitespaceIndex(
        in characters: [Character],
        before index: Int
    ) -> Int? {
        guard index > 0 else { return nil }

        var currentIndex = index - 1
        while currentIndex >= 0 {
            if !isJSONWhitespace(characters[currentIndex]) {
                return currentIndex
            }

            if currentIndex == 0 {
                return nil
            }
            currentIndex -= 1
        }

        return nil
    }

    private static func nextNonWhitespaceIndex(
        in characters: [Character],
        after index: Int
    ) -> Int? {
        var currentIndex = index + 1
        while currentIndex < characters.count {
            if !isJSONWhitespace(characters[currentIndex]) {
                return currentIndex
            }
            currentIndex += 1
        }

        return nil
    }

    private static func isJSONWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\n" || character == "\r" || character == "\t"
    }

    private static func tryDecodeTranslations(
        from rawText: String,
        sourceBlocks: [String]
    ) -> [PDFTranslationBlock]? {
        if let direct = decodeTranslationsJSON(rawText, sourceBlocks: sourceBlocks) {
            return direct
        }

        if let jsonRange = rawText.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            let json = String(rawText[jsonRange])
            if let extracted = decodeTranslationsJSON(json, sourceBlocks: sourceBlocks) {
                return extracted
            }
        }

        return nil
    }

    private static func decodeTranslationsJSON(
        _ json: String,
        sourceBlocks: [String]
    ) -> [PDFTranslationBlock]? {
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(PDFTranslationResponse.self, from: data) else {
            return nil
        }

        var targetByIndex: [Int: String] = [:]
        for item in response.translations {
            if let index = item.index,
               (0..<sourceBlocks.count).contains(index) {
                let normalized = item.target.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    targetByIndex[index] = item.target
                }
            }
        }

        return sourceBlocks.enumerated().map { index, source in
            let candidate = targetByIndex[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let target = candidate.isEmpty ? source : candidate
            return PDFTranslationBlock(
                id: index,
                source: source,
                target: target
            )
        }
    }

    private static func performRequestWithRetry(
        _ request: URLRequest,
        maxAttempts: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval
    ) async throws -> Data {
        let attempts = max(1, maxAttempts)

        for attempt in 0..<attempts {
            try Task.checkCancellation()

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MetadataEnrichmentError.requestFailed("HTTP 响应无效。")
                }

                let statusCode = httpResponse.statusCode
                if (200...299).contains(statusCode) {
                    return data
                }

                if transientHTTPStatusCodes.contains(statusCode), attempt < attempts - 1 {
                    let delay = retryDelay(
                        forAttempt: attempt,
                        statusCode: statusCode,
                        response: httpResponse,
                        baseDelay: baseDelay,
                        maxDelay: maxDelay
                    )
                    try await sleep(seconds: delay)
                    continue
                }

                throw MetadataEnrichmentError.requestFailed("HTTP \(statusCode)\(bodySnippet(from: data))")
            } catch {
                if error is CancellationError {
                    throw error
                }

                if attempt < attempts - 1 {
                    let delay = retryDelay(
                        forAttempt: attempt,
                        statusCode: nil,
                        response: nil,
                        baseDelay: baseDelay,
                        maxDelay: maxDelay
                    )
                    try await sleep(seconds: delay)
                    continue
                }

                if let typedError = error as? MetadataEnrichmentError {
                    throw typedError
                }

                throw MetadataEnrichmentError.requestFailed(error.localizedDescription)
            }
        }

        throw MetadataEnrichmentError.requestFailed("请求失败，请稍后重试。")
    }

    private static func retryDelay(
        forAttempt attempt: Int,
        statusCode: Int?,
        response: HTTPURLResponse?,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval
    ) -> TimeInterval {
        if let response,
           let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let parsed = parseRetryAfter(retryAfter) {
            return min(max(parsed, 1), maxDelay)
        }

        let requestBaseDelay = statusCode == 429 ? max(baseDelay, 20) : max(baseDelay, 1)
        let exponential = requestBaseDelay * pow(2, Double(attempt))
        let jitter = Double.random(in: 0...2)
        return min(exponential + jitter, maxDelay)
    }

    private static func parseRetryAfter(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(trimmed), seconds.isFinite, seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"

        guard let date = formatter.date(from: trimmed) else {
            return nil
        }
        return max(date.timeIntervalSinceNow, 0)
    }

    private static func bodySnippet(from data: Data) -> String {
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? "" : "\n\(String(body.prefix(600)))"
    }

    private static func rawResponseText(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func sleep(seconds: TimeInterval) async throws {
        let clamped = max(seconds, 0)
        let nanoseconds = UInt64(clamped * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func extractDocumentExcerpt(from url: URL, charLimit: Int = 7000) -> String {
        let fileExtension = url.pathExtension.lowercased()
        let extracted: String

        switch fileExtension {
        case "pdf":
            extracted = extractPDFExcerpt(from: url, charLimit: charLimit)
        case "txt", "md", "csv":
            extracted = plainText(from: url)
        case "html", "htm":
            extracted = stripMarkup(from: plainText(from: url))
        case "rtf", "doc", "docx":
            extracted = runProcess("/usr/bin/textutil", arguments: ["-convert", "txt", "-stdout", url.path]) ?? ""
        case "epub":
            let epubText = runProcess(
                "/usr/bin/unzip",
                arguments: ["-p", url.path, "*.xhtml", "*.html", "*.htm", "*.opf"]
            ) ?? ""
            extracted = stripMarkup(from: epubText)
        case "mobi":
            extracted = runProcess("/usr/bin/strings", arguments: [url.path]) ?? ""
        default:
            extracted = runProcess("/usr/bin/textutil", arguments: ["-convert", "txt", "-stdout", url.path])
                ?? runProcess("/usr/bin/strings", arguments: [url.path])
                ?? plainText(from: url)
        }

        return normalizedExcerpt(extracted, charLimit: charLimit)
    }

    private static func extractPDFExcerpt(from url: URL, pageLimit: Int = 5, charLimit: Int = 7000) -> String {
        guard let document = PDFDocument(url: url) else {
            return ""
        }

        var chunks: [String] = []
        let upperBound = min(document.pageCount, pageLimit)
        for index in 0..<upperBound {
            guard let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                continue
            }
            chunks.append(text)
        }

        let merged = chunks.joined(separator: "\n\n")
        return normalizedExcerpt(merged, charLimit: charLimit)
    }

    private static func plainText(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let unicode = String(data: data, encoding: .unicode) {
            return unicode
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func stripMarkup(from text: String) -> String {
        text
            .replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func normalizedExcerpt(_ text: String, charLimit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(charLimit))
    }

    private static func runProcess(_ executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath, isDirectory: false)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct PDFTranslationResponse: Codable {
    struct TranslationItem: Codable {
        var index: Int?
        var target: String
    }

    var translations: [TranslationItem]
}

private struct ChatRequest: Encodable {
    var apiProvider: MetadataAPIProvider
    var model: String
    var enableThinking: Bool?
    var messages: [ChatMessage]
    var extraBody: ChatExtraBody?

    enum CodingKeys: String, CodingKey {
        case model
        case enableThinking = "enable_thinking"
        case messages
        case extraBody = "extra_body"
    }

    init(apiProvider: MetadataAPIProvider, model: String, enableThinking: Bool?, messages: [ChatMessage]) {
        self.apiProvider = apiProvider
        self.model = model
        self.enableThinking = enableThinking
        self.messages = messages
        switch apiProvider {
        case .siliconFlow:
            self.extraBody = nil
        case .aliyunDashScope:
            self.extraBody = ChatExtraBody(enableThinking: enableThinking)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)

        switch apiProvider {
        case .siliconFlow:
            try container.encodeIfPresent(enableThinking, forKey: .enableThinking)
        case .aliyunDashScope:
            try container.encodeIfPresent(extraBody, forKey: .extraBody)
        }
    }
}

private struct ChatExtraBody: Codable {
    var enableThinking: Bool?

    enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var role: String
            var content: String
        }

        var message: Message
    }

    var choices: [Choice]
}
