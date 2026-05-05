import Foundation

struct LitrixWebImportError: LocalizedError {
    let statusCode: Int
    let message: String

    var errorDescription: String? { message }
    var localizedDescription: String { message }

    static func badRequest(_ message: String) -> LitrixWebImportError {
        LitrixWebImportError(statusCode: 400, message: message)
    }
}

private struct LitrixWebImportRequest: Decodable {
    struct Metadata: Decodable {
        var title: String?
        var englishTitle: String?
        var authors: String?
        var authorsEnglish: String?
        var year: String?
        var source: String?
        var doi: String?
        var abstractText: String?
        var chineseAbstract: String?
        var notes: String?
        var tags: [String]?
        var collections: [String]?
        var paperType: String?
        var volume: String?
        var issue: String?
        var pages: String?
        var rqs: String?
        var conclusion: String?
        var results: String?
        var category: String?
        var impactFactor: String?
        var samples: String?
        var participantType: String?
        var variables: String?
        var dataCollection: String?
        var dataAnalysis: String?
        var methodology: String?
        var theoreticalFoundation: String?
        var educationalLevel: String?
        var country: String?
        var keywords: String?
        var limitations: String?
    }

    var pageURL: String?
    var pageTitle: String?
    var pdfURL: String?
    var pdfURLCandidates: [String]?
    var pdfDataBase64: String?
    var pdfFileName: String?
    var pdfContentType: String?
    var pdfByteLength: Int?
    var metadata: Metadata?
}

@MainActor
final class LitrixWebImportService {
    private let store: LibraryStore
    private let fileManager = FileManager.default

    init(store: LibraryStore) {
        self.store = store
    }

    func importFromJSONData(_ data: Data) async throws -> [String: Any] {
        let decoder = JSONDecoder()
        let request: LitrixWebImportRequest
        do {
            request = try decoder.decode(LitrixWebImportRequest.self, from: data)
        } catch {
            throw LitrixWebImportError.badRequest("Invalid web import JSON payload")
        }

        return try await importRequest(request)
    }

    private func importRequest(_ request: LitrixWebImportRequest) async throws -> [String: Any] {
        let pageURL = nonEmpty(request.pageURL)
        let pageTitle = nonEmpty(request.pageTitle)
        let metadata = request.metadata ?? .init()

        guard pageTitle != nil || !metadata.isEmpty || nonEmpty(request.pdfURL) != nil || nonEmpty(request.pdfDataBase64) != nil else {
            throw LitrixWebImportError.badRequest("Web import requires at least a page title, pdfURL, or extracted metadata.")
        }

        var warning: String?
        if let temporaryPDFURL = writeInlinePDFIfAvailable(from: request) {
            defer { try? fileManager.removeItem(at: temporaryPDFURL) }

            let importResult = store.importPDFs(from: [temporaryPDFURL], shouldPersist: true)
            if let importedID = importResult.importedPaperIDs.first,
               var paper = store.paper(id: importedID) {
                apply(metadata: metadata, pageTitle: pageTitle, pageURL: pageURL, to: &paper)
                store.updatePaper(paper)
                let refreshed = store.paper(id: importedID) ?? paper
                let duplicateWarning = importWarning(from: importResult)
                return makeResponse(
                    paper: refreshed,
                    created: true,
                    importedPDF: true,
                    duplicate: !importResult.duplicateTitles.isEmpty,
                    warning: duplicateWarning,
                    pageURL: pageURL,
                    pdfURL: nonEmpty(request.pdfURL)
                )
            }
            warning = importWarning(from: importResult)
        } else if nonEmpty(request.pdfDataBase64) != nil {
            warning = "Browser PDF transfer failed: inline PDF data was invalid or not a PDF."
        }

        let pdfURLCandidates = await candidatePDFURLs(from: request, metadata: metadata)
        for pdfURLString in pdfURLCandidates {
            guard let pdfURL = URL(string: pdfURLString) else { continue }

            do {
                let temporaryPDFURL = try await downloadPDF(from: pdfURL, referer: pageURL)
                defer { try? fileManager.removeItem(at: temporaryPDFURL) }

                let importResult = store.importPDFs(from: [temporaryPDFURL], shouldPersist: true)
                if let importedID = importResult.importedPaperIDs.first,
                   var paper = store.paper(id: importedID) {
                    apply(metadata: metadata, pageTitle: pageTitle, pageURL: pageURL, to: &paper)
                    store.updatePaper(paper)
                    let refreshed = store.paper(id: importedID) ?? paper
                    let duplicateWarning = importWarning(from: importResult)
                    return makeResponse(
                        paper: refreshed,
                        created: true,
                        importedPDF: true,
                        duplicate: !importResult.duplicateTitles.isEmpty,
                        warning: duplicateWarning,
                        pageURL: pageURL,
                        pdfURL: pdfURLString
                    )
                }

                warning = importWarning(from: importResult)
            } catch {
                warning = "PDF download failed: \(error.localizedDescription)"
                continue
            }
        }

        let metadataOnlyPaper = buildMetadataOnlyPaper(
            metadata: metadata,
            pageTitle: pageTitle,
            pageURL: pageURL
        )

        let duplicate = store.hasPotentialDuplicate(metadataOnlyPaper)
        let created = store.addMetadataOnlyPaper(metadataOnlyPaper)
        if created {
            let persisted = store.paper(id: metadataOnlyPaper.id) ?? metadataOnlyPaper
            return makeResponse(
                paper: persisted,
                created: true,
                importedPDF: false,
                duplicate: duplicate,
                warning: warning ?? (duplicate ? "Possible duplicate detected. Imported anyway." : nil),
                pageURL: pageURL,
                pdfURL: nonEmpty(request.pdfURL)
            )
        }

        return makeResponse(
            paper: metadataOnlyPaper,
            created: false,
            importedPDF: false,
            duplicate: true,
            warning: warning ?? "Possible duplicate detected.",
            pageURL: pageURL,
            pdfURL: nonEmpty(request.pdfURL)
        )
    }

    private func candidatePDFURLs(
        from request: LitrixWebImportRequest,
        metadata: LitrixWebImportRequest.Metadata
    ) async -> [String] {
        var candidates = directPDFURLCandidates(from: request)
        if let doi = normalizedDOI(metadata.doi) {
            let openAccessCandidates = await openAccessPDFURLCandidates(forDOI: doi)
            candidates.append(contentsOf: openAccessCandidates)
        }
        return uniqueHTTPURLs(candidates)
    }

    private func directPDFURLCandidates(from request: LitrixWebImportRequest) -> [String] {
        let candidates = [request.pdfURL].compactMap { $0 } + (request.pdfURLCandidates ?? [])
        return uniqueHTTPURLs(candidates)
    }

    private func uniqueHTTPURLs(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for candidate in candidates {
            guard let trimmed = nonEmpty(candidate),
                  let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(key)
        }
        return result
    }

    private func openAccessPDFURLCandidates(forDOI doi: String) async -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: await openAlexPDFURLCandidates(forDOI: doi))
        candidates.append(contentsOf: await unpaywallPDFURLCandidates(forDOI: doi))
        return uniqueHTTPURLs(candidates)
    }

    private func openAlexPDFURLCandidates(forDOI doi: String) async -> [String] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openalex.org"
        components.path = "/works/https://doi.org/\(doi)"
        components.queryItems = [URLQueryItem(name: "mailto", value: "litrix@example.invalid")]
        guard let url = components.url,
              let object = await fetchJSONObject(from: url) else {
            return []
        }
        return pdfURLs(fromOpenAccessObject: object, locationArrayKeys: ["locations"])
    }

    private func unpaywallPDFURLCandidates(forDOI doi: String) async -> [String] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.unpaywall.org"
        components.path = "/v2/\(urlPathComponentEscaped(doi))"
        components.queryItems = [URLQueryItem(name: "email", value: "litrix@example.invalid")]
        guard let url = components.url,
              let object = await fetchJSONObject(from: url) else {
            return []
        }
        return pdfURLs(fromOpenAccessObject: object, locationArrayKeys: ["oa_locations"])
    }

    private func fetchJSONObject(from url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        } catch {
            return nil
        }
    }

    private func pdfURLs(
        fromOpenAccessObject object: [String: Any],
        locationArrayKeys: [String]
    ) -> [String] {
        var candidates: [String] = []
        for key in ["best_oa_location", "primary_location"] {
            if let location = object[key] as? [String: Any] {
                candidates.append(contentsOf: pdfURLs(fromLocation: location))
            }
        }
        for key in locationArrayKeys {
            if let locations = object[key] as? [[String: Any]] {
                for location in locations {
                    candidates.append(contentsOf: pdfURLs(fromLocation: location))
                }
            }
        }
        return candidates
    }

    private func pdfURLs(fromLocation location: [String: Any]) -> [String] {
        [
            location["pdf_url"] as? String,
            location["url_for_pdf"] as? String
        ].compactMap { $0 }
    }

    private func normalizedDOI(_ value: String?) -> String? {
        var doi = nonEmpty(value)?
            .replacingOccurrences(of: "https://doi.org/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "http://doi.org/", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "doi:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if doi.lowercased().hasPrefix("doi ") {
            doi = String(doi.dropFirst(4))
        }
        return nonEmpty(doi)
    }

    private func urlPathComponentEscaped(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func writeInlinePDFIfAvailable(from request: LitrixWebImportRequest) -> URL? {
        guard let base64 = nonEmpty(request.pdfDataBase64),
              let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            return nil
        }

        let declaredType = request.pdfContentType?.lowercased() ?? ""
        let fileName = sanitizedPDFFileName(
            preferred: request.pdfFileName ?? "Litrix-Web.pdf",
            fallback: "Litrix-Web-\(UUID().uuidString).pdf"
        )
        let looksLikePDF = declaredType.contains("pdf")
            || fileName.lowercased().hasSuffix(".pdf")
            || data.hasPDFHeader
        guard looksLikePDF else {
            return nil
        }

        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("litrix-web-import-\(UUID().uuidString)-\(fileName)", isDirectory: false)
        do {
            try data.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        } catch {
            return nil
        }
    }

    private func downloadPDF(from url: URL, referer: String?) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/pdf,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer = nonEmpty(referer) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw LitrixWebImportError.badRequest("Remote PDF request did not return a successful HTTP status.")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let looksLikePDF = contentType.contains("application/pdf")
            || url.pathExtension.lowercased() == "pdf"
            || data.hasPDFHeader
        guard looksLikePDF else {
            throw LitrixWebImportError.badRequest("Remote file is not a PDF.")
        }

        let fileName = sanitizedPDFFileName(
            preferred: httpResponse.suggestedFilename ?? url.lastPathComponent,
            fallback: "Litrix-Web-\(UUID().uuidString).pdf"
        )
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("litrix-web-import-\(UUID().uuidString)-\(fileName)", isDirectory: false)
        try fileManager.createDirectory(at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: temporaryURL, options: .atomic)
        return temporaryURL
    }

    private func buildMetadataOnlyPaper(
        metadata: LitrixWebImportRequest.Metadata,
        pageTitle: String?,
        pageURL: String?
    ) -> Paper {
        let paper = Paper(
            title: normalizedMetadataValue(firstNonEmpty(metadata.title, pageTitle), field: .title) ?? "Untitled Import",
            englishTitle: normalizedMetadataValue(firstNonEmpty(metadata.englishTitle), field: .englishTitle) ?? "",
            authors: normalizedMetadataValue(firstNonEmpty(metadata.authors), field: .authors) ?? "",
            authorsEnglish: normalizedMetadataValue(firstNonEmpty(metadata.authorsEnglish), field: .authorsEnglish) ?? "",
            year: normalizedMetadataValue(firstNonEmpty(metadata.year), field: .year) ?? "",
            source: normalizedMetadataValue(firstNonEmpty(metadata.source), field: .source) ?? "",
            doi: normalizedMetadataValue(firstNonEmpty(metadata.doi), field: .doi) ?? "",
            abstractText: firstNonEmpty(metadata.abstractText) ?? "",
            chineseAbstract: normalizedMetadataValue(firstNonEmpty(metadata.chineseAbstract), field: .chineseAbstract) ?? "",
            notes: firstNonEmpty(metadata.notes) ?? "",
            collections: normalizedList(metadata.collections),
            tags: normalizedList(metadata.tags),
            paperType: normalizedMetadataValue(firstNonEmpty(metadata.paperType), field: .paperType) ?? "电子文献",
            volume: normalizedMetadataValue(firstNonEmpty(metadata.volume), field: .volume) ?? "",
            issue: normalizedMetadataValue(firstNonEmpty(metadata.issue), field: .issue) ?? "",
            pages: normalizedMetadataValue(firstNonEmpty(metadata.pages), field: .pages) ?? "",
            rqs: normalizedMetadataValue(firstNonEmpty(metadata.rqs), field: .rqs) ?? "",
            conclusion: normalizedMetadataValue(firstNonEmpty(metadata.conclusion), field: .conclusion) ?? "",
            results: normalizedMetadataValue(firstNonEmpty(metadata.results), field: .results) ?? "",
            category: normalizedMetadataValue(firstNonEmpty(metadata.category), field: .category) ?? "",
            impactFactor: normalizedMetadataValue(firstNonEmpty(metadata.impactFactor), field: .impactFactor) ?? "",
            samples: normalizedMetadataValue(firstNonEmpty(metadata.samples), field: .samples) ?? "",
            participantType: normalizedMetadataValue(firstNonEmpty(metadata.participantType), field: .participantType) ?? "",
            variables: normalizedMetadataValue(firstNonEmpty(metadata.variables), field: .variables) ?? "",
            dataCollection: normalizedMetadataValue(firstNonEmpty(metadata.dataCollection), field: .dataCollection) ?? "",
            dataAnalysis: normalizedMetadataValue(firstNonEmpty(metadata.dataAnalysis), field: .dataAnalysis) ?? "",
            methodology: normalizedMetadataValue(firstNonEmpty(metadata.methodology), field: .methodology) ?? "",
            theoreticalFoundation: normalizedMetadataValue(firstNonEmpty(metadata.theoreticalFoundation), field: .theoreticalFoundation) ?? "",
            educationalLevel: normalizedMetadataValue(firstNonEmpty(metadata.educationalLevel), field: .educationalLevel) ?? "",
            country: normalizedMetadataValue(firstNonEmpty(metadata.country), field: .country) ?? "",
            keywords: normalizedMetadataValue(firstNonEmpty(metadata.keywords), field: .keywords) ?? "",
            limitations: normalizedMetadataValue(firstNonEmpty(metadata.limitations), field: .limitations) ?? "",
            webPageURL: pageURL ?? ""
        )
        return paper
    }

    private func apply(
        metadata: LitrixWebImportRequest.Metadata,
        pageTitle: String?,
        pageURL: String?,
        to paper: inout Paper
    ) {
        update(&paper.title, using: normalizedMetadataValue(firstNonEmpty(metadata.title, pageTitle), field: .title))
        update(&paper.englishTitle, using: normalizedMetadataValue(firstNonEmpty(metadata.englishTitle), field: .englishTitle))
        update(&paper.authors, using: normalizedMetadataValue(firstNonEmpty(metadata.authors), field: .authors))
        update(&paper.authorsEnglish, using: normalizedMetadataValue(firstNonEmpty(metadata.authorsEnglish), field: .authorsEnglish))
        update(&paper.year, using: normalizedMetadataValue(firstNonEmpty(metadata.year), field: .year))
        update(&paper.source, using: normalizedMetadataValue(firstNonEmpty(metadata.source), field: .source))
        update(&paper.doi, using: normalizedMetadataValue(firstNonEmpty(metadata.doi), field: .doi))
        update(&paper.abstractText, using: firstNonEmpty(metadata.abstractText))
        update(&paper.chineseAbstract, using: normalizedMetadataValue(firstNonEmpty(metadata.chineseAbstract), field: .chineseAbstract))
        update(&paper.paperType, using: normalizedMetadataValue(firstNonEmpty(metadata.paperType), field: .paperType))
        update(&paper.volume, using: normalizedMetadataValue(firstNonEmpty(metadata.volume), field: .volume))
        update(&paper.issue, using: normalizedMetadataValue(firstNonEmpty(metadata.issue), field: .issue))
        update(&paper.pages, using: normalizedMetadataValue(firstNonEmpty(metadata.pages), field: .pages))
        update(&paper.rqs, using: normalizedMetadataValue(firstNonEmpty(metadata.rqs), field: .rqs))
        update(&paper.conclusion, using: normalizedMetadataValue(firstNonEmpty(metadata.conclusion), field: .conclusion))
        update(&paper.results, using: normalizedMetadataValue(firstNonEmpty(metadata.results), field: .results))
        update(&paper.category, using: normalizedMetadataValue(firstNonEmpty(metadata.category), field: .category))
        update(&paper.impactFactor, using: normalizedMetadataValue(firstNonEmpty(metadata.impactFactor), field: .impactFactor))
        update(&paper.samples, using: normalizedMetadataValue(firstNonEmpty(metadata.samples), field: .samples))
        update(&paper.participantType, using: normalizedMetadataValue(firstNonEmpty(metadata.participantType), field: .participantType))
        update(&paper.variables, using: normalizedMetadataValue(firstNonEmpty(metadata.variables), field: .variables))
        update(&paper.dataCollection, using: normalizedMetadataValue(firstNonEmpty(metadata.dataCollection), field: .dataCollection))
        update(&paper.dataAnalysis, using: normalizedMetadataValue(firstNonEmpty(metadata.dataAnalysis), field: .dataAnalysis))
        update(&paper.methodology, using: normalizedMetadataValue(firstNonEmpty(metadata.methodology), field: .methodology))
        update(&paper.theoreticalFoundation, using: normalizedMetadataValue(firstNonEmpty(metadata.theoreticalFoundation), field: .theoreticalFoundation))
        update(&paper.educationalLevel, using: normalizedMetadataValue(firstNonEmpty(metadata.educationalLevel), field: .educationalLevel))
        update(&paper.country, using: normalizedMetadataValue(firstNonEmpty(metadata.country), field: .country))
        update(&paper.keywords, using: normalizedMetadataValue(firstNonEmpty(metadata.keywords), field: .keywords))
        update(&paper.limitations, using: normalizedMetadataValue(firstNonEmpty(metadata.limitations), field: .limitations))
        update(&paper.webPageURL, using: pageURL)

        if let notes = firstNonEmpty(metadata.notes) {
            paper.notes = paper.notes.isEmpty ? notes : "\(notes)\n\n\(paper.notes)"
        }

        if !normalizedList(metadata.tags).isEmpty {
            paper.tags = merge(existing: paper.tags, incoming: normalizedList(metadata.tags))
        }
        if !normalizedList(metadata.collections).isEmpty {
            paper.collections = merge(existing: paper.collections, incoming: normalizedList(metadata.collections))
        }
    }

    private func importWarning(from result: PDFImportResult) -> String? {
        if let duplicate = result.duplicateTitles.first {
            return "Possible duplicate detected and imported anyway: \(duplicate)"
        }
        if let failed = result.failedFiles.first {
            return "PDF import failed for \(failed). A metadata-only item was created instead."
        }
        return nil
    }

    private func makeResponse(
        paper: Paper,
        created: Bool,
        importedPDF: Bool,
        duplicate: Bool,
        warning: String?,
        pageURL: String?,
        pdfURL: String?
    ) -> [String: Any] {
        var item: [String: Any] = [
            "id": paper.id.uuidString,
            "title": paper.title,
            "authors": paper.authors,
            "year": paper.year,
            "source": paper.source,
            "doi": paper.doi,
            "webPageURL": paper.webPageURL,
            "hasPDF": paper.storedPDFFileName != nil
        ]
        if let storedPDFFileName = paper.storedPDFFileName {
            item["storedPDFFileName"] = storedPDFFileName
        }

        var response: [String: Any] = [
            "created": created,
            "importedPDF": importedPDF,
            "duplicate": duplicate,
            "item": item
        ]
        if let warning {
            response["warning"] = warning
        }
        if let pageURL {
            response["pageURL"] = pageURL
        }
        if let pdfURL {
            response["pdfURL"] = pdfURL
        }
        return response
    }

    private func update(_ target: inout String, using candidate: String?) {
        guard let candidate = firstNonEmpty(candidate) else { return }
        target = candidate
    }

    private func merge(existing: [String], incoming: [String]) -> [String] {
        Array(Set(existing + incoming)).sorted()
    }

    private func normalizedList(_ values: [String]?) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values ?? [] {
            let parts = value
                .split(whereSeparator: { $0 == "；" || $0 == ";" })
                .map(String.init)
            for part in parts {
                guard let item = nonEmpty(part) else { continue }
                let key = item.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard seen.insert(key).inserted else { continue }
                result.append(item)
            }
        }
        return result
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(nonEmpty).first
    }

    private func normalizedMetadataValue(_ value: String?, field: MetadataField) -> String? {
        let normalized = MetadataValueNormalizer.normalize(value ?? "", for: field)
        return normalized.isEmpty ? nil : normalized
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sanitizedPDFFileName(preferred: String, fallback: String) -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        var safe = rawName.components(separatedBy: invalidCharacters).joined(separator: "-")
        if safe.count > 180 {
            safe = String(safe.prefix(180))
        }
        return safe.lowercased().hasSuffix(".pdf") ? safe : "\(safe).pdf"
    }
}

private extension Data {
    var hasPDFHeader: Bool {
        count >= 5 && self[startIndex..<(startIndex + 5)] == Data("%PDF-".utf8)
    }
}

private extension LitrixWebImportRequest.Metadata {
    var isEmpty: Bool {
        [
            title,
            englishTitle,
            authors,
            authorsEnglish,
            year,
            source,
            doi,
            abstractText,
            chineseAbstract,
            notes,
            paperType,
            volume,
            issue,
            pages,
            rqs,
            conclusion,
            results,
            category,
            impactFactor,
            samples,
            participantType,
            variables,
            dataCollection,
            dataAnalysis,
            methodology,
            theoreticalFoundation,
            educationalLevel,
            country,
            keywords,
            limitations
        ]
        .allSatisfy { ($0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty }
            && (tags ?? []).isEmpty
            && (collections ?? []).isEmpty
    }
}
