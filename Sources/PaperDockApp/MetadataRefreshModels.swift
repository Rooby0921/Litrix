import Foundation

enum MetadataRefreshMode: String, CaseIterable, Identifiable {
    case refreshAll
    case refreshMissing
    case customRefresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refreshAll:
            return "Refresh All"
        case .refreshMissing:
            return "Refresh Missing"
        case .customRefresh:
            return "Custom Refresh"
        }
    }
}

enum MetadataField: String, CaseIterable, Codable, Hashable, Identifiable {
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: return "Title"
        case .englishTitle: return "English Title"
        case .authors: return "Authors"
        case .authorsEnglish: return "Authors (English)"
        case .year: return "Year"
        case .source: return "Source"
        case .doi: return "DOI"
        case .abstractText: return "Abstract"
        case .chineseAbstract: return "Chinese Abstract"
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

    func displayName(for language: AppLanguage) -> String {
        guard language == .chinese else { return displayName }
        if let tableColumn {
            return tableColumn.displayName(for: language)
        }

        switch self {
        case .doi: return "DOI"
        case .abstractText: return "摘要"
        case .chineseAbstract: return "中文摘要"
        case .volume: return "卷"
        case .issue: return "期"
        case .pages: return "页码"
        case .paperType: return "文献类型"
        default: return displayName
        }
    }

    var tableColumn: PaperTableColumn? {
        switch self {
        case .title: return .title
        case .englishTitle: return .englishTitle
        case .authors: return .authors
        case .authorsEnglish: return .authorsEnglish
        case .year: return .year
        case .source: return .source
        case .abstractText: return .abstractText
        case .chineseAbstract: return .chineseAbstract
        case .rqs: return .rqs
        case .conclusion: return .conclusion
        case .results: return .results
        case .category: return .category
        case .impactFactor: return .impactFactor
        case .samples: return .samples
        case .participantType: return .participantType
        case .variables: return .variables
        case .dataCollection: return .dataCollection
        case .dataAnalysis: return .dataAnalysis
        case .methodology: return .methodology
        case .theoreticalFoundation: return .theoreticalFoundation
        case .educationalLevel: return .educationalLevel
        case .country: return .country
        case .keywords: return .keywords
        case .limitations: return .limitations
        case .doi, .volume, .issue, .pages, .paperType:
            return nil
        }
    }

    func value(in paper: Paper) -> String {
        switch self {
        case .title: return paper.title
        case .englishTitle: return paper.englishTitle
        case .authors: return paper.authors
        case .authorsEnglish: return paper.authorsEnglish
        case .year: return paper.year
        case .source: return paper.source
        case .doi: return paper.doi
        case .abstractText: return paper.abstractText
        case .chineseAbstract: return paper.chineseAbstract
        case .volume: return paper.volume
        case .issue: return paper.issue
        case .pages: return paper.pages
        case .paperType: return paper.paperType
        case .rqs: return paper.rqs
        case .conclusion: return paper.conclusion
        case .results: return paper.results
        case .category: return paper.category
        case .impactFactor: return paper.impactFactor
        case .samples: return paper.samples
        case .participantType: return paper.participantType
        case .variables: return paper.variables
        case .dataCollection: return paper.dataCollection
        case .dataAnalysis: return paper.dataAnalysis
        case .methodology: return paper.methodology
        case .theoreticalFoundation: return paper.theoreticalFoundation
        case .educationalLevel: return paper.educationalLevel
        case .country: return paper.country
        case .keywords: return paper.keywords
        case .limitations: return paper.limitations
        }
    }

    func isMissing(in paper: Paper) -> Bool {
        value(in: paper).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func assign(_ value: String, to paper: inout Paper) {
        switch self {
        case .title: paper.title = value
        case .englishTitle: paper.englishTitle = value
        case .authors: paper.authors = value
        case .authorsEnglish: paper.authorsEnglish = value
        case .year: paper.year = value
        case .source: paper.source = value
        case .doi: paper.doi = value
        case .abstractText: paper.abstractText = value
        case .chineseAbstract: paper.chineseAbstract = value
        case .volume: paper.volume = value
        case .issue: paper.issue = value
        case .pages: paper.pages = value
        case .paperType: paper.paperType = value
        case .rqs: paper.rqs = value
        case .conclusion: paper.conclusion = value
        case .results: paper.results = value
        case .category: paper.category = value
        case .impactFactor: paper.impactFactor = value
        case .samples: paper.samples = value
        case .participantType: paper.participantType = value
        case .variables: paper.variables = value
        case .dataCollection: paper.dataCollection = value
        case .dataAnalysis: paper.dataAnalysis = value
        case .methodology: paper.methodology = value
        case .theoreticalFoundation: paper.theoreticalFoundation = value
        case .educationalLevel: paper.educationalLevel = value
        case .country: paper.country = value
        case .keywords: paper.keywords = value
        case .limitations: paper.limitations = value
        }
    }

    func value(in suggestion: MetadataSuggestion) -> String {
        switch self {
        case .title: return suggestion.title
        case .englishTitle: return suggestion.englishTitle
        case .authors: return suggestion.authors
        case .authorsEnglish: return suggestion.authorsEnglish
        case .year: return suggestion.year
        case .source: return suggestion.source
        case .doi: return suggestion.doi
        case .abstractText: return suggestion.abstractText
        case .chineseAbstract: return suggestion.chineseAbstract
        case .volume: return suggestion.volume
        case .issue: return suggestion.issue
        case .pages: return suggestion.pages
        case .paperType: return suggestion.paperType
        case .rqs: return suggestion.rqs
        case .conclusion: return suggestion.conclusion
        case .results: return suggestion.results
        case .category: return suggestion.category
        case .impactFactor: return suggestion.impactFactor
        case .samples: return suggestion.samples
        case .participantType: return suggestion.participantType
        case .variables: return suggestion.variables
        case .dataCollection: return suggestion.dataCollection
        case .dataAnalysis: return suggestion.dataAnalysis
        case .methodology: return suggestion.methodology
        case .theoreticalFoundation: return suggestion.theoreticalFoundation
        case .educationalLevel: return suggestion.educationalLevel
        case .country: return suggestion.country
        case .keywords: return suggestion.keywords
        case .limitations: return suggestion.limitations
        }
    }
}

extension Paper {
    mutating func apply(
        _ suggestion: MetadataSuggestion,
        fields: [MetadataField],
        mode: MetadataRefreshMode
    ) {
        for field in fields {
            let incoming = MetadataValueNormalizer.normalize(field.value(in: suggestion), for: field)
            switch mode {
            case .refreshAll, .customRefresh:
                field.assign(incoming, to: &self)
            case .refreshMissing:
                guard field.isMissing(in: self) else { continue }
                let normalized = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }
                field.assign(incoming, to: &self)
            }
        }
    }
}
