import Foundation

enum DOIMetadataService {
    static func fetchSuggestion(for doi: String) async throws -> MetadataSuggestion {
        let normalizedDOI = MetadataValueNormalizer.normalizeDOI(doi)
        guard !normalizedDOI.isEmpty else {
            throw NSError(domain: "Litrix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid DOI"])
        }

        var doiPathAllowed = CharacterSet.urlPathAllowed
        doiPathAllowed.remove(charactersIn: "/")
        let encodedDOI = normalizedDOI.addingPercentEncoding(withAllowedCharacters: doiPathAllowed) ?? normalizedDOI
        guard let url = URL(string: "https://api.crossref.org/works/\(encodedDOI)") else {
            throw NSError(domain: "Litrix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid DOI"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown DOI metadata error"
            throw NSError(domain: "Litrix", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = root["message"] as? [String: Any]
        else {
            throw NSError(domain: "Litrix", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected DOI response format"])
        }

        return suggestion(from: message, requestedDOI: normalizedDOI).normalized()
    }

    static func fetchPaper(for doi: String) async throws -> Paper {
        let suggestion = try await fetchSuggestion(for: doi)
        return Paper(
            title: suggestion.title,
            englishTitle: suggestion.englishTitle,
            authors: suggestion.authors,
            authorsEnglish: suggestion.authorsEnglish,
            year: suggestion.year,
            source: suggestion.source,
            doi: suggestion.doi,
            abstractText: suggestion.abstractText,
            notes: "",
            paperType: suggestion.paperType.isEmpty ? "期刊文章" : suggestion.paperType,
            volume: suggestion.volume,
            issue: suggestion.issue,
            pages: suggestion.pages,
            storageFolderName: nil,
            storedPDFFileName: nil,
            originalPDFFileName: nil,
            imageFileNames: []
        )
    }

    private static func suggestion(from message: [String: Any], requestedDOI: String) -> MetadataSuggestion {
        let title = firstString(in: message, keys: ["title"])
        let source = firstString(in: message, keys: ["container-title", "short-container-title", "event", "publisher"])
        let year = publicationYear(in: message)
        let authors = authorList(from: message["author"] as? [[String: Any]])
        let abstractText = strippedHTML(stringValue(message["abstract"]))
        let doi = stringValue(message["DOI"], fallback: requestedDOI)
        let volume = stringValue(message["volume"])
        let issue = stringValue(message["issue"])
        let pages = firstString(in: message, keys: ["page", "article-number"])
        let paperType = mapCrossrefType(stringValue(message["type"]))

        return MetadataSuggestion(
            title: title,
            englishTitle: title,
            authors: authors,
            authorsEnglish: authors,
            year: year,
            source: source,
            doi: doi,
            abstractText: abstractText,
            volume: volume,
            issue: issue,
            pages: pages,
            paperType: paperType
        )
    }

    private static func firstString(in message: [String: Any], keys: [String]) -> String {
        for key in keys {
            let value = message[key]
            if let array = value as? [Any],
               let first = array.compactMap({ stringValue($0) }).first(where: { !$0.isEmpty }) {
                return first
            }
            if let dictionary = value as? [String: Any] {
                for nestedKey in ["title", "name", "acronym"] {
                    let string = stringValue(dictionary[nestedKey])
                    if !string.isEmpty {
                        return string
                    }
                }
            }
            let string = stringValue(value)
            if !string.isEmpty {
                return string
            }
        }
        return ""
    }

    private static func stringValue(_ value: Any?, fallback: String = "") -> String {
        switch value {
        case let value as String:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        case let value as NSNumber:
            return value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func publicationYear(in message: [String: Any]) -> String {
        for key in ["published-print", "published-online", "published", "issued", "created", "deposited"] {
            guard
                let date = message[key] as? [String: Any],
                let dateParts = date["date-parts"] as? [[[Int]]],
                let year = dateParts.first?.first?.first
            else {
                continue
            }
            let yearText = String(year)
            let normalized = MetadataValueNormalizer.normalizeYear(yearText)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return ""
    }

    private static func authorList(from authorItems: [[String: Any]]?) -> String {
        guard let authorItems else { return "" }
        return authorItems.compactMap { item in
            let family = stringValue(item["family"])
            let given = stringValue(item["given"])
            if !family.isEmpty && !given.isEmpty {
                return "\(given) \(family)"
            }
            return family.isEmpty ? given : family
        }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private static func strippedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapCrossrefType(_ type: String) -> String {
        let normalized = type.lowercased()
        if normalized.contains("journal") || normalized == "article" {
            return "期刊文章"
        }
        if normalized.contains("proceedings") || normalized.contains("conference") {
            return "会议论文"
        }
        if normalized.contains("book-chapter") || normalized.contains("chapter") {
            return "图书章节"
        }
        if normalized == "book" || normalized.contains("monograph") {
            return "书籍"
        }
        if normalized.contains("dissertation") || normalized.contains("thesis") {
            return "学位论文"
        }
        if normalized.contains("report") {
            return "报告"
        }
        return "电子文献"
    }
}
