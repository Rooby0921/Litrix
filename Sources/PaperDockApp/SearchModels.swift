import Foundation

enum AdvancedSearchMatchMode: String, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .any:
            return "Any"
        }
    }

    func title(for language: AppLanguage) -> String {
        guard language == .chinese else { return title }

        switch self {
        case .all:
            return "全部"
        case .any:
            return "任意"
        }
    }
}

enum AdvancedSearchField: String, CaseIterable, Identifiable {
    case title
    case englishTitle
    case authors
    case authorsEnglish
    case source
    case year
    case doi
    case abstractText
    case chineseAbstract
    case volume
    case issue
    case pages
    case paperType
    case notes
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
    case webPageURL
    case tags
    case collections
    case attachmentStatus
    case fullText  // Extract and search within PDF body text via PDFKit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .englishTitle:
            return "English Title"
        case .authors:
            return "Authors"
        case .authorsEnglish:
            return "Authors (English)"
        case .source:
            return "Source"
        case .year:
            return "Year"
        case .doi:
            return "DOI"
        case .abstractText:
            return "Abstract"
        case .chineseAbstract:
            return "Chinese Abstract"
        case .volume:
            return "Volume"
        case .issue:
            return "Issue"
        case .pages:
            return "Pages"
        case .paperType:
            return "Paper Type"
        case .notes:
            return "Note"
        case .rqs:
            return "RQs"
        case .conclusion:
            return "Conclusion"
        case .results:
            return "Results"
        case .category:
            return "Category"
        case .impactFactor:
            return "IF"
        case .samples:
            return "Samples"
        case .participantType:
            return "Participant Type"
        case .variables:
            return "Variables"
        case .dataCollection:
            return "Data Collection"
        case .dataAnalysis:
            return "Data Analysis"
        case .methodology:
            return "Methodology"
        case .theoreticalFoundation:
            return "Theoretical Foundation"
        case .educationalLevel:
            return "Educational Level"
        case .country:
            return "Country"
        case .keywords:
            return "Keywords"
        case .limitations:
            return "Limitations"
        case .webPageURL:
            return "Web Link"
        case .tags:
            return "Tags"
        case .collections:
            return "Collections"
        case .attachmentStatus:
            return "Attachment Status"
        case .fullText:
            return "Full Text"
        }
    }

    func title(for language: AppLanguage) -> String {
        guard language == .chinese else { return title }

        switch self {
        case .title:
            return "标题"
        case .englishTitle:
            return "英文标题"
        case .authors:
            return "作者"
        case .authorsEnglish:
            return "英文作者"
        case .source:
            return "来源"
        case .year:
            return "年份"
        case .doi:
            return "DOI"
        case .abstractText:
            return "摘要"
        case .chineseAbstract:
            return "中文摘要"
        case .volume:
            return "卷"
        case .issue:
            return "期"
        case .pages:
            return "页码"
        case .paperType:
            return "文献类型"
        case .notes:
            return "笔记"
        case .rqs:
            return "研究问题"
        case .conclusion:
            return "结论"
        case .results:
            return "结果"
        case .category:
            return "类别"
        case .impactFactor:
            return "影响因子"
        case .samples:
            return "样本"
        case .participantType:
            return "参与者类型"
        case .variables:
            return "变量"
        case .dataCollection:
            return "数据收集"
        case .dataAnalysis:
            return "数据分析"
        case .methodology:
            return "方法"
        case .theoreticalFoundation:
            return "理论基础"
        case .educationalLevel:
            return "教育阶段"
        case .country:
            return "国家"
        case .keywords:
            return "关键词"
        case .limitations:
            return "局限"
        case .webPageURL:
            return "网页链接"
        case .tags:
            return "标签"
        case .collections:
            return "分类"
        case .attachmentStatus:
            return "附件状态"
        case .fullText:
            return "全文"
        }
    }

    func value(in paper: Paper) -> String {
        switch self {
        case .title:
            return paper.title
        case .englishTitle:
            return paper.englishTitle
        case .authors:
            return paper.authors
        case .authorsEnglish:
            return paper.authorsEnglish
        case .source:
            return paper.source
        case .year:
            return paper.year
        case .doi:
            return paper.doi
        case .abstractText:
            return paper.abstractText
        case .chineseAbstract:
            return paper.chineseAbstract
        case .volume:
            return paper.volume
        case .issue:
            return paper.issue
        case .pages:
            return paper.pages
        case .paperType:
            return paper.paperType
        case .notes:
            return paper.notes
        case .rqs:
            return paper.rqs
        case .conclusion:
            return paper.conclusion
        case .results:
            return paper.results
        case .category:
            return paper.category
        case .impactFactor:
            return paper.impactFactor
        case .samples:
            return paper.samples
        case .participantType:
            return paper.participantType
        case .variables:
            return paper.variables
        case .dataCollection:
            return paper.dataCollection
        case .dataAnalysis:
            return paper.dataAnalysis
        case .methodology:
            return paper.methodology
        case .theoreticalFoundation:
            return paper.theoreticalFoundation
        case .educationalLevel:
            return paper.educationalLevel
        case .country:
            return paper.country
        case .keywords:
            return paper.keywords
        case .limitations:
            return paper.limitations
        case .webPageURL:
            return paper.webPageURL
        case .tags:
            return paper.tags.joined(separator: ", ")
        case .collections:
            return paper.collections.joined(separator: ", ")
        case .attachmentStatus:
            return paper.storedPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? "Attached"
                : "Missing"
        case .fullText:
            return paper.storedPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
}

enum AdvancedSearchOperator: String, CaseIterable, Identifiable {
    case contains
    case notContains
    case equals
    case beginsWith
    case endsWith
    case isEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains:
            return "Contains"
        case .notContains:
            return "Does Not Contain"
        case .equals:
            return "Equals"
        case .beginsWith:
            return "Starts With"
        case .endsWith:
            return "Ends With"
        case .isEmpty:
            return "Is Empty"
        }
    }

    func title(for language: AppLanguage) -> String {
        guard language == .chinese else { return title }

        switch self {
        case .contains:
            return "包含"
        case .notContains:
            return "不包含"
        case .equals:
            return "等于"
        case .beginsWith:
            return "开头为"
        case .endsWith:
            return "结尾为"
        case .isEmpty:
            return "为空"
        }
    }

    func matches(lhs: String, rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        switch self {
        case .contains:
            return left.localizedCaseInsensitiveContains(right)
        case .notContains:
            return !left.localizedCaseInsensitiveContains(right)
        case .equals:
            return left.compare(right, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        case .beginsWith:
            return left.lowercased().hasPrefix(right.lowercased())
        case .endsWith:
            return left.lowercased().hasSuffix(right.lowercased())
        case .isEmpty:
            return left.isEmpty
        }
    }
}

struct AdvancedSearchCondition: Identifiable, Hashable {
    var id = UUID()
    var field: AdvancedSearchField = .title
    var `operator`: AdvancedSearchOperator = .contains
    var value: String = ""

    func matches(_ paper: Paper) -> Bool {
        let fieldValue = field.value(in: paper)
        return `operator`.matches(lhs: fieldValue, rhs: value)
    }
}

struct AdvancedSearchState {
    var scope: SidebarSelection = .library(.all)
    var matchMode: AdvancedSearchMatchMode = .all
    var conditions: [AdvancedSearchCondition] = [
        AdvancedSearchCondition(),
        AdvancedSearchCondition(),
        AdvancedSearchCondition()
    ]

    func results(in papers: [Paper]) -> [Paper] {
        let activeConditions = conditions.filter {
            $0.operator == .isEmpty || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !activeConditions.isEmpty else {
            return papers
        }

        switch matchMode {
        case .all:
            return papers.filter { paper in activeConditions.allSatisfy { $0.matches(paper) } }
        case .any:
            return papers.filter { paper in activeConditions.contains { $0.matches(paper) } }
        }
    }
}

enum LibrarySearchQuery {
    case plainText(String)
    case citation(CitationSearchQuery)

    static func parse(_ rawValue: String) -> LibrarySearchQuery? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let citation = CitationSearchQuery(rawValue: trimmed) {
            return .citation(citation)
        }

        return .plainText(trimmed)
    }
}

struct CitationSearchQuery {
    private struct CitationEntry {
        var authorTerms: [String]
        var year: String
        var authorCountConstraint: AuthorCountConstraint

        func matches(_ paper: Paper) -> Bool {
            let searchMetadata = paper.searchMetadata
            let normalizedAuthorTerms = searchMetadata.normalizedAuthorTerms
            let normalizedAuthorsBlob = searchMetadata.normalizedAuthorsBlob

            guard authorCountConstraint.matches(searchMetadata.authorCount) else {
                return false
            }

            let hasAllAuthors = authorTerms.allSatisfy { authorTerm in
                normalizedAuthorTerms.contains { authorName in
                    authorName.contains(authorTerm)
                } || normalizedAuthorsBlob.contains(authorTerm)
            }
            guard hasAllAuthors else {
                return false
            }

            return CitationSearchQuery.extractedYear(from: paper.year) == year
        }
    }

    enum AuthorCountConstraint {
        case exact(Int)
        case atLeast(Int)

        func matches(_ value: Int) -> Bool {
            switch self {
            case .exact(let expected):
                return value == expected
            case .atLeast(let minimum):
                return value >= minimum
            }
        }
    }

    private let entries: [CitationEntry]

    private static let citationPattern = try? NSRegularExpression(
        pattern: #"([^;()]+?)\s*,\s*(\d{4}[a-zA-Z]?)"#
    )
    private static let fallbackPattern = try? NSRegularExpression(
        pattern: #"([^;()]+?)\s+(\d{4}[a-zA-Z]?)"#
    )
    private static let yearPattern = try? NSRegularExpression(pattern: #"\b(\d{4})\b"#)
    private static let etAlPattern = try? NSRegularExpression(pattern: #"\bet\s+al\.?\b"#, options: .caseInsensitive)

    init?(rawValue: String) {
        let normalizedInput = Self.normalizedCitationInput(rawValue)
        let parsed = Self.parseEntries(from: normalizedInput)
        guard !parsed.isEmpty else {
            return nil
        }
        entries = parsed
    }

    func matches(_ paper: Paper) -> Bool {
        entries.contains { $0.matches(paper) }
    }

    private static func parseEntries(from value: String) -> [CitationEntry] {
        guard let citationPattern, let fallbackPattern else {
            return []
        }
        var parsed: [CitationEntry] = []
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = citationPattern.matches(in: value, options: [], range: range)
        for match in matches {
            guard
                let authorRange = Range(match.range(at: 1), in: value),
                let yearRange = Range(match.range(at: 2), in: value),
                let entry = buildEntry(rawAuthors: String(value[authorRange]), rawYear: String(value[yearRange]))
            else {
                continue
            }
            parsed.append(entry)
        }

        // Fallback: allow missing comma, but keep conservative to reduce false positives.
        if parsed.isEmpty {
            let fallbackMatches = fallbackPattern.matches(in: value, options: [], range: range)
            for match in fallbackMatches {
                guard
                    let authorRange = Range(match.range(at: 1), in: value),
                    let yearRange = Range(match.range(at: 2), in: value)
                else {
                    continue
                }

                let rawAuthors = String(value[authorRange])
                if !looksLikeAuthorFragment(rawAuthors) {
                    continue
                }

                guard let entry = buildEntry(rawAuthors: rawAuthors, rawYear: String(value[yearRange])) else {
                    continue
                }
                parsed.append(entry)
            }
        }

        var deduplicated: [CitationEntry] = []
        for entry in parsed where !deduplicated.contains(where: { candidate in
            candidate.year == entry.year
                && candidate.authorTerms == entry.authorTerms
        }) {
            deduplicated.append(entry)
        }
        return deduplicated
    }

    private static func buildEntry(rawAuthors: String, rawYear: String) -> CitationEntry? {
        let normalizedAuthors = rawAuthors
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let normalizedYear = String(rawYear.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4))

        guard !normalizedAuthors.isEmpty else { return nil }
        guard !normalizedYear.isEmpty else { return nil }

        let hasEtAl = containsEtAl(in: normalizedAuthors)
        let parsedAuthors = authorTerms(from: normalizedAuthors)
        guard !parsedAuthors.isEmpty else { return nil }

        let constraint: AuthorCountConstraint = hasEtAl
            ? .atLeast(max(parsedAuthors.count + 1, 2))
            : .exact(parsedAuthors.count)

        return CitationEntry(
            authorTerms: parsedAuthors,
            year: normalizedYear,
            authorCountConstraint: constraint
        )
    }

    private static func authorTerms(from value: String) -> [String] {
        let normalized = value
            .replacingOccurrences(of: "＆", with: "&")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")

        return AuthorNameParser
            .parse(raw: normalized, dropEtAl: true)
            .map(AuthorNameParser.normalizedToken(from:))
            .filter { !$0.isEmpty }
    }

    private static func looksLikeAuthorFragment(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("et al")
            || normalized.contains("&")
            || normalized.contains(" and ")
            || normalized.contains("等")
    }

    private static func containsEtAl(in value: String) -> Bool {
        guard let etAlPattern else {
            return value.localizedCaseInsensitiveContains("et al")
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return etAlPattern.firstMatch(in: value, options: [], range: range) != nil
    }

    private static func normalizedCitationInput(_ value: String) -> String {
        value
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func extractedYear(from value: String) -> String? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard
            let match = Self.yearPattern?.firstMatch(in: value, options: [], range: range),
            let yearRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }

        return String(value[yearRange])
    }
}
