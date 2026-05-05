import Foundation

struct LitrixWebMetadataResult {
    var pageURL: String
    var pageTitle: String
    var pdfURL: String
    var suggestion: MetadataSuggestion
}

enum LitrixWebMetadataError: LocalizedError {
    case missingWebPageURL
    case invalidWebPageURL
    case requestFailed(String)
    case emptyMetadata

    var errorDescription: String? {
        switch self {
        case .missingWebPageURL:
            return "这篇文献还没有网页链接。"
        case .invalidWebPageURL:
            return "网页链接无效。"
        case .requestFailed(let message):
            return "网页读取失败：\(message)"
        case .emptyMetadata:
            return "网页中没有找到可用元数据，已保留现有内容。"
        }
    }
}

enum LitrixWebMetadataService {
    static func fetch(from rawURL: String) async throws -> LitrixWebMetadataResult {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LitrixWebMetadataError.missingWebPageURL }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LitrixWebMetadataError.invalidWebPageURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LitrixWebMetadataError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LitrixWebMetadataError.requestFailed("HTTP \(statusCode)")
        }

        let html = decodedHTML(from: data, response: httpResponse)
        let parser = HTMLPaperMetadataParser(html: html, baseURL: httpResponse.url ?? url)
        let result = parser.result()
        guard hasSuggestionValue(result.suggestion) || !result.pdfURL.isEmpty else {
            throw LitrixWebMetadataError.emptyMetadata
        }
        return result
    }

    static func downloadPDF(from rawURL: String) async throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LitrixWebMetadataError.invalidWebPageURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/pdf,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LitrixWebMetadataError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LitrixWebMetadataError.requestFailed("HTTP \(statusCode)")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let looksLikePDF = contentType.contains("application/pdf") || url.pathExtension.lowercased() == "pdf"
        guard looksLikePDF else {
            throw LitrixWebMetadataError.requestFailed("远程文件不是 PDF。")
        }

        let fileName = sanitizedFileName(
            preferred: httpResponse.suggestedFilename ?? url.lastPathComponent,
            fallback: "Litrix-Web-\(UUID().uuidString).pdf"
        )
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: temporaryURL, options: .atomic)
        return temporaryURL
    }

    private static func decodedHTML(from data: Data, response: HTTPURLResponse) -> String {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("gbk") || contentType.contains("gb2312") {
            let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let html = String(data: data, encoding: String.Encoding(rawValue: encoding)) {
                return html
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func hasSuggestionValue(_ suggestion: MetadataSuggestion) -> Bool {
        [
            suggestion.title,
            suggestion.englishTitle,
            suggestion.authors,
            suggestion.authorsEnglish,
            suggestion.year,
            suggestion.source,
            suggestion.doi,
            suggestion.abstractText,
            suggestion.chineseAbstract,
            suggestion.volume,
            suggestion.issue,
            suggestion.pages,
            suggestion.paperType,
            suggestion.rqs,
            suggestion.conclusion,
            suggestion.results,
            suggestion.category,
            suggestion.impactFactor,
            suggestion.samples,
            suggestion.participantType,
            suggestion.variables,
            suggestion.dataCollection,
            suggestion.dataAnalysis,
            suggestion.methodology,
            suggestion.theoreticalFoundation,
            suggestion.educationalLevel,
            suggestion.country,
            suggestion.keywords,
            suggestion.limitations
        ]
        .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func sanitizedFileName(preferred: String, fallback: String) -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let safe = rawName.components(separatedBy: invalidCharacters).joined(separator: "-")
        return safe.lowercased().hasSuffix(".pdf") ? safe : "\(safe).pdf"
    }
}

private struct HTMLPaperMetadataParser {
    let html: String
    let baseURL: URL

    func result() -> LitrixWebMetadataResult {
        let title = firstMeta([
            "citation_title", "dc.title", "dcterms.title", "og:title", "twitter:title"
        ]).nilIfEmpty ?? documentTitle()
        let authors = unique(
            allMetaValues(["citation_author", "dc.creator", "dcterms.creator", "author"])
        )
        let publicationDate = firstMeta([
            "citation_publication_date", "citation_online_date", "citation_date",
            "dc.date", "dcterms.issued", "article:published_time"
        ])
        let source = firstMeta([
            "citation_journal_title", "citation_conference_title", "citation_publisher",
            "dc.source", "prism.publicationname", "og:site_name"
        ])
        let abstractText = firstMeta([
            "citation_abstract", "dc.description", "dcterms.abstract", "description", "og:description"
        ])
        let keywordValues = unique(
            allMetaValues(["citation_keywords", "keywords", "dc.subject"])
                .flatMap { splitList($0) }
        )
        let firstPage = firstMeta(["citation_firstpage", "prism.startingpage"])
        let lastPage = firstMeta(["citation_lastpage", "prism.endingpage"])
        let pages = pageRange(first: firstPage, last: lastPage)
        let suggestion = MetadataSuggestion(
            title: title,
            englishTitle: containsHanCharacters(title) ? "" : title,
            authors: authors.joined(separator: "; "),
            authorsEnglish: authors.contains(where: containsHanCharacters) ? "" : authors.joined(separator: "; "),
            year: extractYear(publicationDate),
            source: source,
            doi: extractDOI(),
            abstractText: abstractText,
            chineseAbstract: containsHanCharacters(abstractText) ? abstractText : "",
            volume: firstMeta(["citation_volume", "prism.volume"]),
            issue: firstMeta(["citation_issue", "prism.number"]),
            pages: pages,
            paperType: "电子文献",
            keywords: keywordValues.joined(separator: ", ")
        ).normalized()

        return LitrixWebMetadataResult(
            pageURL: baseURL.absoluteString,
            pageTitle: title,
            pdfURL: extractPDFURL(),
            suggestion: suggestion
        )
    }

    private func allMetaValues(_ keys: [String]) -> [String] {
        let wanted = Set(keys.map { $0.lowercased() })
        return metaTags().compactMap { attributes in
            let key = (attributes["name"] ?? attributes["property"] ?? attributes["itemprop"] ?? "")
                .lowercased()
            guard wanted.contains(key) else { return nil }
            return decodeHTMLEntities(attributes["content"] ?? "").trimmed.nilIfEmpty
        }
    }

    private func firstMeta(_ keys: [String]) -> String {
        allMetaValues(keys).first ?? ""
    }

    private func documentTitle() -> String {
        guard let range = html.range(
            of: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return ""
        }
        let raw = String(html[range])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeHTMLEntities(raw).trimmed
    }

    private func metaTags() -> [[String: String]] {
        matches(pattern: #"<meta\b[^>]*>"#).map(attributes(in:))
    }

    private func extractPDFURL() -> String {
        let direct = firstMeta(["citation_pdf_url"])
        if let url = absoluteURL(direct) {
            return url
        }

        for tag in matches(pattern: #"<(?:a|link)\b[^>]*(?:href)\s*=\s*["'][^"']+["'][^>]*>"#) {
            let attributes = attributes(in: tag)
            let href = attributes["href"] ?? ""
            let type = (attributes["type"] ?? "").lowercased()
            let lowerHref = href.lowercased()
            if type.contains("pdf") || lowerHref.range(of: #"\.pdf(?:$|[?#])"#, options: .regularExpression) != nil {
                if let url = absoluteURL(href) {
                    return url
                }
            }
        }
        return ""
    }

    private func extractDOI() -> String {
        let direct = firstMeta(["citation_doi", "dc.identifier", "dc.identifier.doi", "prism.doi"])
        if let doi = doiMatch(in: direct) {
            return doi
        }
        return doiMatch(in: html) ?? ""
    }

    private func extractYear(_ value: String) -> String {
        guard let range = value.range(of: #"\b(18|19|20|21)\d{2}\b"#, options: .regularExpression) else {
            return ""
        }
        return String(value[range])
    }

    private func pageRange(first: String, last: String) -> String {
        let first = first.trimmed
        let last = last.trimmed
        if !first.isEmpty, !last.isEmpty, first != last {
            return "\(first)-\(last)"
        }
        return first.isEmpty ? last : first
    }

    private func splitList(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ";,，；"))
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private func absoluteURL(_ value: String) -> String? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL.absoluteString
    }

    private func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(["'])(.*?)\2"#
        var result: [String: String] = [:]
        for match in matches(pattern: pattern, in: tag) {
            guard match.count >= 4 else { continue }
            result[match[1].lowercased()] = decodeHTMLEntities(match[3])
        }
        return result
    }

    private func doiMatch(in value: String) -> String? {
        guard let range = value.range(
            of: #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        return String(value[range]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n<>[]{}()\"'.,;:"))
    }

    private func containsHanCharacters(_ value: String) -> Bool {
        value.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private func matches(pattern: String) -> [String] {
        matches(pattern: pattern, in: html).compactMap(\.first)
    }

    private func matches(pattern: String, in value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsString = value as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return regex.matches(in: value, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return "" }
                return nsString.substring(with: range)
            }
        }
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        let numericPattern = #"&#(x?[0-9A-Fa-f]+);"#
        guard let regex = try? NSRegularExpression(pattern: numericPattern) else { return result }
        let nsString = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed()
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let token = nsString.substring(with: match.range(at: 1))
            let radix = token.lowercased().hasPrefix("x") ? 16 : 10
            let numberText = radix == 16 ? String(token.dropFirst()) : token
            guard let scalarValue = UInt32(numberText, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else { continue }
            result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: String(scalar))
        }
        return result
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
