import Foundation
import PDFKit

struct ParsedPaperMetadata {
    var title: String
    var authors: String
    var year: String
}

enum FileNameParser {
    static func parse(url: URL) -> ParsedPaperMetadata {
        let fileStem = url.deletingPathExtension().lastPathComponent
        let fallback = parseFileNameStem(fileStem)

        guard let document = PDFDocument(url: url) else {
            return fallback
        }

        let attributes = document.documentAttributes ?? [:]
        let rawTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawAuthor = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ParsedPaperMetadata(
            title: rawTitle.isEmpty ? fallback.title : rawTitle,
            authors: rawAuthor.isEmpty ? fallback.authors : rawAuthor,
            year: fallback.year
        )
    }

    private static func parseFileNameStem(_ stem: String) -> ParsedPaperMetadata {
        let parts = stem
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = parts.first ?? stem
        let authors = parts.count > 1 ? parts[1] : ""
        let yearCandidate = parts.count > 2 ? parts[2] : ""
        let year = yearCandidate.range(of: #"(?<!\d)(19|20)\d{2}(?!\d)"#, options: .regularExpression)
            .map { String(yearCandidate[$0]) } ?? ""

        return ParsedPaperMetadata(title: title, authors: authors, year: year)
    }
}
