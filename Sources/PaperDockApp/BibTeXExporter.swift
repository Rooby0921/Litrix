import AppKit
import Foundation

enum BibTeXExporter {
    static func exportText(for paper: Paper, fields: BibTeXExportFieldOptions = BibTeXExportFieldOptions()) -> String {
        let citeKey = makeCiteKey(for: paper)
        let type = bibType(for: paper.paperType)

        var entries: [(String, String)] = []
        if fields.title {
            appendField("title", paper.title, to: &entries)
        }
        if fields.author {
            appendField("author", normalizeAuthors(paper.authors), to: &entries)
        }
        if fields.year {
            appendField("year", paper.year, to: &entries)
        }
        if fields.journal {
            appendField("journal", paper.source, to: &entries)
        }
        if fields.doi {
            appendField("doi", paper.doi, to: &entries)
        }
        if fields.abstract {
            appendField("abstract", paper.abstractText, to: &entries)
        }
        if fields.volume {
            appendField("volume", paper.volume, to: &entries)
        }
        if fields.number {
            appendField("number", paper.issue, to: &entries)
        }
        if fields.pages {
            appendField("pages", paper.pages, to: &entries)
        }

        let body = entries
            .map { "  \($0.0) = {\($0.1)}" }
            .joined(separator: ",\n")

        return "@\(type){\(citeKey),\n\(body)\n}\n"
    }

    @MainActor
    static func save(_ text: String, suggestedFileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bib")!]
        panel.nameFieldStringValue = suggestedFileName

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("导出 BibTeX 失败: \(error.localizedDescription)")
        }
    }

    private static func appendField(_ key: String, _ value: String, to fields: inout [(String, String)]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fields.append((key, trimmed.replacingOccurrences(of: "\n", with: " ")))
    }

    private static func normalizeAuthors(_ authors: String) -> String {
        authors
            .replacingOccurrences(of: "和", with: " and ")
            .replacingOccurrences(of: ",", with: " and ")
            .replacingOccurrences(of: "，", with: " and ")
    }

    private static func bibType(for paperType: String) -> String {
        switch paperType {
        case "会议论文":
            return "inproceedings"
        case "书籍":
            return "book"
        default:
            return "article"
        }
    }

    private static func makeCiteKey(for paper: Paper) -> String {
        let authorHead = paper.authors
            .components(separatedBy: CharacterSet(charactersIn: ",，和 "))
            .first?
            .filter { $0.isLetter || $0.isNumber } ?? "paper"

        let year = paper.year.isEmpty ? "n.d." : paper.year
        return "\(authorHead)\(year)"
    }
}
