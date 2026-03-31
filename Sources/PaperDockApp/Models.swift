import Foundation

enum PaperRatingScale {
    static let maximum = 3

    static func clamped(_ value: Int) -> Int {
        min(max(value, 0), maximum)
    }
}

enum TagPaletteColor: String, CaseIterable, Codable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        }
    }

    var hex: String {
        switch self {
        case .red:
            return "#FF3B30"
        case .orange:
            return "#FF9500"
        case .yellow:
            return "#FFCC00"
        case .green:
            return "#34C759"
        case .blue:
            return "#1E7CEB"
        case .purple:
            return "#AF52DE"
        case .pink:
            return "#FF2D55"
        }
    }
}

enum AuthorNameParser {
    private static let connectivePattern = #"\s*(?:\band\b|&|＆|和|与)\s*"#
    private static let etAlPattern = #"\bet\s+al\.?\b"#

    static func parse(raw: String, dropEtAl: Bool = false) -> [String] {
        var normalized = raw
            .replacingOccurrences(of: "\n", with: ";")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "、", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        if dropEtAl {
            normalized = normalized.replacingOccurrences(
                of: etAlPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !normalized.isEmpty else { return [] }
        }

        let connectiveParts = splitByRegex(normalized, pattern: connectivePattern)
        if connectiveParts.count > 1 {
            let cleaned = connectiveParts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            if !cleaned.isEmpty { return cleaned }
        }

        if normalized.contains(";") {
            let parts = normalized
                .split(separator: ";")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts }
        }

        if normalized.contains(",") {
            let rawParts = normalized
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }

            if rawParts.count >= 2 {
                let looksLikeSurnameCommaGiven = rawParts.count % 2 == 0
                    && stride(from: 0, to: rawParts.count, by: 2).allSatisfy { index in
                        rawParts[index].split(separator: " ").count == 1
                    }
                    && stride(from: 1, to: rawParts.count, by: 2).allSatisfy { index in
                        let token = rawParts[index]
                        return token.contains(".") || token.split(separator: " ").count <= 2
                    }

                if looksLikeSurnameCommaGiven {
                    var combined: [String] = []
                    var index = 0
                    while index + 1 < rawParts.count {
                        combined.append("\(rawParts[index]), \(rawParts[index + 1])")
                        index += 2
                    }
                    if !combined.isEmpty { return combined }
                }

                return rawParts
            }
        }

        return [normalized]
    }

    static func normalizedToken(from value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(
                of: #"[^\p{L}\p{N}]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitByRegex(
        _ value: String,
        pattern: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return [value]
        }
        let nsString = value as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: value, options: [], range: fullRange)
        guard !matches.isEmpty else { return [value] }

        var parts: [String] = []
        var cursor = 0
        for match in matches {
            let range = NSRange(location: cursor, length: match.range.location - cursor)
            if range.length > 0 {
                let segment = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    parts.append(segment)
                }
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsString.length {
            let tailRange = NSRange(location: cursor, length: nsString.length - cursor)
            let tail = nsString.substring(with: tailRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                parts.append(tail)
            }
        }

        return parts
    }
}

struct PaperSearchMetadata: Codable, Hashable {
    var authorNames: [String]
    var normalizedAuthorTerms: [String]
    var normalizedAuthorsBlob: String
    var authorCount: Int

    init(authors: String) {
        let names = AuthorNameParser.parse(raw: authors)
        let normalizedNames = names
            .map(AuthorNameParser.normalizedToken(from:))
            .filter { !$0.isEmpty }
        let blob = AuthorNameParser.normalizedToken(from: authors)

        authorNames = names
        normalizedAuthorTerms = normalizedNames
        normalizedAuthorsBlob = blob
        authorCount = normalizedNames.count
    }
}

struct Paper: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var englishTitle: String
    var authors: String {
        didSet {
            guard oldValue != authors else { return }
            searchMetadata = PaperSearchMetadata(authors: authors)
        }
    }
    var authorsEnglish: String
    var searchMetadata: PaperSearchMetadata
    var year: String
    var source: String
    var rating: Int
    var doi: String
    var abstractText: String
    var notes: String
    var collections: [String]
    var tags: [String]
    var paperType: String
    var volume: String
    var issue: String
    var pages: String
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
    var storageFolderName: String?
    var storedPDFFileName: String?
    var originalPDFFileName: String?
    var preferredOpenPDFFileName: String?
    var imageFileNames: [String]
    var addedAtMilliseconds: Int64
    var importedAt: Date
    var lastOpenedAt: Date?
    var lastEditedAtMilliseconds: Int64?

    init(
        id: UUID = UUID(),
        title: String = "",
        englishTitle: String = "",
        authors: String = "",
        authorsEnglish: String = "",
        year: String = "",
        source: String = "",
        rating: Int = 0,
        doi: String = "",
        abstractText: String = "",
        notes: String = "",
        collections: [String] = [],
        tags: [String] = [],
        paperType: String = "期刊文章",
        volume: String = "",
        issue: String = "",
        pages: String = "",
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
        limitations: String = "",
        storageFolderName: String? = nil,
        storedPDFFileName: String? = nil,
        originalPDFFileName: String? = nil,
        preferredOpenPDFFileName: String? = nil,
        imageFileNames: [String] = [],
        addedAtMilliseconds: Int64 = Paper.currentTimestampMilliseconds(),
        importedAt: Date = .now,
        lastOpenedAt: Date? = nil,
        lastEditedAtMilliseconds: Int64? = nil,
        searchMetadata: PaperSearchMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.englishTitle = englishTitle
        self.authors = authors
        self.authorsEnglish = authorsEnglish
        self.searchMetadata = searchMetadata ?? PaperSearchMetadata(authors: authors)
        self.year = year
        self.source = source
        self.rating = PaperRatingScale.clamped(rating)
        self.doi = doi
        self.abstractText = abstractText
        self.notes = notes
        self.collections = collections
        self.tags = tags
        self.paperType = paperType
        self.volume = volume
        self.issue = issue
        self.pages = pages
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
        self.storageFolderName = storageFolderName
        self.storedPDFFileName = storedPDFFileName
        self.originalPDFFileName = originalPDFFileName
        self.preferredOpenPDFFileName = preferredOpenPDFFileName
        self.imageFileNames = imageFileNames
        self.addedAtMilliseconds = addedAtMilliseconds
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastEditedAtMilliseconds = lastEditedAtMilliseconds
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case englishTitle
        case authors
        case authorsEnglish
        case searchMetadata
        case year
        case source
        case rating
        case doi
        case abstractText
        case notes
        case collections
        case tags
        case paperType
        case volume
        case issue
        case pages
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
        case storageFolderName
        case storedPDFFileName
        case originalPDFFileName
        case preferredOpenPDFFileName
        case imageFileNames
        case addedAtMilliseconds
        case importedAt
        case lastOpenedAt
        case lastEditedAtMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        englishTitle = try container.decodeIfPresent(String.self, forKey: .englishTitle) ?? ""
        let decodedAuthors = try container.decodeIfPresent(String.self, forKey: .authors) ?? ""
        authors = decodedAuthors
        authorsEnglish = try container.decodeIfPresent(String.self, forKey: .authorsEnglish) ?? ""
        searchMetadata = PaperSearchMetadata(authors: decodedAuthors)
        year = try container.decodeIfPresent(String.self, forKey: .year) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        rating = PaperRatingScale.clamped(try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0)
        doi = try container.decodeIfPresent(String.self, forKey: .doi) ?? ""
        abstractText = try container.decodeIfPresent(String.self, forKey: .abstractText) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        collections = try container.decodeIfPresent([String].self, forKey: .collections) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        paperType = try container.decodeIfPresent(String.self, forKey: .paperType) ?? "期刊文章"
        volume = try container.decodeIfPresent(String.self, forKey: .volume) ?? ""
        issue = try container.decodeIfPresent(String.self, forKey: .issue) ?? ""
        pages = try container.decodeIfPresent(String.self, forKey: .pages) ?? ""
        rqs = try container.decodeIfPresent(String.self, forKey: .rqs) ?? ""
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion) ?? ""
        results = try container.decodeIfPresent(String.self, forKey: .results) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        impactFactor = try container.decodeIfPresent(String.self, forKey: .impactFactor) ?? ""
        samples = try container.decodeIfPresent(String.self, forKey: .samples) ?? ""
        participantType = try container.decodeIfPresent(String.self, forKey: .participantType) ?? ""
        variables = try container.decodeIfPresent(String.self, forKey: .variables) ?? ""
        dataCollection = try container.decodeIfPresent(String.self, forKey: .dataCollection) ?? ""
        dataAnalysis = try container.decodeIfPresent(String.self, forKey: .dataAnalysis) ?? ""
        methodology = try container.decodeIfPresent(String.self, forKey: .methodology) ?? ""
        theoreticalFoundation = try container.decodeIfPresent(String.self, forKey: .theoreticalFoundation) ?? ""
        educationalLevel = try container.decodeIfPresent(String.self, forKey: .educationalLevel) ?? ""
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        keywords = try container.decodeIfPresent(String.self, forKey: .keywords) ?? ""
        limitations = try container.decodeIfPresent(String.self, forKey: .limitations) ?? ""
        storageFolderName = try container.decodeIfPresent(String.self, forKey: .storageFolderName)
        storedPDFFileName = try container.decodeIfPresent(String.self, forKey: .storedPDFFileName)
        originalPDFFileName = try container.decodeIfPresent(String.self, forKey: .originalPDFFileName)
        preferredOpenPDFFileName = try container.decodeIfPresent(String.self, forKey: .preferredOpenPDFFileName)
        imageFileNames = try container.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? .now
        if let decodedMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .addedAtMilliseconds) {
            addedAtMilliseconds = decodedMilliseconds
        } else {
            addedAtMilliseconds = Int64((importedAt.timeIntervalSince1970 * 1_000).rounded())
        }
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        lastEditedAtMilliseconds = try container.decodeIfPresent(Int64.self, forKey: .lastEditedAtMilliseconds)
    }

    var imageSortKey: String {
        imageFileNames.joined(separator: "\u{1F}")
    }

    var tagsSortKey: String {
        tags.joined(separator: "\u{1F}")
    }

    var attachmentSortKey: String {
        let normalized = storedPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? "0" : "1-\(normalized)"
    }

    var editedSortKey: Int64 {
        lastEditedAtMilliseconds ?? 0
    }

    var addedAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(addedAtMilliseconds) / 1_000)
    }

    var editedAtDate: Date? {
        guard let lastEditedAtMilliseconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastEditedAtMilliseconds) / 1_000)
    }

    static func currentTimestampMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
}

struct LibrarySnapshot: Codable {
    var papers: [Paper]
    var collections: [String]
    var tags: [String]
    var tagColorHexes: [String: String]

    init(
        papers: [Paper],
        collections: [String],
        tags: [String],
        tagColorHexes: [String: String] = [:]
    ) {
        self.papers = papers
        self.collections = collections
        self.tags = tags
        self.tagColorHexes = tagColorHexes
    }

    private enum CodingKeys: String, CodingKey {
        case papers
        case collections
        case tags
        case tagColorHexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        papers = try container.decode([Paper].self, forKey: .papers)
        collections = try container.decode([String].self, forKey: .collections)
        tags = try container.decode([String].self, forKey: .tags)
        tagColorHexes = try container.decodeIfPresent([String: String].self, forKey: .tagColorHexes) ?? [:]
    }
}

enum TaxonomyKind: String, CaseIterable, Identifiable {
    case collection
    case tag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection:
            return "分类"
        case .tag:
            return "标签"
        }
    }
}

enum SystemLibrary: String, CaseIterable, Hashable {
    case all
    case recentReading
    case zombiePapers
    case unfiled
    case missingDOI
    case missingAttachment

    var title: String {
        switch self {
        case .all:
            return "所有文献"
        case .recentReading:
            return "最近阅读"
        case .zombiePapers:
            return "Zombie Papers"
        case .unfiled:
            return "未整理"
        case .missingDOI:
            return "缺失 DOI"
        case .missingAttachment:
            return "缺失附件"
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "books.vertical"
        case .recentReading:
            return "clock.arrow.circlepath"
        case .zombiePapers:
            return "moon.zzz"
        case .unfiled:
            return "tray"
        case .missingDOI:
            return "magnifyingglass.circle"
        case .missingAttachment:
            return "paperclip"
        }
    }
}

enum SidebarSelection: Hashable {
    case library(SystemLibrary)
    case collection(String)
    case tag(String)

    var title: String {
        switch self {
        case .library(let filter):
            return filter.title
        case .collection(let name):
            return name
        case .tag(let name):
            return "#\(name)"
        }
    }
}
