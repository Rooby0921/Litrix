import AppKit
import Darwin
import Foundation
import PDFKit

struct PDFImportResult {
    var importedPaperIDs: [UUID] = []
    var duplicateTitles: [String] = []
    var failedFiles: [String] = []

    static let empty = PDFImportResult()
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var papers: [Paper] = [] {
        didSet {
            recomputeSidebarCountSnapshot()
            dataRevision &+= 1
        }
    }
    @Published private(set) var collections: [String] = []
    @Published private(set) var tags: [String] = []
    @Published private(set) var tagColorHexes: [String: String] = [:]
    @Published private(set) var dataRevision: Int = 0

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let legacyNoteFileName = "Note.txt"
    private let canonicalNoteFileName = "note.txt"
    private let imagesDirectoryName = "images"
    private let settings: SettingsStore
    private var sidebarCountSnapshot = SidebarCountSnapshot.empty
    private var stableSelectionPaperIDs: [SidebarSelection: [UUID]] = [:]
    private var paperIndexByID: [UUID: Int] = [:]
    private var attachmentPresenceCache: [UUID: AttachmentPresenceCacheEntry] = [:]
    private var lastAttachmentPresenceRevalidationAt: Date = .distantPast
    private var lastDynamicCountConfig = DynamicCountConfig(
        recentReadingInterval: 0,
        zombieInterval: 0
    )
    private var pendingSaveTask: Task<Void, Never>?
    private var lastBackupWriteAt: Date = .distantPast
    private var terminateObserver: NSObjectProtocol?

    private struct SidebarCountSnapshot {
        var all = 0
        var recentReading = 0
        var zombiePapers = 0
        var unfiled = 0
        var missingDOI = 0
        var missingAttachment = 0
        var collections: [String: Int] = [:]
        var tags: [String: Int] = [:]

        static let empty = SidebarCountSnapshot()
    }

    private struct AttachmentPresenceCacheEntry {
        var pdfPath: String?
        var isMissing: Bool
    }

    private struct DynamicCountConfig: Equatable {
        var recentReadingInterval: TimeInterval
        var zombieInterval: TimeInterval
    }

    init(settings: SettingsStore) {
        self.settings = settings
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushPendingSaveNow()
            }
        }

        load()
    }

    var papersStorageRootURL: URL {
        papersDirectory
    }

    func currentLibrarySnapshot() -> LibrarySnapshot {
        LibrarySnapshot(
            papers: papers,
            collections: collections,
            tags: tags,
            tagColorHexes: tagColorHexes
        )
    }

    func restoreLibrarySnapshot(_ snapshot: LibrarySnapshot) {
        papers = snapshot.papers
            .map { hydratePaperAssets(for: migratePaperIfNeeded($0)) }
            .sorted(by: { $0.addedAtMilliseconds > $1.addedAtMilliseconds })
        collections = snapshot.collections
        tags = snapshot.tags
        tagColorHexes = snapshot.tagColorHexes
        syncTaxonomies()
        save()
    }

    @discardableResult
    func writeImportCheckpoint() -> URL? {
        do {
            try ensureStorageDirectories()
            let snapshot = currentLibrarySnapshot()
            let data = try encoder.encode(snapshot)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let fileURL = backupsDirectory.appendingPathComponent(
                "pre-import-library-\(formatter.string(from: .now)).json",
                isDirectory: false
            )
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("写入资料库导入快照失败: \(error.localizedDescription)")
            return nil
        }
    }

    func importPDFs(from urls: [URL], shouldPersist: Bool = true) -> PDFImportResult {
        guard !urls.isEmpty else { return .empty }

        var result = PDFImportResult()

        do {
            try ensureStorageDirectories()
        } catch {
            NSSound.beep()
            print("导入 PDF 前准备存储目录失败: \(error.localizedDescription)")
            result.failedFiles = urls.map(\.lastPathComponent)
            return result
        }

        var existingTitleKeys = Set(
            papers
                .map(\.title)
                .map(normalizedPaperTitle)
                .filter { !$0.isEmpty }
        )
        var existingDOIKeys = Set(
            papers
                .map(\.doi)
                .map(normalizedDOI)
                .filter { !$0.isEmpty }
        )

        for url in urls {
            autoreleasepool {
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if needsAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let parsed = FileNameParser.parse(url: url)
                let extracted = extractPDFCoreMetadata(from: url)
                let resolvedTitle: String = {
                    let extractedTitle = extracted.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extractedTitle.isEmpty {
                        return extractedTitle
                    }
                    return parsed.title.isEmpty ? url.deletingPathExtension().lastPathComponent : parsed.title
                }()
                let resolvedAuthors: String = {
                    let extractedAuthors = extracted.authors.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extractedAuthors.isEmpty {
                        return extractedAuthors
                    }
                    return parsed.authors
                }()
                let resolvedYear: String = {
                    let extractedYear = extracted.year.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extractedYear.isEmpty {
                        return extractedYear
                    }
                    return parsed.year
                }()
                let resolvedDOI = extracted.doi.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedTitle = normalizedPaperTitle(resolvedTitle)
                let normalizedResolvedDOI = normalizedDOI(resolvedDOI)

                if !normalizedResolvedDOI.isEmpty, existingDOIKeys.contains(normalizedResolvedDOI) {
                    result.duplicateTitles.append(resolvedDOI.isEmpty ? resolvedTitle : "\(resolvedTitle) [\(resolvedDOI)]")
                    return
                }

                if !normalizedTitle.isEmpty, existingTitleKeys.contains(normalizedTitle) {
                    result.duplicateTitles.append(resolvedTitle)
                    return
                }

                do {
                    let importedAssets = try importPaperAssets(from: url)
                    let paper = Paper(
                        title: resolvedTitle,
                        authors: resolvedAuthors,
                        year: resolvedYear,
                        doi: resolvedDOI,
                        notes: "",
                        storageFolderName: importedAssets.folderName,
                        storedPDFFileName: importedAssets.pdfURL.lastPathComponent,
                        originalPDFFileName: url.lastPathComponent,
                        imageFileNames: []
                    )
                    papers.insert(paper, at: 0)
                    if settings.autoRenameImportedPDFFiles {
                        _ = renameStoredPDF(forPaperID: paper.id, shouldPersist: false)
                    }
                    result.importedPaperIDs.append(paper.id)
                    if !normalizedTitle.isEmpty {
                        existingTitleKeys.insert(normalizedTitle)
                    }
                    if !normalizedResolvedDOI.isEmpty {
                        existingDOIKeys.insert(normalizedResolvedDOI)
                    }
                } catch {
                    result.failedFiles.append(url.lastPathComponent)
                    print("导入 PDF 失败(\(url.lastPathComponent)): \(error.localizedDescription)")
                }
            }
        }

        if !result.importedPaperIDs.isEmpty, shouldPersist {
            syncTaxonomies()
            save()
        }

        if !result.failedFiles.isEmpty {
            NSSound.beep()
        }

        return result
    }

    func finalizePendingPDFImportIfNeeded() {
        syncTaxonomies()
        save()
    }

    func importBibTeX(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        var imported: [Paper] = []
        for url in urls {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let entries = parseBibTeXEntries(from: text)
            for entry in entries {
                imported.append(paper(from: entry))
            }
        }

        guard !imported.isEmpty else { return }
        papers.insert(contentsOf: imported, at: 0)
        syncTaxonomies()
        save()
    }

    func addMetadataOnlyPaper(_ paper: Paper) {
        if isDuplicatePaper(title: paper.title, doi: paper.doi) {
            return
        }
        papers.insert(paper, at: 0)
        syncTaxonomies()
        save()
    }

    func importLitrixLibrary(
        _ snapshot: LibrarySnapshot,
        archivePapersDirectory: URL,
        selection: LitrixImportSelection,
        resolveDuplicate: (LitrixDuplicateCandidate) -> LitrixDuplicateResolution
    ) -> LitrixImportReport {
        var report = LitrixImportReport()

        let shouldProcessPapers = selection.includePapers || selection.includeNotes || selection.includeAttachments
        guard shouldProcessPapers else {
            return report
        }

        do {
            try ensureStorageDirectories()
        } catch {
            report.failedTitles.append("初始化导入目录失败")
            return report
        }

        for incomingPaper in snapshot.papers {
            if let duplicate = duplicatePaperIndex(for: incomingPaper) {
                report.duplicateConflicts += 1
                let candidate = LitrixDuplicateCandidate(
                    existingPaper: papers[duplicate.index],
                    incomingPaper: incomingPaper,
                    reason: duplicate.reason
                )
                let resolution = resolveDuplicate(candidate)
                switch resolution {
                case .skip:
                    report.skipped += 1
                    continue
                case .overwrite:
                    do {
                        try overwriteImportedPaper(
                            at: duplicate.index,
                            with: incomingPaper,
                            archivePapersDirectory: archivePapersDirectory,
                            selection: selection
                        )
                        report.overwritten += 1
                    } catch {
                        report.failedTitles.append(normalizedTitle(incomingPaper.title))
                    }
                case .rename:
                    do {
                        var renamed = incomingPaper
                        renamed.title = uniqueRenamedTitle(from: incomingPaper.title)
                        try insertImportedPaper(
                            renamed,
                            archivePapersDirectory: archivePapersDirectory,
                            selection: selection
                        )
                        report.renamed += 1
                        if !selection.includePapers {
                            report.orphanCreated += 1
                        }
                    } catch {
                        report.failedTitles.append(normalizedTitle(incomingPaper.title))
                    }
                }
                continue
            }

            do {
                let createdAsOrphan = !selection.includePapers
                try insertImportedPaper(
                    incomingPaper,
                    archivePapersDirectory: archivePapersDirectory,
                    selection: selection
                )
                report.added += 1
                if createdAsOrphan {
                    report.orphanCreated += 1
                }
            } catch {
                report.failedTitles.append(normalizedTitle(incomingPaper.title))
            }
        }

        if selection.includePapers {
            mergeImportedTaxonomies(from: snapshot)
        }

        syncTaxonomies()
        save()
        return report
    }

    func importWorkspacePapersIfAvailable() {
        guard let workspacePapersDirectory else { return }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: workspacePapersDirectory,
                includingPropertiesForKeys: nil
            )
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            _ = importPDFs(from: pdfs)
        } catch {
            NSSound.beep()
            print("读取工作区 papers 目录失败: \(error.localizedDescription)")
        }
    }

    func updatePaper(_ paper: Paper, preserveExplicitLastEditedTimestamp: Bool = false) {
        guard let index = indexOfPaper(id: paper.id) else { return }
        let previous = papers[index]
        var updated = paper
        let shouldAutoUpdateEditedTimestamp =
            !preserveExplicitLastEditedTimestamp
            || previous.lastEditedAtMilliseconds == updated.lastEditedAtMilliseconds
        if hasMetadataEdit(previous: previous, updated: updated),
           shouldAutoUpdateEditedTimestamp {
            updated.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        }
        papers[index] = updated
        if previous.notes != updated.notes
            || previous.title != updated.title
            || previous.storageFolderName != updated.storageFolderName {
            writeNoteFileIfPossible(for: updated)
        }
        if previous.collections != updated.collections || previous.tags != updated.tags {
            syncTaxonomies()
        }
        save()
    }

    func createCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !collections.contains(trimmed) else { return }
        collections = (collections + [trimmed]).uniquedAndSorted()
        save()
    }

    func createTag(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(trimmed) else { return }
        tags = (tags + [trimmed]).uniquedAndSorted()
        save()
    }

    func renameTag(oldName: String, newName: String) {
        let oldTrimmed = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty, oldTrimmed != newTrimmed else { return }
        guard tags.contains(oldTrimmed) else { return }
        guard !tags.contains(newTrimmed) else { return }

        tags = tags.map { $0 == oldTrimmed ? newTrimmed : $0 }.uniquedAndSorted()

        for index in papers.indices {
            var paper = papers[index]
            if paper.tags.contains(oldTrimmed) {
                paper.tags = paper.tags.map { $0 == oldTrimmed ? newTrimmed : $0 }.uniquedAndSorted()
                papers[index] = paper
            }
        }

        if let color = tagColorHexes.removeValue(forKey: oldTrimmed) {
            tagColorHexes[newTrimmed] = color
        }

        syncTaxonomies()
        save()
    }

    func deleteTag(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tags.removeAll { $0 == trimmed }
        tagColorHexes.removeValue(forKey: trimmed)

        for index in papers.indices {
            var paper = papers[index]
            if paper.tags.contains(trimmed) {
                paper.tags.removeAll { $0 == trimmed }
                papers[index] = paper
            }
        }

        syncTaxonomies()
        save()
    }

    func setTagColor(hex: String?, forTag name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard tags.contains(trimmed) else { return }

        let normalized = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            tagColorHexes[trimmed] = normalized
        } else {
            tagColorHexes.removeValue(forKey: trimmed)
        }
        save()
    }

    func tagColorHex(forTag name: String) -> String? {
        tagColorHexes[name]
    }

    func renameCollection(oldName: String, newName: String) {
        let oldTrimmed = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty, oldTrimmed != newTrimmed else { return }
        guard collections.contains(oldTrimmed) else { return }
        guard !collections.contains(newTrimmed) else { return }

        collections = collections.map { $0 == oldTrimmed ? newTrimmed : $0 }.uniquedAndSorted()

        for index in papers.indices {
            var paper = papers[index]
            if paper.collections.contains(oldTrimmed) {
                paper.collections = paper.collections.map { $0 == oldTrimmed ? newTrimmed : $0 }.uniquedAndSorted()
                papers[index] = paper
            }
        }

        syncTaxonomies()
        save()
    }

    func deleteCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        collections.removeAll { $0 == trimmed }

        for index in papers.indices {
            var paper = papers[index]
            if paper.collections.contains(trimmed) {
                paper.collections.removeAll { $0 == trimmed }
                papers[index] = paper
            }
        }

        syncTaxonomies()
        save()
    }

    func setCollection(_ name: String, assigned: Bool, forPaperID paperID: UUID) {
        setCollection(name, assigned: assigned, forPaperIDs: [paperID])
    }

    func setCollection(_ name: String, assigned: Bool, forPaperIDs paperIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let perfStart = PerformanceMonitor.now()

        var touchedPaper = false
        var seen: Set<UUID> = []
        seen.reserveCapacity(paperIDs.count)
        var nextPapers = papers

        for paperID in paperIDs {
            guard seen.insert(paperID).inserted else { continue }
            guard let index = indexOfPaper(id: paperID) else { continue }

            var paper = nextPapers[index]
            let hadCollection = paper.collections.contains(trimmed)
            if assigned {
                guard !hadCollection else { continue }
                paper.collections.append(trimmed)
            } else {
                guard hadCollection else { continue }
                paper.collections.removeAll { $0 == trimmed }
            }
            paper.collections = paper.collections.uniquedAndSorted()
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            nextPapers[index] = paper
            touchedPaper = true
        }

        var taxonomyTouched = false
        if assigned && !collections.contains(trimmed) {
            collections.append(trimmed)
            taxonomyTouched = true
        }

        guard touchedPaper || taxonomyTouched else { return }
        if touchedPaper {
            papers = nextPapers
        }
        syncTaxonomies()
        save()
        PerformanceMonitor.logElapsed(
            "LibraryStore.setCollectionBatch",
            from: perfStart,
            thresholdMS: 6
        ) {
            "assigned=\(assigned), collection=\(trimmed), requested=\(paperIDs.count)"
        }
    }

    func setTag(_ name: String, assigned: Bool, forPaperID paperID: UUID) {
        setTag(name, assigned: assigned, forPaperIDs: [paperID])
    }

    func setTag(_ name: String, assigned: Bool, forPaperIDs paperIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let perfStart = PerformanceMonitor.now()

        var touchedPaper = false
        var seen: Set<UUID> = []
        seen.reserveCapacity(paperIDs.count)
        var nextPapers = papers

        for paperID in paperIDs {
            guard seen.insert(paperID).inserted else { continue }
            guard let index = indexOfPaper(id: paperID) else { continue }

            var paper = nextPapers[index]
            let hadTag = paper.tags.contains(trimmed)
            if assigned {
                guard !hadTag else { continue }
                paper.tags.append(trimmed)
            } else {
                guard hadTag else { continue }
                paper.tags.removeAll { $0 == trimmed }
            }
            paper.tags = paper.tags.uniquedAndSorted()
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            nextPapers[index] = paper
            touchedPaper = true
        }

        var taxonomyTouched = false
        if assigned && !tags.contains(trimmed) {
            tags.append(trimmed)
            taxonomyTouched = true
        }

        guard touchedPaper || taxonomyTouched else { return }
        if touchedPaper {
            papers = nextPapers
        }
        syncTaxonomies()
        save()
        PerformanceMonitor.logElapsed(
            "LibraryStore.setTagBatch",
            from: perfStart,
            thresholdMS: 6
        ) {
            "assigned=\(assigned), tag=\(trimmed), requested=\(paperIDs.count)"
        }
    }

    func removePaper(id: UUID) {
        guard let index = indexOfPaper(id: id) else { return }
        let paper = papers.remove(at: index)
        if let folderURL = paperDirectoryURL(for: paper) {
            try? fileManager.removeItem(at: folderURL)
        } else if let pdfURL = pdfURL(for: paper) {
            try? fileManager.removeItem(at: pdfURL)
        }
        syncTaxonomies()
        save()
    }

    func pdfURL(for paper: Paper) -> URL? {
        resolvedPDFURL(for: paper)
    }

    func defaultOpenPDFURL(for paper: Paper) -> URL? {
        resolvedPreferredOpenPDFURL(for: paper) ?? resolvedPDFURL(for: paper)
    }

    func availablePDFFileNames(for paper: Paper) -> [String] {
        availablePDFURLs(for: paper).map(\.lastPathComponent)
    }

    func preferredOpenPDFFileName(for paper: Paper) -> String? {
        normalizedPDFFileName(paper.preferredOpenPDFFileName)
    }

    @discardableResult
    func setPreferredOpenPDFFileName(_ fileName: String?, forPaperID paperID: UUID) -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }
        var paper = papers[index]

        let normalizedFileName = normalizedPDFFileName(fileName)
        if let normalizedFileName {
            let availableNames = Set(availablePDFFileNames(for: paper))
            guard availableNames.contains(normalizedFileName) else { return false }
        }

        guard paper.preferredOpenPDFFileName != normalizedFileName else { return false }
        paper.preferredOpenPDFFileName = normalizedFileName
        paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = paper
        save()
        return true
    }

    func hasExistingPDFAttachment(for paper: Paper) -> Bool {
        guard let url = resolvedPDFURL(for: paper) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func paperDirectoryURL(for paper: Paper) -> URL? {
        guard let storageFolderName = paper.storageFolderName else {
            return nil
        }
        return papersDirectory.appendingPathComponent(storageFolderName, isDirectory: true)
    }

    func noteURL(for paper: Paper) -> URL? {
        guard let folderURL = paperDirectoryURL(for: paper) else { return nil }
        return canonicalNoteURL(in: folderURL)
    }

    func noteDisplayFileName(for paper: Paper) -> String {
        let trimmedTitle = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return canonicalNoteFileName
        }
        return "\(trimmedTitle) · \(canonicalNoteFileName)"
    }

    func imageURLs(for paper: Paper) -> [URL] {
        guard let folderURL = paperDirectoryURL(for: paper) else {
            return []
        }
        return paper.imageFileNames.map { imageFileName in
            existingImageURL(named: imageFileName, in: folderURL)
                ?? canonicalImageURL(named: imageFileName, in: folderURL)
        }
    }

    func imageDirectoryURL(for paper: Paper) -> URL? {
        guard let folderURL = paperDirectoryURL(for: paper) else { return nil }
        return imagesDirectoryURL(in: folderURL)
    }

    func imageURL(for paper: Paper, fileName: String) -> URL? {
        guard let folderURL = paperDirectoryURL(for: paper) else { return nil }
        return existingImageURL(named: fileName, in: folderURL)
            ?? canonicalImageURL(named: fileName, in: folderURL)
    }

    func addImages(to paperID: UUID, from urls: [URL]) {
        guard let index = indexOfPaper(id: paperID) else { return }
        var paper = papers[index]
        guard let folderURL = paperDirectoryURL(for: paper) else { return }

        do {
            let imagesDirectoryURL = try ensureImagesDirectoryExists(at: folderURL)
            for url in urls {
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                let fileName = "Image-\(UUID().uuidString).\(ext)"
                let destination = imagesDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
                try fileManager.copyItem(at: url, to: destination)
                paper.imageFileNames.append(fileName)
            }
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            papers[index] = paper
            save()
        } catch {
            NSSound.beep()
            print("保存图片失败: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func addImageFromPasteboard(to paperID: UUID) async -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }
        var paper = papers[index]
        guard let folderURL = paperDirectoryURL(for: paper) else { return false }

        let pasteboard = NSPasteboard.general
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let tiffData = image.tiffRepresentation else {
            return false
        }

        let data: Data? = await Task.detached(priority: .utility) { [tiffData] () -> Data? in
            guard let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }.value
        guard let data else {
            return false
        }

        let fileName = "Image-\(UUID().uuidString).png"

        do {
            let imagesDirectoryURL = try ensureImagesDirectoryExists(at: folderURL)
            let destination = imagesDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            paper.imageFileNames.append(fileName)
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            papers[index] = paper
            save()
            return true
        } catch {
            NSSound.beep()
            print("粘贴图片失败: \(error.localizedDescription)")
            return false
        }
    }

    func removeImage(from paperID: UUID, fileName: String) {
        guard let index = indexOfPaper(id: paperID) else { return }
        var paper = papers[index]
        guard let imageURL = imageURL(for: paper, fileName: fileName) else { return }
        try? fileManager.removeItem(at: imageURL)
        paper.imageFileNames.removeAll(where: { $0 == fileName })
        paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = paper
        save()
    }

    func revealImage(for paperID: UUID, fileName: String) {
        guard let paper = paper(id: paperID),
              let url = imageURL(for: paper, fileName: fileName) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openPDF(for paper: Paper) {
        guard let url = defaultOpenPDFURL(for: paper),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        ensureEditablePDF(at: url)
        markOpened(paperID: paper.id)
        openViaLaunchServices(url, preferredApplication: nil)
    }

    func revealPDF(for paper: Paper) {
        guard let url = resolvedPDFURL(for: paper),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @discardableResult
    func renameStoredPDF(forPaperID paperID: UUID, shouldPersist: Bool = true) -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }
        var paper = papers[index]
        guard let currentURL = pdfURL(for: paper) else { return false }
        guard fileManager.fileExists(atPath: currentURL.path) else { return false }

        let targetFileName = preferredPDFFileName(for: paper)
        guard !targetFileName.isEmpty else { return false }
        guard targetFileName != paper.storedPDFFileName else { return false }

        let destinationURL = uniquePDFDestinationURL(
            in: currentURL.deletingLastPathComponent(),
            preferredFileName: targetFileName
        )

        do {
            ensureEditablePDF(at: currentURL)
            try fileManager.moveItem(at: currentURL, to: destinationURL)
            ensureEditablePDF(at: destinationURL)

            if paper.preferredOpenPDFFileName == currentURL.lastPathComponent {
                paper.preferredOpenPDFFileName = destinationURL.lastPathComponent
            }
            paper.storedPDFFileName = destinationURL.lastPathComponent
            paper.originalPDFFileName = destinationURL.lastPathComponent
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            papers[index] = paper

            if shouldPersist {
                save()
            }
            return true
        } catch {
            print("重命名 PDF 失败(\(currentURL.lastPathComponent)): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func renameAllStoredPDFsToMetadataPattern() -> Int {
        var renamedCount = 0
        for paper in papers {
            if renameStoredPDF(forPaperID: paper.id, shouldPersist: false) {
                renamedCount += 1
            }
        }
        if renamedCount > 0 {
            save()
        }
        return renamedCount
    }

    func openBackupFolder() {
        NSWorkspace.shared.open(backupsDirectory)
    }

    func migratePapersDirectory(to newDirectory: URL) throws {
        let sourceDirectory = papersDirectory.standardizedFileURL
        let destinationDirectory = newDirectory.standardizedFileURL
        guard sourceDirectory.path != destinationDirectory.path else { return }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: sourceDirectory.path) else { return }
        try mergeDirectoryContents(from: sourceDirectory, to: destinationDirectory)
    }

    func paper(id: UUID) -> Paper? {
        guard let index = indexOfPaper(id: id) else { return nil }
        return papers[index]
    }

    func markPaperOpened(_ paperID: UUID) {
        markOpened(paperID: paperID)
    }

    func count(for selection: SidebarSelection) -> Int {
        switch selection {
        case .library(.all):
            return sidebarCountSnapshot.all
        case .library(.recentReading):
            ensureDynamicLibraryCountsFresh()
            return sidebarCountSnapshot.recentReading
        case .library(.zombiePapers):
            ensureDynamicLibraryCountsFresh()
            return sidebarCountSnapshot.zombiePapers
        case .library(.unfiled):
            return sidebarCountSnapshot.unfiled
        case .library(.missingDOI):
            return sidebarCountSnapshot.missingDOI
        case .library(.missingAttachment):
            return sidebarCountSnapshot.missingAttachment
        case .collection(let name):
            return sidebarCountSnapshot.collections[name] ?? 0
        case .tag(let name):
            return sidebarCountSnapshot.tags[name] ?? 0
        }
    }

    func filteredPapers(
        for selection: SidebarSelection,
        searchText: String,
        searchField: AdvancedSearchField? = nil
    ) -> [Paper] {
        let perfStart = PerformanceMonitor.now()
        let base: [Paper]

        switch selection {
        case .library(.all):
            base = papers
        case .library(.recentReading):
            let cutoff = Date().addingTimeInterval(-settings.recentReadingRange.interval)
            base = papers.filter { paper in
                guard let lastOpenedAt = paper.lastOpenedAt else {
                    return false
                }
                return lastOpenedAt >= cutoff
            }
        case .library(.zombiePapers):
            let cutoff = Date().addingTimeInterval(-settings.resolvedZombiePapersInterval)
            base = papers.filter { paper in
                guard paper.addedAtDate <= cutoff else { return false }
                guard let editedAt = paper.editedAtDate else { return true }
                return editedAt < cutoff
            }
        case .library(.unfiled):
            base = papersForStableSelection(.library(.unfiled))
        case .library(.missingDOI):
            base = papersForStableSelection(.library(.missingDOI))
        case .library(.missingAttachment):
            ensureAttachmentPresenceSnapshotFresh()
            base = papersForStableSelection(.library(.missingAttachment))
        case .collection(let name):
            base = papersForStableSelection(.collection(name))
        case .tag(let name):
            base = papersForStableSelection(.tag(name))
        }

        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let searchField {
            guard !normalizedSearchText.isEmpty else {
                PerformanceMonitor.logElapsed(
                    "LibraryStore.filteredPapers",
                    from: perfStart,
                    thresholdMS: 10
                ) {
                    "selection=\(selection.performanceLabel), query=none, base=\(base.count), result=\(base.count), field=\(searchField.rawValue)"
                }
                return base
            }

            let result = base.filter { paper in
                paperTextContainsQuery(normalizedSearchText, in: searchField.value(in: paper))
            }
            PerformanceMonitor.logElapsed(
                "LibraryStore.filteredPapers",
                from: perfStart,
                thresholdMS: 10
            ) {
                "selection=\(selection.performanceLabel), query=plain, base=\(base.count), result=\(result.count), field=\(searchField.rawValue)"
            }
            return result
        }

        guard let query = LibrarySearchQuery.parse(normalizedSearchText) else {
            PerformanceMonitor.logElapsed(
                "LibraryStore.filteredPapers",
                from: perfStart,
                thresholdMS: 10
            ) {
                "selection=\(selection.performanceLabel), query=none, base=\(base.count), result=\(base.count)"
            }
            return base
        }

        let result = base.filter { paper in
            switch query {
            case .plainText(let plainText):
                return matchesPlainText(plainText, in: paper)
            case .citation(let citation):
                return citation.matches(paper)
            }
        }
        let queryLabel: String = {
            switch query {
            case .plainText:
                return "plain"
            case .citation:
                return "citation"
            }
        }()
        PerformanceMonitor.logElapsed(
            "LibraryStore.filteredPapers",
            from: perfStart,
            thresholdMS: 10
        ) {
            "selection=\(selection.performanceLabel), query=\(queryLabel), base=\(base.count), result=\(result.count)"
        }
        return result
    }

    private func indexOfPaper(id: UUID) -> Int? {
        if let cached = paperIndexByID[id],
           papers.indices.contains(cached),
           papers[cached].id == id {
            return cached
        }

        guard let resolved = papers.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        paperIndexByID[id] = resolved
        return resolved
    }

    private func papersForStableSelection(_ selection: SidebarSelection) -> [Paper] {
        guard let ids = stableSelectionPaperIDs[selection], !ids.isEmpty else {
            return []
        }

        var result: [Paper] = []
        result.reserveCapacity(ids.count)

        for id in ids {
            if let index = paperIndexByID[id],
               papers.indices.contains(index),
               papers[index].id == id {
                result.append(papers[index])
                continue
            }

            guard let resolvedIndex = indexOfPaper(id: id) else { continue }
            result.append(papers[resolvedIndex])
        }

        return result
    }

    private func ensureAttachmentPresenceSnapshotFresh() {
        let age = Date().timeIntervalSince(lastAttachmentPresenceRevalidationAt)
        guard age > 1.6 else { return }
        recomputeSidebarCountSnapshot(forceAttachmentRevalidation: true)
    }

    private func ensureDynamicLibraryCountsFresh() {
        let current = DynamicCountConfig(
            recentReadingInterval: settings.recentReadingRange.interval,
            zombieInterval: settings.resolvedZombiePapersInterval
        )
        guard current != lastDynamicCountConfig else { return }
        recomputeSidebarCountSnapshot()
    }

    private func matchesPlainText(_ query: String, in paper: Paper) -> Bool {
        if paperTextContainsQuery(query, in: paper.title)
            || paperTextContainsQuery(query, in: paper.englishTitle)
            || paperTextContainsQuery(query, in: paper.authors)
            || paperTextContainsQuery(query, in: paper.authorsEnglish)
            || paperTextContainsQuery(query, in: paper.year)
            || paperTextContainsQuery(query, in: paper.source)
            || paperTextContainsQuery(query, in: paper.doi)
            || paperTextContainsQuery(query, in: paper.tagsSortKey)
            || paperTextContainsQuery(query, in: paper.paperType)
            || paperTextContainsQuery(query, in: paper.volume)
            || paperTextContainsQuery(query, in: paper.issue)
            || paperTextContainsQuery(query, in: paper.pages)
            || paperTextContainsQuery(query, in: paper.category)
            || paperTextContainsQuery(query, in: paper.impactFactor)
            || paperTextContainsQuery(query, in: paper.country)
            || paperTextContainsQuery(query, in: paper.keywords)
            || paperTextContainsQuery(query, in: paper.abstractText)
            || paperTextContainsQuery(query, in: paper.notes)
            || paperTextContainsQuery(query, in: paper.rqs)
            || paperTextContainsQuery(query, in: paper.conclusion)
            || paperTextContainsQuery(query, in: paper.results)
            || paperTextContainsQuery(query, in: paper.samples)
            || paperTextContainsQuery(query, in: paper.participantType)
            || paperTextContainsQuery(query, in: paper.variables)
            || paperTextContainsQuery(query, in: paper.dataCollection)
            || paperTextContainsQuery(query, in: paper.dataAnalysis)
            || paperTextContainsQuery(query, in: paper.methodology)
            || paperTextContainsQuery(query, in: paper.theoreticalFoundation)
            || paperTextContainsQuery(query, in: paper.educationalLevel)
            || paperTextContainsQuery(query, in: paper.limitations) {
            return true
        }

        for collection in paper.collections where paperTextContainsQuery(query, in: collection) {
            return true
        }

        for tag in paper.tags where paperTextContainsQuery(query, in: tag) {
            return true
        }

        return false
    }

    private func paperTextContainsQuery(_ query: String, in source: String) -> Bool {
        guard !query.isEmpty, !source.isEmpty else { return false }
        return source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func recomputeSidebarCountSnapshot(forceAttachmentRevalidation: Bool = false) {
        let perfStart = PerformanceMonitor.now()
        let dynamicConfig = DynamicCountConfig(
            recentReadingInterval: settings.recentReadingRange.interval,
            zombieInterval: settings.resolvedZombiePapersInterval
        )
        let now = Date()
        let recentReadingCutoff = now.addingTimeInterval(-dynamicConfig.recentReadingInterval)
        let zombieCutoff = now.addingTimeInterval(-dynamicConfig.zombieInterval)

        var snapshot = SidebarCountSnapshot.empty
        snapshot.all = papers.count
        var nextStableSelectionPaperIDs: [SidebarSelection: [UUID]] = [
            .library(.all): [],
            .library(.unfiled): [],
            .library(.missingDOI): [],
            .library(.missingAttachment): []
        ]
        var nextPaperIndexByID: [UUID: Int] = [:]
        nextPaperIndexByID.reserveCapacity(papers.count)
        var nextAttachmentPresenceCache: [UUID: AttachmentPresenceCacheEntry] = [:]
        nextAttachmentPresenceCache.reserveCapacity(papers.count)

        for (index, paper) in papers.enumerated() {
            nextPaperIndexByID[paper.id] = index
            nextStableSelectionPaperIDs[.library(.all), default: []].append(paper.id)

            if let lastOpenedAt = paper.lastOpenedAt,
               lastOpenedAt >= recentReadingCutoff {
                snapshot.recentReading += 1
            }

            if paper.addedAtDate <= zombieCutoff {
                if let editedAt = paper.editedAtDate {
                    if editedAt < zombieCutoff {
                        snapshot.zombiePapers += 1
                    }
                } else {
                    snapshot.zombiePapers += 1
                }
            }

            if paper.collections.isEmpty {
                snapshot.unfiled += 1
                nextStableSelectionPaperIDs[.library(.unfiled), default: []].append(paper.id)
            }

            if paper.doi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                snapshot.missingDOI += 1
                nextStableSelectionPaperIDs[.library(.missingDOI), default: []].append(paper.id)
            }

            let pdfPath = pdfURL(for: paper)?.path
            let hasMissingAttachment: Bool
            if !forceAttachmentRevalidation,
               let cached = attachmentPresenceCache[paper.id],
               cached.pdfPath == pdfPath {
                hasMissingAttachment = cached.isMissing
            } else {
                hasMissingAttachment = {
                    guard let pdfPath else { return true }
                    return !fileManager.fileExists(atPath: pdfPath)
                }()
            }
            nextAttachmentPresenceCache[paper.id] = AttachmentPresenceCacheEntry(
                pdfPath: pdfPath,
                isMissing: hasMissingAttachment
            )
            if hasMissingAttachment {
                snapshot.missingAttachment += 1
                nextStableSelectionPaperIDs[.library(.missingAttachment), default: []].append(paper.id)
            }

            for collection in paper.collections {
                snapshot.collections[collection, default: 0] += 1
                nextStableSelectionPaperIDs[.collection(collection), default: []].append(paper.id)
            }

            for tag in paper.tags {
                snapshot.tags[tag, default: 0] += 1
                nextStableSelectionPaperIDs[.tag(tag), default: []].append(paper.id)
            }
        }

        stableSelectionPaperIDs = nextStableSelectionPaperIDs
        paperIndexByID = nextPaperIndexByID
        attachmentPresenceCache = nextAttachmentPresenceCache
        lastDynamicCountConfig = dynamicConfig
        lastAttachmentPresenceRevalidationAt = .now
        sidebarCountSnapshot = snapshot
        PerformanceMonitor.logElapsed(
            "LibraryStore.recomputeSidebarCountSnapshot",
            from: perfStart,
            thresholdMS: 18
        ) {
            "papers=\(papers.count), forceAttachmentRevalidation=\(forceAttachmentRevalidation), collections=\(snapshot.collections.count), tags=\(snapshot.tags.count)"
        }
    }

    private func load() {
        do {
            try ensureStorageDirectories()
            migrateLegacyStorageIfNeeded()
            guard fileManager.fileExists(atPath: libraryFileURL.path) else {
                return
            }
            let data = try Data(contentsOf: libraryFileURL)
            let snapshot = try decoder.decode(LibrarySnapshot.self, from: data)
            var didNormalizeStoredState = false
            let hydratedPapers = snapshot.papers.map { snapshotPaper in
                let migrated = migratePaperIfNeeded(snapshotPaper)
                let hydrated = hydratePaperAssets(for: migrated)
                if persistedPaperForLibraryStorage(hydrated) != snapshotPaper {
                    didNormalizeStoredState = true
                }
                return hydrated
            }

            papers = hydratedPapers.sorted(by: { $0.addedAtMilliseconds > $1.addedAtMilliseconds })
            collections = snapshot.collections
            tags = snapshot.tags
            tagColorHexes = snapshot.tagColorHexes
            if didNormalizeStoredState {
                save()
            }
        } catch {
            NSSound.beep()
            print("读取资料库失败: \(error.localizedDescription)")
        }
    }

    private func save() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            flushPendingSaveNow()
        }
    }

    private func flushPendingSaveNow() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        do {
            try ensureStorageDirectories()
            let snapshot = LibrarySnapshot(
                papers: persistedPapersForLibraryStorage(),
                collections: collections,
                tags: tags,
                tagColorHexes: tagColorHexes
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: libraryFileURL, options: .atomic)

            let now = Date()
            if now.timeIntervalSince(lastBackupWriteAt) >= 45 {
                try writeBackups(data: data)
                lastBackupWriteAt = now
            }
        } catch {
            NSSound.beep()
            print("保存资料库失败: \(error.localizedDescription)")
        }
    }

    private func syncTaxonomies() {
        let usedCollections = papers
            .flatMap(\.collections)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedAndSorted()

        let usedTags = papers
            .flatMap(\.tags)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedAndSorted()

        collections = (collections + usedCollections).uniquedAndSorted()
        tags = (tags + usedTags).uniquedAndSorted()
        let validTags = Set(tags)
        tagColorHexes = tagColorHexes.filter { validTags.contains($0.key) }
    }

    private func importPaperAssets(from url: URL) throws -> (folderName: String, pdfURL: URL) {
        let folderName = UUID().uuidString
        let folderURL = papersDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = try ensureImagesDirectoryExists(at: folderURL)

        let originalName = url.lastPathComponent
        let safeName = sanitizeFileName(originalName)
        let pdfDestination = folderURL.appendingPathComponent(safeName, isDirectory: false)
        try fileManager.copyItem(at: url, to: pdfDestination)
        ensureEditablePDF(at: pdfDestination)

        let noteURL = canonicalNoteURL(in: folderURL)
        try "".write(to: noteURL, atomically: true, encoding: .utf8)

        return (folderName, pdfDestination)
    }

    private struct BibTeXEntry {
        var type: String
        var key: String
        var fields: [String: String]
    }

    private func parseBibTeXEntries(from text: String) -> [BibTeXEntry] {
        var results: [BibTeXEntry] = []
        let scalars = Array(text)
        var index = 0

        while index < scalars.count {
            guard scalars[index] == "@" else {
                index += 1
                continue
            }

            guard let openBrace = scalars[index...].firstIndex(of: "{") else {
                break
            }
            let type = String(scalars[(index + 1)..<openBrace]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            var depth = 0
            var endIndex = openBrace
            while endIndex < scalars.count {
                if scalars[endIndex] == "{" {
                    depth += 1
                } else if scalars[endIndex] == "}" {
                    depth -= 1
                    if depth == 0 {
                        break
                    }
                }
                endIndex += 1
            }

            guard endIndex < scalars.count else { break }

            let body = String(scalars[(openBrace + 1)..<endIndex])
            if let entry = parseBibTeXBody(body, type: type) {
                results.append(entry)
            }

            index = endIndex + 1
        }

        return results
    }

    private func parseBibTeXBody(_ body: String, type: String) -> BibTeXEntry? {
        guard let keySeparator = body.firstIndex(of: ",") else { return nil }
        let key = String(body[..<keySeparator]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let rawFields = String(body[body.index(after: keySeparator)...])

        var fields: [String: String] = [:]
        for pair in splitTopLevelFields(rawFields) {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = pair[..<eq].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rawValue = pair[pair.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            fields[name] = unwrappedBibTeXValue(String(rawValue))
        }

        return BibTeXEntry(type: type, key: key, fields: fields)
    }

    private func splitTopLevelFields(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var braceDepth = 0
        var quoteDepth = false

        for char in text {
            if char == "\"" {
                quoteDepth.toggle()
            } else if char == "{", !quoteDepth {
                braceDepth += 1
            } else if char == "}", !quoteDepth, braceDepth > 0 {
                braceDepth -= 1
            }

            if char == ",", braceDepth == 0, !quoteDepth {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
                current = ""
            } else {
                current.append(char)
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    private func unwrappedBibTeXValue(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while (result.hasPrefix("{") && result.hasSuffix("}")) || (result.hasPrefix("\"") && result.hasSuffix("\"")) {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func paper(from entry: BibTeXEntry) -> Paper {
        let title = entry.fields["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authors = normalizedBibTeXAuthors(entry.fields["author"] ?? "")
        let source = (entry.fields["journal"] ?? entry.fields["booktitle"] ?? entry.fields["publisher"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let year = (entry.fields["year"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let doi = (entry.fields["doi"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let abstractText = (entry.fields["abstract"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let volume = (entry.fields["volume"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let issue = (entry.fields["number"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pages = (entry.fields["pages"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = mappedPaperType(from: entry.type)

        return Paper(
            title: title,
            authors: authors,
            year: year,
            source: source,
            doi: doi,
            abstractText: abstractText,
            notes: "",
            paperType: type,
            volume: volume,
            issue: issue,
            pages: pages,
            storageFolderName: nil,
            storedPDFFileName: nil,
            originalPDFFileName: nil,
            imageFileNames: []
        )
    }

    private func normalizedBibTeXAuthors(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: " and ")
            .map { part in
                part.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "{", with: "")
                    .replacingOccurrences(of: "}", with: "")
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func mappedPaperType(from bibType: String) -> String {
        switch bibType.lowercased() {
        case "article":
            return "期刊"
        case "inproceedings", "conference":
            return "会议"
        case "book", "inbook":
            return "书籍"
        case "misc", "online":
            return "电子文献"
        default:
            return "文献"
        }
    }

    private func duplicatePaperIndex(for incoming: Paper) -> (index: Int, reason: LitrixDuplicateReason)? {
        let normalizedIncomingDOI = normalizedDOI(incoming.doi)
        let normalizedIncomingTitle = normalizedPaperTitle(incoming.title)

        if !normalizedIncomingDOI.isEmpty,
           let doiMatchIndex = papers.firstIndex(where: { normalizedDOI($0.doi) == normalizedIncomingDOI }) {
            let titleMatches = !normalizedIncomingTitle.isEmpty
                && normalizedPaperTitle(papers[doiMatchIndex].title) == normalizedIncomingTitle
            return (doiMatchIndex, titleMatches ? .doiAndTitle : .doi)
        }

        if !normalizedIncomingTitle.isEmpty,
           let titleMatchIndex = papers.firstIndex(where: { normalizedPaperTitle($0.title) == normalizedIncomingTitle }) {
            return (titleMatchIndex, .title)
        }

        return nil
    }

    private func uniqueRenamedTitle(from source: String) -> String {
        let rawBase = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawBase.isEmpty ? "Untitled Paper" : rawBase

        var index = 2
        var candidate = "\(base) (\(index))"
        while papers.contains(where: { normalizedPaperTitle($0.title) == normalizedPaperTitle(candidate) }) {
            index += 1
            candidate = "\(base) (\(index))"
        }
        return candidate
    }

    private func normalizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Paper" : trimmed
    }

    private func mergeImportedTaxonomies(from snapshot: LibrarySnapshot) {
        collections = (collections + snapshot.collections).uniquedAndSorted()
        tags = (tags + snapshot.tags).uniquedAndSorted()

        for (tag, colorHex) in snapshot.tagColorHexes {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty else { continue }
            tagColorHexes[trimmedTag] = colorHex
        }
    }

    private func insertImportedPaper(
        _ incoming: Paper,
        archivePapersDirectory: URL,
        selection: LitrixImportSelection
    ) throws {
        var imported = importedPaperTemplate(from: incoming, selection: selection)
        imported.id = UUID()

        if selection.includeAttachments {
            let copiedAssets = try copyArchiveAssets(
                for: incoming,
                archivePapersDirectory: archivePapersDirectory
            )
            imported.storageFolderName = copiedAssets?.folderName
            imported.storedPDFFileName = copiedAssets?.storedPDFFileName
            imported.originalPDFFileName = copiedAssets?.originalPDFFileName
            imported.imageFileNames = copiedAssets?.imageFileNames ?? []
        } else {
            imported.storageFolderName = nil
            imported.storedPDFFileName = nil
            imported.originalPDFFileName = nil
            imported.imageFileNames = []
        }

        imported.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers.insert(imported, at: 0)
        if selection.includeNotes {
            writeNoteFileIfPossible(for: imported)
        }
    }

    private func overwriteImportedPaper(
        at index: Int,
        with incoming: Paper,
        archivePapersDirectory: URL,
        selection: LitrixImportSelection
    ) throws {
        guard papers.indices.contains(index) else { return }
        let existing = papers[index]

        var updated = selection.includePapers
            ? importedPaperTemplate(from: incoming, selection: selection)
            : existing

        updated.id = existing.id
        updated.lastOpenedAt = existing.lastOpenedAt

        if !selection.includePapers {
            updated.collections = existing.collections
            updated.tags = existing.tags
            updated.rating = existing.rating
            updated.addedAtMilliseconds = existing.addedAtMilliseconds
            updated.importedAt = existing.importedAt
        }

        if selection.includeNotes {
            updated.notes = incoming.notes
        } else {
            updated.notes = existing.notes
        }

        if selection.includeAttachments {
            if let oldFolderURL = paperDirectoryURL(for: existing) {
                try? fileManager.removeItem(at: oldFolderURL)
            } else if let oldPDFURL = pdfURL(for: existing) {
                try? fileManager.removeItem(at: oldPDFURL)
            }

            let copiedAssets = try copyArchiveAssets(
                for: incoming,
                archivePapersDirectory: archivePapersDirectory
            )
            updated.storageFolderName = copiedAssets?.folderName
            updated.storedPDFFileName = copiedAssets?.storedPDFFileName
            updated.originalPDFFileName = copiedAssets?.originalPDFFileName
            updated.imageFileNames = copiedAssets?.imageFileNames ?? []
        } else {
            updated.storageFolderName = existing.storageFolderName
            updated.storedPDFFileName = existing.storedPDFFileName
            updated.originalPDFFileName = existing.originalPDFFileName
            updated.imageFileNames = existing.imageFileNames
        }

        updated.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = updated
        if selection.includeNotes {
            writeNoteFileIfPossible(for: updated)
        }
    }

    private func importedPaperTemplate(from incoming: Paper, selection: LitrixImportSelection) -> Paper {
        if selection.includePapers {
            var copied = incoming
            if !selection.includeNotes {
                copied.notes = ""
            }
            return copied
        }

        return Paper(
            title: incoming.title,
            authors: incoming.authors,
            year: incoming.year,
            source: incoming.source,
            doi: incoming.doi,
            notes: selection.includeNotes ? incoming.notes : "",
            paperType: incoming.paperType,
            storageFolderName: nil,
            storedPDFFileName: nil,
            originalPDFFileName: nil,
            imageFileNames: []
        )
    }

    private struct ImportedArchiveAssets {
        var folderName: String
        var storedPDFFileName: String?
        var originalPDFFileName: String?
        var imageFileNames: [String]
    }

    private func copyArchiveAssets(
        for incoming: Paper,
        archivePapersDirectory: URL
    ) throws -> ImportedArchiveAssets? {
        guard let sourceFolderName = incoming.storageFolderName,
              !sourceFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let sourceFolderURL = archivePapersDirectory.appendingPathComponent(sourceFolderName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceFolderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let destinationFolderName = UUID().uuidString
        let destinationFolderURL = papersDirectory.appendingPathComponent(destinationFolderName, isDirectory: true)
        try fileManager.copyItem(at: sourceFolderURL, to: destinationFolderURL)

        let storedPDFFileName: String? = {
            guard let fileName = incoming.storedPDFFileName else { return nil }
            let fileURL = destinationFolderURL.appendingPathComponent(fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            ensureEditablePDF(at: fileURL)
            return fileName
        }()

        let imageFileNames = incoming.imageFileNames.filter { fileName in
            guard let imageURL = existingImageURL(named: fileName, in: destinationFolderURL) else {
                return false
            }
            return fileManager.fileExists(atPath: imageURL.path)
        }

        return ImportedArchiveAssets(
            folderName: destinationFolderName,
            storedPDFFileName: storedPDFFileName,
            originalPDFFileName: incoming.originalPDFFileName ?? incoming.storedPDFFileName,
            imageFileNames: imageFileNames
        )
    }

    private func normalizedPaperTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func normalizedDOI(_ doi: String) -> String {
        doi
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isDuplicatePaper(title: String, doi: String) -> Bool {
        let normalizedTitle = normalizedPaperTitle(title)
        let normalizedDoi = normalizedDOI(doi)
        return papers.contains { existing in
            if !normalizedDoi.isEmpty && normalizedDOI(existing.doi) == normalizedDoi {
                return true
            }
            if !normalizedTitle.isEmpty && normalizedPaperTitle(existing.title) == normalizedTitle {
                return true
            }
            return false
        }
    }

    private func hasMetadataEdit(previous: Paper, updated: Paper) -> Bool {
        var lhs = previous
        var rhs = updated
        lhs.lastOpenedAt = nil
        rhs.lastOpenedAt = nil
        lhs.lastEditedAtMilliseconds = nil
        rhs.lastEditedAtMilliseconds = nil
        return lhs != rhs
    }

    private struct PDFCoreMetadata {
        var title: String = ""
        var authors: String = ""
        var year: String = ""
        var doi: String = ""
    }

    private func extractPDFCoreMetadata(from url: URL) -> PDFCoreMetadata {
        guard let document = PDFDocument(url: url) else {
            return PDFCoreMetadata()
        }

        let attributes = document.documentAttributes ?? [:]
        var metadata = PDFCoreMetadata()

        if let rawTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String {
            metadata.title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let rawAuthors = attributes[PDFDocumentAttribute.authorAttribute] as? String {
            metadata.authors = rawAuthors.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let createdDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
            metadata.year = yearString(from: createdDate)
        } else if let modifiedDate = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date {
            metadata.year = yearString(from: modifiedDate)
        }

        var excerpt = ""
        let upperBound = min(document.pageCount, 5)
        for index in 0..<upperBound {
            guard let text = document.page(at: index)?.string else { continue }
            excerpt.append(text)
            excerpt.append("\n")
            if excerpt.count >= 20_000 {
                break
            }
        }
        if excerpt.count > 20_000 {
            excerpt = String(excerpt.prefix(20_000))
        }

        metadata.doi = detectDOI(in: excerpt)

        if metadata.title.isEmpty {
            metadata.title = detectTitleInFrontMatter(excerpt)
        }
        if metadata.authors.isEmpty {
            metadata.authors = detectAuthorsInFrontMatter(excerpt, title: metadata.title)
        }
        if metadata.year.isEmpty {
            metadata.year = detectPublicationYear(in: excerpt)
        }

        return metadata
    }

    private func yearString(from date: Date) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        if (1900...(Calendar.current.component(.year, from: .now) + 1)).contains(year) {
            return String(year)
        }
        return ""
    }

    private func detectTitleInFrontMatter(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(24) {
            let lowered = line.lowercased()
            if line.count < 8 || line.count > 240 {
                continue
            }
            if lowered.contains("abstract")
                || lowered.contains("keywords")
                || lowered.contains("doi")
                || lowered.contains("@") {
                continue
            }
            return line
        }

        return ""
    }

    private func detectAuthorsInFrontMatter(_ text: String, title: String) -> String {
        let titleNormalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.prefix(36) {
            if line.count < 3 || line.count > 120 {
                continue
            }

            let normalizedLine = line
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleNormalized.isEmpty && normalizedLine == titleNormalized {
                continue
            }

            let lowered = line.lowercased()
            if lowered.contains("abstract")
                || lowered.contains("keywords")
                || lowered.contains("university")
                || lowered.contains("department")
                || lowered.contains("journal")
                || lowered.contains("doi")
                || lowered.contains("@")
                || lowered.contains("http")
                || lowered.contains("www.") {
                continue
            }

            let separators = [" and ", " & ", "，", ",", ";", "；", "、", "与", "和"]
            let containsSeparator = separators.contains { lowered.contains($0.lowercased()) }
            if !containsSeparator, !looksLikePersonName(line) {
                continue
            }

            let names = AuthorNameParser.parse(raw: line)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { looksLikePersonName($0) }

            if names.count >= 2 {
                return names.joined(separator: ", ")
            }
            if names.count == 1 {
                return names[0]
            }
        }

        return ""
    }

    private func looksLikePersonName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil {
            return false
        }
        if trimmed.contains("@") || trimmed.contains("http") {
            return false
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, words.count <= 6 {
            return true
        }

        if trimmed.range(of: #"^[\p{Han}·]{2,16}$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func detectPublicationYear(in text: String) -> String {
        let pattern = #"(?<!\d)(19|20)\d{2}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ""
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return "" }

        let currentYear = Calendar.current.component(.year, from: .now)
        let years: [Int] = matches.compactMap { match in
            let token = nsText.substring(with: match.range)
            guard let value = Int(token) else { return nil }
            guard (1900...(currentYear + 1)).contains(value) else { return nil }
            return value
        }

        guard !years.isEmpty else { return "" }
        if let mostRecent = years.max() {
            return String(mostRecent)
        }
        return ""
    }

    private func detectDOI(in text: String) -> String {
        let pattern = #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return ""
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return ""
        }
        var doi = nsText.substring(with: match.range)
        doi = doi.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return doi
    }

    private func markOpened(paperID: UUID) {
        guard let index = indexOfPaper(id: paperID) else { return }
        papers[index].lastOpenedAt = .now
        papers[index].lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        save()
    }

    private func ensureEditablePDF(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        ensureWritableParentDirectory(for: url)

        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = false
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)

        clearExtendedACL(atPath: url.path)
        removeBlockingExtendedAttributes(atPath: url.path)

        try? fileManager.setAttributes(
            [
                .posixPermissions: 0o666,
                FileAttributeKey(rawValue: "NSFileImmutable"): false,
                FileAttributeKey(rawValue: "NSFileAppendOnly"): false
            ],
            ofItemAtPath: url.path
        )

        guard !fileManager.isWritableFile(atPath: url.path) else { return }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).repair.pdf", isDirectory: false)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: tempURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: tempURL.path)

            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            clearExtendedACL(atPath: url.path)
            removeBlockingExtendedAttributes(atPath: url.path)
            try? fileManager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            print("修复 PDF 可写权限失败: \(error.localizedDescription)")
        }
    }

    private func ensureWritableParentDirectory(for url: URL) {
        let parent = url.deletingLastPathComponent()
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        clearExtendedACL(atPath: parent.path)
    }

    private func clearExtendedACL(atPath path: String) {
        guard let emptyACL = acl_init(1) else { return }
        defer { acl_free(UnsafeMutableRawPointer(emptyACL)) }
        _ = acl_set_file(path, ACL_TYPE_EXTENDED, emptyACL)
    }

    private func removeBlockingExtendedAttributes(atPath path: String) {
        let names = extendedAttributeNames(atPath: path)
        guard !names.isEmpty else { return }

        let blockedPrefixes = [
            "com.apple.macl",
            "com.apple.quarantine",
            "com.apple.provenance"
        ]

        for name in names {
            guard blockedPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            _ = path.withCString { filePath in
                name.withCString { attrName in
                    removexattr(filePath, attrName, 0)
                }
            }
        }
    }

    private func extendedAttributeNames(atPath path: String) -> [String] {
        let size = path.withCString { filePath in
            listxattr(filePath, nil, 0, 0)
        }
        guard size > 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(size))
        let readSize = path.withCString { filePath in
            listxattr(filePath, &buffer, buffer.count, 0)
        }
        guard readSize > 0 else { return [] }

        var names: [String] = []
        var startIndex = 0
        for index in 0..<Int(readSize) {
            if buffer[index] == 0 {
                let slice = buffer[startIndex..<index]
                if !slice.isEmpty {
                    let bytes = slice.map { UInt8(bitPattern: $0) }
                    names.append(String(decoding: bytes, as: UTF8.self))
                }
                startIndex = index + 1
            }
        }

        return names
    }

    private func preferredPDFFileName(for paper: Paper) -> String {
        let titlePart = sanitizedMetadataComponent(paper.title, fallback: "Untitled")
        let authorsPart = sanitizedMetadataComponent(paper.authors, fallback: "UnknownAuthor")
        let yearPart = normalizedYearForFileName(paper.year)
        let rawStem = "\(titlePart)-\(authorsPart)-\(yearPart)"
        let limitedStem = String(rawStem.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = limitedStem.isEmpty ? "Untitled-UnknownAuthor-n.d." : limitedStem
        return sanitizeFileName("\(stem).pdf")
    }

    private func sanitizedMetadataComponent(_ raw: String, fallback: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ";", with: ", ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !cleaned.isEmpty else { return fallback }
        let normalized = sanitizeFileName(cleaned)
            .replacingOccurrences(of: #"(?i)\.pdf$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return normalized.isEmpty ? fallback : normalized
    }

    private func normalizedYearForFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"(?<!\d)(19|20)\d{2}(?!\d)"#, options: .regularExpression) {
            return String(trimmed[range])
        }
        return "n.d."
    }

    private func uniquePDFDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let preferredURL = directory.appendingPathComponent(preferredFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }

        let ext = preferredURL.pathExtension
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(stem)-\(counter)"
            } else {
                candidateName = "\(stem)-\(counter).\(ext)"
            }
            let candidateURL = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = fileName.components(separatedBy: invalidCharacters)
        let joined = components.joined(separator: "-")
        return joined.isEmpty ? "paper.pdf" : joined
    }

    private func ensureStorageDirectories() throws {
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pdfsDirectory, withIntermediateDirectories: true)
        do {
            try fileManager.createDirectory(at: papersDirectory, withIntermediateDirectories: true)
        } catch {
            print("文献目录当前不可写，等待用户授权: \(error.localizedDescription)")
        }
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    private var storageDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Litrix", isDirectory: true)
    }

    private var legacyStorageDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PaperDock", isDirectory: true)
    }

    private var pdfsDirectory: URL {
        storageDirectory.appendingPathComponent("PDFs", isDirectory: true)
    }

    private var papersDirectory: URL {
        settings.resolvedPapersDirectoryURL
    }

    private var libraryFileURL: URL {
        storageDirectory.appendingPathComponent("library.json", isDirectory: false)
    }

    private var backupsDirectory: URL {
        storageDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    var hasWorkspacePapersDirectory: Bool {
        guard let workspacePapersDirectory else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: workspacePapersDirectory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private var workspacePapersDirectory: URL? {
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidate = currentDirectory.appendingPathComponent("papers", isDirectory: true)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private func writeBackups(data: Data) throws {
        let latestBackup = backupsDirectory.appendingPathComponent("latest-library-backup.json", isDirectory: false)
        try data.write(to: latestBackup, options: .atomic)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let datedBackup = backupsDirectory.appendingPathComponent(
            "library-\(formatter.string(from: .now)).json",
            isDirectory: false
        )
        try data.write(to: datedBackup, options: .atomic)

        let backupFiles = try fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let datedFiles = backupFiles.filter { $0.lastPathComponent != "latest-library-backup.json" }
        let sortedFiles = datedFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for staleFile in sortedFiles.dropFirst(15) {
            try? fileManager.removeItem(at: staleFile)
        }
    }

    private func migrateLegacyStorageIfNeeded() {
        guard fileManager.fileExists(atPath: legacyStorageDirectory.path) else {
            return
        }

        let legacyLibraryFileURL = legacyStorageDirectory.appendingPathComponent("library.json", isDirectory: false)
        if !fileManager.fileExists(atPath: libraryFileURL.path),
           fileManager.fileExists(atPath: legacyLibraryFileURL.path) {
            try? fileManager.copyItem(at: legacyLibraryFileURL, to: libraryFileURL)
        }

        let legacyBackupsDirectory = legacyStorageDirectory.appendingPathComponent("Backups", isDirectory: true)
        if fileManager.fileExists(atPath: legacyBackupsDirectory.path) {
            try? mergeDirectoryContents(from: legacyBackupsDirectory, to: backupsDirectory)
        }

        let legacyPapersDirectory = legacyStorageDirectory.appendingPathComponent("Papers", isDirectory: true)
        if fileManager.fileExists(atPath: legacyPapersDirectory.path) {
            try? mergeDirectoryContents(from: legacyPapersDirectory, to: papersDirectory)
        }
    }

    private func mergeDirectoryContents(from source: URL, to destination: URL) throws {
        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for sourceItem in items {
            let destinationItem = destination.appendingPathComponent(sourceItem.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destinationItem.path) {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: sourceItem.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    try fileManager.createDirectory(at: destinationItem, withIntermediateDirectories: true)
                    try mergeDirectoryContents(from: sourceItem, to: destinationItem)
                    try? fileManager.removeItem(at: sourceItem)
                }
                continue
            }

            try fileManager.moveItem(at: sourceItem, to: destinationItem)
        }
    }

    private func resolvedPDFURL(for paper: Paper) -> URL? {
        let normalizedStoredName = paper.storedPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOriginalName = paper.originalPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let folderURL = paperDirectoryURL(for: paper) {
            if let normalizedStoredName, !normalizedStoredName.isEmpty {
                let storedURL = folderURL.appendingPathComponent(normalizedStoredName, isDirectory: false)
                if fileManager.fileExists(atPath: storedURL.path) {
                    return storedURL
                }
            }

            if let normalizedOriginalName, !normalizedOriginalName.isEmpty {
                let originalURL = folderURL.appendingPathComponent(normalizedOriginalName, isDirectory: false)
                if fileManager.fileExists(atPath: originalURL.path) {
                    return originalURL
                }
            }

            if let normalizedStoredName, !normalizedStoredName.isEmpty {
                return folderURL.appendingPathComponent(normalizedStoredName, isDirectory: false)
            }
            if let normalizedOriginalName, !normalizedOriginalName.isEmpty {
                return folderURL.appendingPathComponent(normalizedOriginalName, isDirectory: false)
            }
            return nil
        }

        if let normalizedStoredName, !normalizedStoredName.isEmpty {
            let storedURL = pdfsDirectory.appendingPathComponent(normalizedStoredName, isDirectory: false)
            if fileManager.fileExists(atPath: storedURL.path) {
                return storedURL
            }
            return storedURL
        }

        if let normalizedOriginalName, !normalizedOriginalName.isEmpty {
            let originalURL = pdfsDirectory.appendingPathComponent(normalizedOriginalName, isDirectory: false)
            if fileManager.fileExists(atPath: originalURL.path) {
                return originalURL
            }
            return originalURL
        }

        return nil
    }

    private func resolvedPreferredOpenPDFURL(for paper: Paper) -> URL? {
        guard let preferredFileName = normalizedPDFFileName(paper.preferredOpenPDFFileName) else {
            return nil
        }

        if let folderURL = paperDirectoryURL(for: paper) {
            let preferredURL = folderURL.appendingPathComponent(preferredFileName, isDirectory: false)
            if fileManager.fileExists(atPath: preferredURL.path) {
                return preferredURL
            }
        }

        let preferredURL = pdfsDirectory.appendingPathComponent(preferredFileName, isDirectory: false)
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        return nil
    }

    private func availablePDFURLs(for paper: Paper) -> [URL] {
        if let folderURL = paperDirectoryURL(for: paper),
           let fileNames = try? fileManager.contentsOfDirectory(atPath: folderURL.path) {
            return fileNames
                .filter { $0.lowercased().hasSuffix(".pdf") && !$0.hasPrefix(".") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { folderURL.appendingPathComponent($0, isDirectory: false) }
        }

        if let url = resolvedPDFURL(for: paper) {
            return [url]
        }

        return []
    }

    private func normalizedPDFFileName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func openViaLaunchServices(_ url: URL, preferredApplication: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)

        var arguments: [String] = []
        if let preferredApplication {
            arguments.append(contentsOf: ["-a", preferredApplication])
        }
        arguments.append(url.path)
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(url)
        }
    }

    private func hydratePaperAssets(for paper: Paper) -> Paper {
        var hydrated = paper

        if let folderURL = paperDirectoryURL(for: paper) {
            hydrated = normalizePaperAssetsIfNeeded(hydrated, in: folderURL)

            if let noteURL = ensuredCanonicalNoteURL(for: hydrated, in: folderURL),
               let text = try? String(contentsOf: noteURL, encoding: .utf8) {
                hydrated.notes = text
            }
        }

        return hydrated
    }

    private func writeNoteFileIfPossible(for paper: Paper) {
        guard let folderURL = paperDirectoryURL(for: paper) else { return }
        let targetNoteURL = canonicalNoteURL(in: folderURL)
        let previousNoteURL = existingNoteURL(for: paper, in: folderURL)

        do {
            try paper.notes.write(to: targetNoteURL, atomically: true, encoding: .utf8)

            if let previousNoteURL,
               previousNoteURL.standardizedFileURL != targetNoteURL.standardizedFileURL {
                try? fileManager.removeItem(at: previousNoteURL)
            }
        } catch {
            print("写入 Note 失败: \(error.localizedDescription)")
        }
    }

    private func migratePaperIfNeeded(_ paper: Paper) -> Paper {
        guard paper.storageFolderName == nil,
              let oldPDFURL = pdfURL(for: paper),
              fileManager.fileExists(atPath: oldPDFURL.path) else {
            return paper
        }

        do {
            let importedAssets = try importPaperAssets(from: oldPDFURL)
            try? fileManager.removeItem(at: oldPDFURL)

            var migrated = paper
            migrated.storageFolderName = importedAssets.folderName
            migrated.storedPDFFileName = importedAssets.pdfURL.lastPathComponent
            migrated.imageFileNames = []
            try migrated.notes.write(
                to: canonicalNoteURL(in: importedAssets.pdfURL.deletingLastPathComponent()),
                atomically: true,
                encoding: .utf8
            )
            return migrated
        } catch {
            print("迁移文献目录失败: \(error.localizedDescription)")
            return paper
        }
    }

    private func existingNoteURL(for paper: Paper, in folderURL: URL) -> URL? {
        let preferredURL = canonicalNoteURL(in: folderURL)
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let legacyURL = folderURL.appendingPathComponent(legacyNoteFileName, isDirectory: false)
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: folderURL.path) else {
            return nil
        }

        let fallback = fileNames
            .filter { fileName in
                fileName.hasSuffix(".txt")
                    && fileName != canonicalNoteFileName
                    && fileName != legacyNoteFileName
                    && !fileName.hasPrefix(".")
            }
            .first
        if let fallback {
            return folderURL.appendingPathComponent(fallback, isDirectory: false)
        }

        return nil
    }

    private func noteFileName(for paper: Paper) -> String {
        canonicalNoteFileName
    }

    private func persistedPapersForLibraryStorage() -> [Paper] {
        papers.map(persistedPaperForLibraryStorage)
    }

    private func persistedPaperForLibraryStorage(_ paper: Paper) -> Paper {
        var persisted = paper
        if persisted.storageFolderName != nil {
            // The note file is the source of truth for papers with asset folders.
            persisted.notes = ""
        }
        return persisted
    }

    private func normalizePaperAssetsIfNeeded(_ paper: Paper, in folderURL: URL) -> Paper {
        var normalized = paper

        if let discoveredPDFName = resolvedPDFFileName(in: normalized, folderURL: folderURL) {
            if normalized.storedPDFFileName != discoveredPDFName {
                normalized.storedPDFFileName = discoveredPDFName
            }
            let trimmedOriginal = normalized.originalPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedOriginal.isEmpty {
                normalized.originalPDFFileName = discoveredPDFName
            }
        }

        if let preferredOpenPDFFileName = normalizedPDFFileName(normalized.preferredOpenPDFFileName) {
            let preferredURL = folderURL.appendingPathComponent(preferredOpenPDFFileName, isDirectory: false)
            if !fileManager.fileExists(atPath: preferredURL.path) {
                normalized.preferredOpenPDFFileName = nil
            }
        }

        normalized.imageFileNames = normalizedImageFileNames(for: normalized, in: folderURL)
        return normalized
    }

    private func resolvedPDFFileName(in paper: Paper, folderURL: URL) -> String? {
        if let storedName = normalizedPDFFileName(paper.storedPDFFileName) {
            let storedURL = folderURL.appendingPathComponent(storedName, isDirectory: false)
            if fileManager.fileExists(atPath: storedURL.path) {
                return storedName
            }
        }

        if let originalName = normalizedPDFFileName(paper.originalPDFFileName) {
            let originalURL = folderURL.appendingPathComponent(originalName, isDirectory: false)
            if fileManager.fileExists(atPath: originalURL.path) {
                return originalName
            }
        }

        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: folderURL.path) else {
            return normalizedPDFFileName(paper.storedPDFFileName)
                ?? normalizedPDFFileName(paper.originalPDFFileName)
        }

        let fallback = fileNames
            .filter { $0.lowercased().hasSuffix(".pdf") && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first

        return fallback
            ?? normalizedPDFFileName(paper.storedPDFFileName)
            ?? normalizedPDFFileName(paper.originalPDFFileName)
    }

    private func normalizedImageFileNames(for paper: Paper, in folderURL: URL) -> [String] {
        var normalizedNames: [String] = []
        var seenNames: Set<String> = []

        let metadataNames = paper.imageFileNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let discoveredNames = discoveredImageFileNames(in: folderURL, pdfFileName: paper.storedPDFFileName)

        for imageFileName in metadataNames + discoveredNames {
            guard seenNames.insert(imageFileName).inserted else { continue }

            let canonicalURL = canonicalImageURL(named: imageFileName, in: folderURL)
            if fileManager.fileExists(atPath: canonicalURL.path) {
                normalizedNames.append(imageFileName)
                continue
            }

            let legacyURL = folderURL.appendingPathComponent(imageFileName, isDirectory: false)
            if fileManager.fileExists(atPath: legacyURL.path) {
                do {
                    _ = try ensureImagesDirectoryExists(at: folderURL)
                    let destinationURL = uniqueAssetDestinationURL(
                        in: imagesDirectoryURL(in: folderURL),
                        preferredFileName: imageFileName
                    )
                    try fileManager.moveItem(at: legacyURL, to: destinationURL)
                    normalizedNames.append(destinationURL.lastPathComponent)
                } catch {
                    print("迁移图片到 images 目录失败(\(imageFileName)): \(error.localizedDescription)")
                }
            }
        }

        return normalizedNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func discoveredImageFileNames(in folderURL: URL, pdfFileName: String?) -> [String] {
        var names: Set<String> = []

        if let fileNames = try? fileManager.contentsOfDirectory(atPath: imagesDirectoryURL(in: folderURL).path) {
            for fileName in fileNames where isImageAssetFileName(fileName, pdfFileName: pdfFileName) {
                names.insert(fileName)
            }
        }

        if let fileNames = try? fileManager.contentsOfDirectory(atPath: folderURL.path) {
            for fileName in fileNames where isLegacyRootImageFileName(fileName, pdfFileName: pdfFileName) {
                names.insert(fileName)
            }
        }

        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func isLegacyRootImageFileName(_ fileName: String, pdfFileName: String?) -> Bool {
        guard isImageAssetFileName(fileName, pdfFileName: pdfFileName) else {
            return false
        }
        return fileName != imagesDirectoryName
    }

    private func isImageAssetFileName(_ fileName: String, pdfFileName: String?) -> Bool {
        if fileName.hasPrefix(".") {
            return false
        }
        if fileName == imagesDirectoryName || fileName == legacyNoteFileName || fileName == canonicalNoteFileName {
            return false
        }
        if fileName.lowercased().hasSuffix(".txt") || fileName.lowercased().hasSuffix(".pdf") {
            return false
        }
        if let pdfFileName, fileName == pdfFileName {
            return false
        }
        return true
    }

    private func ensuredCanonicalNoteURL(for paper: Paper, in folderURL: URL) -> URL? {
        let canonicalURL = canonicalNoteURL(in: folderURL)

        if fileManager.fileExists(atPath: canonicalURL.path) {
            if let legacyURL = existingNoteURL(for: paper, in: folderURL),
               legacyURL.standardizedFileURL != canonicalURL.standardizedFileURL {
                try? fileManager.removeItem(at: legacyURL)
            }
            return canonicalURL
        }

        if let legacyURL = existingNoteURL(for: paper, in: folderURL),
           legacyURL.standardizedFileURL != canonicalURL.standardizedFileURL {
            do {
                try fileManager.moveItem(at: legacyURL, to: canonicalURL)
                return canonicalURL
            } catch {
                print("迁移 Note 到固定文件名失败: \(error.localizedDescription)")
            }
        }

        guard !paper.notes.isEmpty else { return nil }
        do {
            try paper.notes.write(to: canonicalURL, atomically: true, encoding: .utf8)
            return canonicalURL
        } catch {
            print("初始化 Note 文件失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func canonicalNoteURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(canonicalNoteFileName, isDirectory: false)
    }

    private func imagesDirectoryURL(in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(imagesDirectoryName, isDirectory: true)
    }

    private func ensureImagesDirectoryExists(at folderURL: URL) throws -> URL {
        let imagesURL = imagesDirectoryURL(in: folderURL)
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        return imagesURL
    }

    private func canonicalImageURL(named fileName: String, in folderURL: URL) -> URL {
        imagesDirectoryURL(in: folderURL).appendingPathComponent(fileName, isDirectory: false)
    }

    private func existingImageURL(named fileName: String, in folderURL: URL) -> URL? {
        let canonicalURL = canonicalImageURL(named: fileName, in: folderURL)
        if fileManager.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        }

        let legacyURL = folderURL.appendingPathComponent(fileName, isDirectory: false)
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return nil
    }

    private func uniqueAssetDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let preferredURL = directory.appendingPathComponent(preferredFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let ext = preferredURL.pathExtension
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(stem)-\(counter)"
            } else {
                candidateName = "\(stem)-\(counter).\(ext)"
            }
            let candidateURL = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }
}

private extension Array where Element == String {
    func uniquedAndSorted() -> [String] {
        Array(Set(self)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
