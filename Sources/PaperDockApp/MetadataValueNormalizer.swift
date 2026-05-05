import Foundation

enum MetadataValueNormalizer {
    static func normalize(_ value: String, for field: MetadataField) -> String {
        switch field {
        case .title, .englishTitle:
            return normalizeTitle(value)
        case .authors, .authorsEnglish:
            return normalizeAuthors(value)
        case .year:
            return normalizeYear(value)
        case .source:
            return normalizeSource(value)
        case .doi:
            return normalizeDOI(value)
        case .volume:
            return normalizeVolume(value)
        case .issue:
            return normalizeIssue(value)
        case .pages:
            return normalizePages(value)
        case .paperType:
            return normalizePaperType(value)
        case .category, .keywords:
            return normalizeCommaSeparatedList(value)
        case .abstractText, .chineseAbstract, .rqs, .conclusion, .results, .impactFactor, .samples, .participantType,
             .variables, .dataCollection, .dataAnalysis, .methodology, .theoreticalFoundation,
             .educationalLevel, .country, .limitations:
            return cleanMultiline(value)
        }
    }

    static func normalizeTitle(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:title|article title|paper title|题名|标题|论文题目)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        value = stripEnclosingQuotes(value)
        value = value.replacingOccurrences(
            of: #"(?i)\.(?:pdf|docx?|rtf|txt)$"#,
            with: "",
            options: .regularExpression
        )
        value = trim(value, characters: " \t\r\n\"'“”‘’[]{}<>")

        if isMissingToken(value) || isLikelyTitleArtifact(value) {
            return ""
        }
        return value
    }

    static func normalizeAuthors(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:authors?|by|作者|作者姓名)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "＆", with: "&")
        value = value.replacingOccurrences(
            of: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"(?i)\bORCID\b\s*:?\s*[0-9Xx\-\s]+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\bcorresponding author\b.*$"#,
            with: " ",
            options: .regularExpression
        )
        value = cleanSingleLine(value)

        let parsed = AuthorNameParser.parse(raw: value)
        var seen: Set<String> = []
        var names: [String] = []
        for item in parsed {
            let cleaned = cleanAuthorName(item)
            guard !cleaned.isEmpty, !isLikelyAuthorArtifact(cleaned) else { continue }
            let key = AuthorNameParser.normalizedToken(from: cleaned)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            names.append(cleaned)
        }

        return names.joined(separator: ", ")
    }

    static func normalizeYear(_ raw: String) -> String {
        let value = cleanSingleLine(raw)
        guard !value.isEmpty else { return "" }

        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let pattern = #"(?<!\d)(19|20)\d{2}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let nsValue = value as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        for match in regex.matches(in: value, range: range) {
            let yearText = nsValue.substring(with: match.range)
            guard let year = Int(yearText), (1900...(currentYear + 1)).contains(year) else { continue }
            return yearText
        }
        return ""
    }

    static func normalizeSource(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:source|journal|venue|来源|期刊|会议)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\b(?:doi|issn|isbn)\b\s*[:：]?.*$"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = stripSourceCitationSuffix(value)
        value = trim(value, characters: " \t\r\n,.;:|")

        if isMissingToken(value) || isLikelySourceArtifact(value) {
            return ""
        }
        return value
    }

    static func normalizeDOI(_ raw: String) -> String {
        var value = normalizeDOIIdentifier(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^(?:doi\s*[:：]\s*)"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[)\]\}>,.;:]+$"#,
            with: "",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizePages(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:pp?\.?|pages?|page range|article number|页码|页)\s*[:：]?\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        if isMissingToken(value) {
            return ""
        }
        if let range = value.range(of: #"[A-Za-z]?\d+[A-Za-z]?\s*-\s*[A-Za-z]?\d+[A-Za-z]?"#, options: .regularExpression) {
            return String(value[range]).replacingOccurrences(of: " ", with: "")
        }
        if let range = value.range(of: #"(?i)\be\d+\b"#, options: .regularExpression) {
            return String(value[range])
        }
        if let range = value.range(of: #"(?i)\b[A-Z]?\d+[A-Z]?\b"#, options: .regularExpression) {
            return String(value[range])
        }
        return ""
    }

    static func normalizeVolume(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:vol(?:ume)?\.?|卷)\s*[:：]?\s*"#,
            with: "",
            options: .regularExpression
        )
        value = trim(value, characters: " \t\r\n,.;:|()[]{}")
        guard !isMissingToken(value) else { return "" }

        if let range = value.range(of: #"^\d+[A-Za-z]?(?=\s*\()"#, options: .regularExpression) {
            return String(value[range])
        }
        if let range = value.range(of: #"^[A-Za-z]?\d+[A-Za-z]?$"#, options: .regularExpression) {
            return String(value[range])
        }
        if let range = value.range(of: #"(?<!\d)[A-Za-z]?\d+[A-Za-z]?(?!\d)"#, options: .regularExpression) {
            return String(value[range])
        }
        return cleanSingleLine(value)
    }

    static func normalizeIssue(_ raw: String) -> String {
        var value = cleanSingleLine(raw)
        value = value.replacingOccurrences(
            of: #"(?i)^\s*(?:issue|number|no\.?|期)\s*[:：]?\s*"#,
            with: "",
            options: .regularExpression
        )
        value = trim(value, characters: " \t\r\n,.;:|()[]{}")
        guard !isMissingToken(value) else { return "" }

        if let range = value.range(of: #"(?<=\()\s*\d+[A-Za-z]?\s*(?=\))"#, options: .regularExpression) {
            return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = value.range(of: #"^[A-Za-z]?\d+[A-Za-z]?$"#, options: .regularExpression) {
            return String(value[range])
        }
        if let range = value.range(of: #"(?<!\d)[A-Za-z]?\d+[A-Za-z]?(?!\d)"#, options: .regularExpression) {
            return String(value[range])
        }
        return cleanSingleLine(value)
    }

    static func normalizePaperType(_ raw: String) -> String {
        let value = cleanSingleLine(raw)
        let lowered = value.lowercased()
        if lowered.contains("journal") || value.contains("期刊") {
            return "期刊文章"
        }
        if lowered.contains("conference") || lowered.contains("proceedings") || value.contains("会议") {
            return "会议论文"
        }
        if lowered.contains("book chapter") || value.contains("章节") {
            return "图书章节"
        }
        if lowered.contains("thesis") || lowered.contains("dissertation") || value.contains("学位论文") {
            return "学位论文"
        }
        if lowered.contains("electronic") || lowered.contains("web") || value.contains("电子") {
            return "电子文献"
        }
        return isMissingToken(value) ? "" : value
    }

    static func normalizeCommaSeparatedList(_ raw: String) -> String {
        let value = cleanSingleLine(raw)
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "、", with: ",")
        var seen: Set<String> = []
        let items = value
            .split(separator: ",")
            .map { cleanSingleLine(String($0)) }
            .filter { !$0.isEmpty && !isMissingToken($0) }
            .filter { item in
                let key = AuthorNameParser.normalizedToken(from: item)
                return !key.isEmpty && seen.insert(key).inserted
            }
        return items.joined(separator: ", ")
    }

    static func cleanSingleLine(_ raw: String) -> String {
        cleanMultiline(raw)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanMultiline(_ raw: String) -> String {
        stripMarkupTags(from: raw)
            .replacingOccurrences(of: "\u{0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripMarkupTags(from raw: String) -> String {
        raw
            .replacingOccurrences(
                of: #"&lt;/?[A-Za-z][A-Za-z0-9:_-]*(?:\s+[^&<>]*)?&gt;"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"</?[A-Za-z][A-Za-z0-9:_-]*(?:\s+[^<>]*)?>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func cleanAuthorName(_ raw: String) -> String {
        var value = raw
        value = value.replacingOccurrences(
            of: #"\([^)]*(?:University|Department|College|School|Institute|Email|ORCID|Corresponding)[^)]*\)"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(
            of: #"(?<=\p{L})\s*[0-9*]+"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"^[0-9*]+\s*"#,
            with: "",
            options: .regularExpression
        )
        value = cleanSingleLine(value)
        return trim(value, characters: " \t\r\n,;:|/\\()[]{}<>*")
    }

    private static func stripEnclosingQuotes(_ value: String) -> String {
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("\u{201C}", "\u{201D}"),
            ("\u{2018}", "\u{2019}")
        ]
        guard let first = value.first, let last = value.last else { return value }
        for pair in pairs where first == pair.0 && last == pair.1 {
            return String(value.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func trim(_ value: String, characters: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: characters))
    }

    private static func isMissingToken(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "n/a"
            || normalized == "na"
            || normalized == "none"
            || normalized == "null"
            || normalized == "unknown"
            || normalized == "-"
            || normalized == "--"
            || normalized == "—"
    }

    private static func isLikelyTitleArtifact(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.range(of: #"^(?:untitled|full text|article|research article|original article|review article)$"#, options: .regularExpression) != nil {
            return true
        }
        return lowered.contains("microsoft word")
            || lowered.contains("contents lists available")
            || lowered.contains("sciencedirect")
            || lowered.contains("springerlink")
            || lowered.contains("downloaded from")
            || lowered.contains("journal homepage")
            || lowered.contains("www.")
            || lowered.contains("http://")
            || lowered.contains("https://")
            || lowered.hasPrefix("/")
    }

    private static func isLikelyAuthorArtifact(_ value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.count < 2 || lowered.count > 140 {
            return true
        }
        if lowered.range(of: #"\d{4}"#, options: .regularExpression) != nil {
            return true
        }
        return lowered.contains("abstract")
            || lowered.contains("keyword")
            || lowered.contains("university")
            || lowered.contains("department")
            || lowered.contains("journal")
            || lowered.contains("conference")
            || lowered.contains("doi")
            || lowered.contains("copyright")
            || lowered.contains("received")
            || lowered.contains("accepted")
            || lowered.contains("available online")
            || lowered.contains("@")
            || lowered.contains("http")
    }

    private static func isLikelySourceArtifact(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.contains("journal homepage")
            || lowered.contains("contents lists available")
            || lowered.contains("downloaded from")
            || lowered.contains("downloaded by")
            || lowered.contains("publication details")
            || lowered.contains("instructions for authors")
            || lowered.contains("registered office")
            || lowered.contains("publisher:")
            || lowered.contains("abstract")
            || lowered.contains("keywords")
            || lowered.contains("@")
            || lowered.contains("http")
    }

    private static func stripSourceCitationSuffix(_ raw: String) -> String {
        var value = raw
        let suffixPatterns = [
            #"(?i)\s+\b(?:18|19|20|21)\d{2}\b\s+\d+[A-Za-z]?\s*:\s*\d+[A-Za-z]?.*$"#,
            #"(?i)\s+\d+[A-Za-z]?\s*,\s*\d+[A-Za-z]?\s*\(\s*(?:18|19|20|21)\d{2}\s*\).*$"#,
            #"(?i)\s+\bvol(?:ume)?\.?\s*\d.*$"#,
            #"(?i)\s+\bno\.?\s*\d.*$"#,
            #"(?i)\s+\bissue\s*\d.*$"#,
            #"(?i)\s+\b\d{1,4}\s*\(\s*[A-Za-z]?\d+[A-Za-z]?\s*\).*$"#,
            #"(?i)\s*,?\s*(?:pp?\.?|pages?)\s*\d+.*$"#,
            #"\s*第\s*\d+\s*卷.*$"#,
            #"\s*\d+\s*卷\s*\d+\s*期.*$"#
        ]
        for pattern in suffixPatterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return value
    }
}

extension MetadataSuggestion {
    func normalized() -> MetadataSuggestion {
        MetadataSuggestion(
            title: MetadataValueNormalizer.normalizeTitle(title),
            englishTitle: MetadataValueNormalizer.normalizeTitle(englishTitle),
            authors: MetadataValueNormalizer.normalizeAuthors(authors),
            authorsEnglish: MetadataValueNormalizer.normalizeAuthors(authorsEnglish),
            year: MetadataValueNormalizer.normalizeYear(year),
            source: MetadataValueNormalizer.normalizeSource(source),
            doi: MetadataValueNormalizer.normalizeDOI(doi),
            abstractText: MetadataValueNormalizer.normalize(abstractText, for: .abstractText),
            chineseAbstract: MetadataValueNormalizer.normalize(chineseAbstract, for: .chineseAbstract),
            volume: MetadataValueNormalizer.normalize(volume, for: .volume),
            issue: MetadataValueNormalizer.normalize(issue, for: .issue),
            pages: MetadataValueNormalizer.normalizePages(pages),
            paperType: MetadataValueNormalizer.normalizePaperType(paperType),
            rqs: MetadataValueNormalizer.normalize(rqs, for: .rqs),
            conclusion: MetadataValueNormalizer.normalize(conclusion, for: .conclusion),
            results: MetadataValueNormalizer.normalize(results, for: .results),
            category: MetadataValueNormalizer.normalizeCommaSeparatedList(category),
            impactFactor: MetadataValueNormalizer.normalize(impactFactor, for: .impactFactor),
            samples: MetadataValueNormalizer.normalize(samples, for: .samples),
            participantType: MetadataValueNormalizer.normalize(participantType, for: .participantType),
            variables: MetadataValueNormalizer.normalize(variables, for: .variables),
            dataCollection: MetadataValueNormalizer.normalize(dataCollection, for: .dataCollection),
            dataAnalysis: MetadataValueNormalizer.normalize(dataAnalysis, for: .dataAnalysis),
            methodology: MetadataValueNormalizer.normalize(methodology, for: .methodology),
            theoreticalFoundation: MetadataValueNormalizer.normalize(theoreticalFoundation, for: .theoreticalFoundation),
            educationalLevel: MetadataValueNormalizer.normalize(educationalLevel, for: .educationalLevel),
            country: MetadataValueNormalizer.normalize(country, for: .country),
            keywords: MetadataValueNormalizer.normalizeCommaSeparatedList(keywords),
            limitations: MetadataValueNormalizer.normalize(limitations, for: .limitations)
        )
    }
}
