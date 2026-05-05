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

struct BibTeXImportResult {
    var importedPaperIDs: [UUID] = []
    var duplicateTitles: [String] = []
    var failedFiles: [String] = []

    static let empty = BibTeXImportResult()
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
    @Published private(set) var collectionMetadata: [String: TaxonomyItemMetadata] = [:]
    @Published private(set) var tagMetadata: [String: TaxonomyItemMetadata] = [:]
    @Published private(set) var dataRevision: Int = 0

    private let fileManager = FileManager.default
    private let supportedAttachmentFileExtensions: Set<String> = [
        "pdf",
        "doc", "docx",
        "xls", "xlsx", "csv",
        "ppt", "pptx",
        "epub", "mobi",
        "html", "htm",
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "webp",
        "txt", "rtf", "md"
    ]
    private let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "webp"
    ]
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
        zombieInterval: 0,
        recentlyDeletedRetentionInterval: 0
    )
    private var pendingSaveTask: Task<Void, Never>?
    private var lastBackupWriteAt: Date = .distantPast
    private var autoSaveSuspended = false
    private var terminateObserver: NSObjectProtocol?
    private var recentlyDeletedCleanupTask: Task<Void, Never>?

    private struct SidebarCountSnapshot {
        var all = 0
        var recentReading = 0
        var zombiePapers = 0
        var unfiled = 0
        var missingDOI = 0
        var missingAttachment = 0
        var recentlyDeleted = 0
        var collections: [String: Int] = [:]
        var tags: [String: Int] = [:]

        static let empty = SidebarCountSnapshot()
    }

    private struct AttachmentPresenceCacheEntry {
        var signature: String
        var isMissing: Bool
    }

    private struct DynamicCountConfig: Equatable {
        var recentReadingInterval: TimeInterval
        var zombieInterval: TimeInterval
        var recentlyDeletedRetentionInterval: TimeInterval
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
        purgeExpiredDeletedPapers()
        startRecentlyDeletedCleanupTask()
    }

    var papersStorageRootURL: URL {
        papersDirectory
    }

    func currentLibrarySnapshot() -> LibrarySnapshot {
        LibrarySnapshot(
            papers: papers,
            collections: collections,
            tags: tags,
            tagColorHexes: tagColorHexes,
            collectionMetadata: collectionMetadata,
            tagMetadata: tagMetadata
        )
    }

    func restoreLibrarySnapshot(_ snapshot: LibrarySnapshot) {
        papers = snapshot.papers
            .map { hydratePaperAssets(for: migratePaperIfNeeded($0)) }
            .sorted(by: { $0.addedAtMilliseconds > $1.addedAtMilliseconds })
        collections = snapshot.collections
        tags = snapshot.tags
        tagColorHexes = snapshot.tagColorHexes
        collectionMetadata = snapshot.collectionMetadata
        tagMetadata = snapshot.tagMetadata
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

        var existingTitleAuthorKeys = Set(
            papers
                .filter { !$0.isDeleted }
                .map { duplicateTitleAuthorKey(title: $0.title, authors: $0.authors) }
                .filter { !$0.isEmpty }
        )
        var existingDOIKeys = Set(
            papers
                .filter { !$0.isDeleted }
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
                let extracted = extractDocumentCoreMetadata(from: url)
                let resolvedTitle: String = {
                    let extractedTitle = MetadataValueNormalizer.normalizeTitle(extracted.title)
                    if !extractedTitle.isEmpty {
                        return extractedTitle
                    }
                    let parsedTitle = MetadataValueNormalizer.normalizeTitle(parsed.title)
                    return parsedTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : parsedTitle
                }()
                let resolvedAuthors: String = {
                    let extractedAuthors = MetadataValueNormalizer.normalizeAuthors(extracted.authors)
                    if !extractedAuthors.isEmpty {
                        return extractedAuthors
                    }
                    return MetadataValueNormalizer.normalizeAuthors(parsed.authors)
                }()
                let resolvedYear: String = {
                    let extractedYear = MetadataValueNormalizer.normalizeYear(extracted.year)
                    if !extractedYear.isEmpty {
                        return extractedYear
                    }
                    return MetadataValueNormalizer.normalizeYear(parsed.year)
                }()
                let resolvedSource: String = {
                    let extractedSource = MetadataValueNormalizer.normalizeSource(extracted.source)
                    if !extractedSource.isEmpty {
                        return extractedSource
                    }
                    return MetadataValueNormalizer.normalizeSource(detectSourceInFileName(url))
                }()
                let resolvedDOI = MetadataValueNormalizer.normalizeDOI(extracted.doi)
                let resolvedVolume = MetadataValueNormalizer.normalizeVolume(extracted.volume)
                let resolvedIssue = MetadataValueNormalizer.normalizeIssue(extracted.issue)
                let resolvedPages = MetadataValueNormalizer.normalizePages(extracted.pages)
                let titleAuthorKey = duplicateTitleAuthorKey(title: resolvedTitle, authors: resolvedAuthors)
                let normalizedResolvedDOI = normalizedDOI(resolvedDOI)

                var duplicateWarning: String?
                if !normalizedResolvedDOI.isEmpty, existingDOIKeys.contains(normalizedResolvedDOI) {
                    duplicateWarning = duplicateDisplayName(
                        title: resolvedTitle,
                        authors: resolvedAuthors,
                        doi: resolvedDOI
                    )
                }

                if duplicateWarning == nil,
                   !titleAuthorKey.isEmpty,
                   existingTitleAuthorKeys.contains(titleAuthorKey) {
                    duplicateWarning = duplicateDisplayName(
                        title: resolvedTitle,
                        authors: resolvedAuthors,
                        doi: resolvedDOI
                    )
                }

                if let duplicateWarning {
                    result.duplicateTitles.append(duplicateWarning)
                }

                do {
                    let importedAssets = try importPaperAssets(from: url)
                    let paper = Paper(
                        title: resolvedTitle,
                        authors: resolvedAuthors,
                        year: resolvedYear,
                        source: resolvedSource,
                        doi: resolvedDOI,
                        notes: "",
                        volume: resolvedVolume,
                        issue: resolvedIssue,
                        pages: resolvedPages,
                        storageFolderName: importedAssets.folderName,
                        storedPDFFileName: importedAssets.pdfURL.lastPathComponent,
                        originalPDFFileName: url.lastPathComponent,
                        imageFileNames: []
                    )
                    papers.insert(paper, at: 0)
                    if settings.autoRenameImportedPDFFiles,
                       url.pathExtension.lowercased() == "pdf" {
                        _ = renameStoredPDF(forPaperID: paper.id, shouldPersist: false)
                    }
                    result.importedPaperIDs.append(paper.id)
                    if !titleAuthorKey.isEmpty {
                        existingTitleAuthorKeys.insert(titleAuthorKey)
                    }
                    if !normalizedResolvedDOI.isEmpty {
                        existingDOIKeys.insert(normalizedResolvedDOI)
                    }
                } catch {
                    result.failedFiles.append(url.lastPathComponent)
                    print("导入文献文件失败(\(url.lastPathComponent)): \(error.localizedDescription)")
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

    @discardableResult
    func importBibTeX(from urls: [URL]) -> BibTeXImportResult {
        guard !urls.isEmpty else { return .empty }

        var result = BibTeXImportResult()
        var existingTitleAuthorKeys = Set(
            papers
                .filter { !$0.isDeleted }
                .map { duplicateTitleAuthorKey(title: $0.title, authors: $0.authors) }
                .filter { !$0.isEmpty }
        )
        var existingDOIKeys = Set(
            papers
                .filter { !$0.isDeleted }
                .map(\.doi)
                .map(normalizedDOI)
                .filter { !$0.isEmpty }
        )

        for url in urls {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                result.failedFiles.append(url.lastPathComponent)
                continue
            }
            let entries = parseBibTeXEntries(from: text)
            for entry in entries {
                let paper = paper(from: entry)
                let titleAuthorKey = duplicateTitleAuthorKey(title: paper.title, authors: paper.authors)
                let doiKey = normalizedDOI(paper.doi)

                if (!doiKey.isEmpty && existingDOIKeys.contains(doiKey))
                    || (!titleAuthorKey.isEmpty && existingTitleAuthorKeys.contains(titleAuthorKey)) {
                    result.duplicateTitles.append(
                        duplicateDisplayName(title: paper.title, authors: paper.authors, doi: paper.doi)
                    )
                }

                papers.insert(paper, at: 0)
                result.importedPaperIDs.append(paper.id)
                if !titleAuthorKey.isEmpty {
                    existingTitleAuthorKeys.insert(titleAuthorKey)
                }
                if !doiKey.isEmpty {
                    existingDOIKeys.insert(doiKey)
                }
            }
        }

        guard !result.importedPaperIDs.isEmpty else { return result }
        syncTaxonomies()
        save()
        return result
    }

    func hasPotentialDuplicate(_ paper: Paper, excludingPaperID: UUID? = nil) -> Bool {
        hasPotentialDuplicate(
            title: paper.title,
            authors: paper.authors,
            doi: paper.doi,
            excludingPaperID: excludingPaperID
        )
    }

    func hasPotentialDuplicate(
        title: String,
        authors: String,
        doi: String,
        excludingPaperID: UUID? = nil
    ) -> Bool {
        let titleAuthorKey = duplicateTitleAuthorKey(title: title, authors: authors)
        let doiKey = normalizedDOI(doi)
        return papers.contains { existing in
            if existing.isDeleted {
                return false
            }
            if existing.id == excludingPaperID {
                return false
            }
            if !doiKey.isEmpty && normalizedDOI(existing.doi) == doiKey {
                return true
            }
            if !titleAuthorKey.isEmpty,
               duplicateTitleAuthorKey(title: existing.title, authors: existing.authors) == titleAuthorKey {
                return true
            }
            return false
        }
    }

    @discardableResult
    func addMetadataOnlyPaper(_ paper: Paper) -> Bool {
        var paper = paper
        do {
            _ = try ensurePaperDirectory(for: &paper)
            papers.insert(paper, at: 0)
            syncTaxonomies()
            save()
            return true
        } catch {
            NSSound.beep()
            print("创建无附件条目失败: \(error.localizedDescription)")
            return false
        }
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
        updated.refreshDerivedSearchData()
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
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
        guard !trimmed.isEmpty else { return }
        guard !collections.contains(trimmed) else { return }
        collections = (collections + [trimmed]).uniquedAndSorted()
        save()
    }

    func createTag(named name: String) {
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(trimmed) else { return }
        tags = (tags + [trimmed]).uniquedAndSorted()
        save()
    }

    func createTaxonomyItem(kind: TaxonomyKind, named name: String, parentPath: String? = nil) {
        let path = TaxonomyHierarchy.path(parent: parentPath, name: name)
        guard !path.isEmpty, TaxonomyHierarchy.depth(of: path) <= TaxonomyHierarchy.maximumDepth else { return }

        switch kind {
        case .collection:
            guard !collections.contains(path) else { return }
            collections = (collections + [path]).uniquedAndSorted()
        case .tag:
            guard !tags.contains(path) else { return }
            tags = (tags + [path]).uniquedAndSorted()
        }
        save()
    }

    func createTaxonomySibling(kind: TaxonomyKind, named name: String, relativeTo path: String) {
        createTaxonomyItem(kind: kind, named: name, parentPath: TaxonomyHierarchy.parentPath(of: path))
    }

    func createTaxonomyChild(kind: TaxonomyKind, named name: String, under path: String) {
        guard TaxonomyHierarchy.depth(of: path) < TaxonomyHierarchy.maximumDepth else { return }
        createTaxonomyItem(kind: kind, named: name, parentPath: path)
    }

    func createTaxonomyParent(kind: TaxonomyKind, named name: String, above path: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = TaxonomyHierarchy.normalizedPath(path)
        guard !trimmed.isEmpty, !normalizedPath.isEmpty else { return }

        let affectedPaths = taxonomyItems(for: kind).filter {
            TaxonomyHierarchy.isDescendant($0, of: normalizedPath)
        }
        let deepestAffectedDepth = affectedPaths.map(TaxonomyHierarchy.depth).max() ?? TaxonomyHierarchy.depth(of: normalizedPath)
        guard deepestAffectedDepth < TaxonomyHierarchy.maximumDepth else { return }

        let oldParent = TaxonomyHierarchy.parentPath(of: normalizedPath)
        let proposedParent = TaxonomyHierarchy.path(parent: oldParent, name: trimmed)
        let newParent = uniqueTaxonomyPath(proposedParent, kind: kind)
        guard !newParent.isEmpty else { return }
        let newRoot = "\(newParent)\(TaxonomyHierarchy.separator)\(TaxonomyHierarchy.leafName(of: normalizedPath))"
        replaceTaxonomyPrefix(kind: kind, oldPrefix: normalizedPath, newPrefix: newRoot)

        var items = taxonomyItems(for: kind)
        items.append(newParent)
        setTaxonomyItems(items.uniquedAndSorted(), for: kind)
        syncTaxonomies()
        save()
    }

    func moveTaxonomyItem(kind: TaxonomyKind, sourcePath: String, targetPath: String, asChild: Bool) {
        let source = TaxonomyHierarchy.normalizedPath(sourcePath)
        let target = TaxonomyHierarchy.normalizedPath(targetPath)
        guard !source.isEmpty, !target.isEmpty, source != target else { return }
        guard taxonomyItems(for: kind).contains(source), taxonomyItems(for: kind).contains(target) else { return }
        guard !TaxonomyHierarchy.isDescendant(target, of: source) else { return }

        let affectedPaths = taxonomyItems(for: kind).filter {
            TaxonomyHierarchy.isDescendant($0, of: source)
        }
        let sourceDepth = TaxonomyHierarchy.depth(of: source)
        let deepestRelativeDepth = affectedPaths
            .map { TaxonomyHierarchy.depth(of: $0) - sourceDepth + 1 }
            .max() ?? 1

        let destinationParent: String?
        if asChild, TaxonomyHierarchy.depth(of: target) + deepestRelativeDepth <= TaxonomyHierarchy.maximumDepth {
            destinationParent = target
        } else {
            destinationParent = TaxonomyHierarchy.parentPath(of: target)
        }

        let proposedRoot = TaxonomyHierarchy.path(parent: destinationParent, name: TaxonomyHierarchy.leafName(of: source))
        guard !proposedRoot.isEmpty, TaxonomyHierarchy.depth(of: proposedRoot) + deepestRelativeDepth - 1 <= TaxonomyHierarchy.maximumDepth else {
            return
        }

        let newRoot = uniqueTaxonomyPath(proposedRoot, kind: kind, excludingPrefix: source)
        guard newRoot != source else { return }
        replaceTaxonomyPrefix(kind: kind, oldPrefix: source, newPrefix: newRoot)
        syncTaxonomies()
        save()
    }

    func renameTag(oldName: String, newName: String) {
        let oldTrimmed = TaxonomyHierarchy.normalizedPath(oldName)
        let newTrimmed = TaxonomyHierarchy.normalizedPath(newName)
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
        if let metadata = tagMetadata.removeValue(forKey: oldTrimmed) {
            tagMetadata[newTrimmed] = metadata
        }

        syncTaxonomies()
        save()
    }

    func deleteTag(named name: String) {
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
        guard !trimmed.isEmpty else { return }

        tags.removeAll { $0 == trimmed }
        tagColorHexes.removeValue(forKey: trimmed)
        tagMetadata.removeValue(forKey: trimmed)

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
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
        guard !trimmed.isEmpty else { return }
        guard tags.contains(trimmed) else { return }

        let normalized = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            tagColorHexes[trimmed] = normalized
            var metadata = tagMetadata[trimmed] ?? TaxonomyItemMetadata(iconSystemName: "circle.fill")
            metadata.colorHex = normalized
            tagMetadata[trimmed] = metadata
        } else {
            tagColorHexes.removeValue(forKey: trimmed)
            if var metadata = tagMetadata[trimmed] {
                metadata.colorHex = ""
                tagMetadata[trimmed] = metadata
            }
        }
        save()
    }

    func tagColorHex(forTag name: String) -> String? {
        let normalized = TaxonomyHierarchy.normalizedPath(name)
        if let hex = tagMetadata[normalized]?.colorHex.trimmingCharacters(in: .whitespacesAndNewlines),
           !hex.isEmpty {
            return hex
        }
        return tagColorHexes[normalized]
    }

    func taxonomyMetadata(for path: String, kind: TaxonomyKind) -> TaxonomyItemMetadata {
        let normalized = TaxonomyHierarchy.normalizedPath(path)
        switch kind {
        case .collection:
            return collectionMetadata[normalized] ?? TaxonomyItemMetadata(iconSystemName: "folder")
        case .tag:
            let legacyColor = tagColorHexes[normalized] ?? ""
            var metadata = tagMetadata[normalized] ?? TaxonomyItemMetadata(iconSystemName: "circle.fill")
            if metadata.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata.colorHex = legacyColor
            }
            return metadata
        }
    }

    @discardableResult
    func updateTaxonomyItem(
        kind: TaxonomyKind,
        path: String,
        title: String,
        metadata: TaxonomyItemMetadata
    ) -> String? {
        let oldPath = TaxonomyHierarchy.normalizedPath(path)
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldPath.isEmpty, !newTitle.isEmpty else { return nil }
        guard taxonomyItems(for: kind).contains(oldPath) else { return nil }

        let proposedPath = TaxonomyHierarchy.path(parent: TaxonomyHierarchy.parentPath(of: oldPath), name: newTitle)
        let destination = proposedPath == oldPath
            ? oldPath
            : uniqueTaxonomyPath(proposedPath, kind: kind, excludingPrefix: oldPath)
        guard !destination.isEmpty else { return nil }

        if destination != oldPath {
            replaceTaxonomyPrefix(kind: kind, oldPrefix: oldPath, newPrefix: destination)
        }
        setTaxonomyMetadata(metadata, for: destination, kind: kind)
        syncTaxonomies()
        save()
        return destination
    }

    func setTaxonomyMetadata(_ metadata: TaxonomyItemMetadata, for path: String, kind: TaxonomyKind) {
        let normalized = TaxonomyHierarchy.normalizedPath(path)
        guard !normalized.isEmpty else { return }
        switch kind {
        case .collection:
            collectionMetadata[normalized] = metadata
        case .tag:
            tagMetadata[normalized] = metadata
            let color = metadata.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
            if color.isEmpty {
                tagColorHexes.removeValue(forKey: normalized)
            } else {
                tagColorHexes[normalized] = color
            }
        }
    }

    func renameCollection(oldName: String, newName: String) {
        let oldTrimmed = TaxonomyHierarchy.normalizedPath(oldName)
        let newTrimmed = TaxonomyHierarchy.normalizedPath(newName)
        guard !oldTrimmed.isEmpty, !newTrimmed.isEmpty, oldTrimmed != newTrimmed else { return }
        guard collections.contains(oldTrimmed) else { return }
        guard !collections.contains(newTrimmed) else { return }

        collections = collections.map { $0 == oldTrimmed ? newTrimmed : $0 }.uniquedAndSorted()
        if let metadata = collectionMetadata.removeValue(forKey: oldTrimmed) {
            collectionMetadata[newTrimmed] = metadata
        }

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
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
        guard !trimmed.isEmpty else { return }

        collections.removeAll { $0 == trimmed }
        collectionMetadata.removeValue(forKey: trimmed)

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
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
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
        let trimmed = TaxonomyHierarchy.normalizedPath(name)
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
        movePaperToRecentlyDeleted(id: id)
    }

    func movePaperToRecentlyDeleted(id: UUID) {
        guard let index = indexOfPaper(id: id) else { return }
        guard papers[index].deletedAt == nil else { return }
        var paper = papers[index]
        paper.deletedAt = .now
        paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = paper
        syncTaxonomies()
        save()
    }

    func restorePaper(id: UUID) {
        guard let index = indexOfPaper(id: id) else { return }
        guard papers[index].deletedAt != nil else { return }
        var paper = papers[index]
        paper.deletedAt = nil
        paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = paper
        syncTaxonomies()
        save()
    }

    func permanentlyDeletePaper(id: UUID) {
        permanentlyDeletePapers(ids: [id])
    }

    func permanentlyDeletePapers(ids: [UUID]) {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return }

        let papersToDelete = papers.filter { targetIDs.contains($0.id) && $0.isDeleted }
        guard !papersToDelete.isEmpty else { return }

        for paper in papersToDelete {
            deleteStoredAssets(for: paper)
        }

        let deletedIDs = Set(papersToDelete.map(\.id))
        papers.removeAll { deletedIDs.contains($0.id) }
        syncTaxonomies()
        save()
    }

    @discardableResult
    func purgeExpiredDeletedPapers(now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-settings.resolvedRecentlyDeletedRetentionInterval)
        let expiredIDs = papers.compactMap { paper -> UUID? in
            guard let deletedAt = paper.deletedAt, deletedAt <= cutoff else { return nil }
            return paper.id
        }
        guard !expiredIDs.isEmpty else { return 0 }

        permanentlyDeletePapers(ids: expiredIDs)
        return expiredIDs.count
    }

    private func startRecentlyDeletedCleanupTask() {
        recentlyDeletedCleanupTask?.cancel()
        recentlyDeletedCleanupTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                guard !Task.isCancelled else { break }
                self?.purgeExpiredDeletedPapers()
            }
        }
    }

    private func deleteStoredAssets(for paper: Paper) {
        if let folderURL = paperDirectoryURL(for: paper) {
            try? fileManager.removeItem(at: folderURL)
        } else if let pdfURL = pdfURL(for: paper) {
            try? fileManager.removeItem(at: pdfURL)
        }
    }

    func pdfURL(for paper: Paper) -> URL? {
        resolvedPDFURL(for: paper)
    }

    func defaultOpenPDFURL(for paper: Paper) -> URL? {
        translatedPreferredPDFURL(for: paper)
            ?? resolvedPreferredOpenPDFURL(for: paper)
            ?? resolvedPDFURL(for: paper)
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

    @discardableResult
    func attachPDF(to paperID: UUID, from url: URL, originalFileName: String? = nil) -> Bool {
        attachFile(to: paperID, from: url, originalFileName: originalFileName)
    }

    @discardableResult
    func attachFile(to paperID: UUID, from url: URL, originalFileName: String? = nil) -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }

        do {
            var paper = papers[index]
            let folderURL = try ensurePaperDirectory(for: &paper)
            let preferredName = originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceName = preferredName?.isEmpty == false ? preferredName! : url.lastPathComponent
            let safeName = sanitizeFileName(sourceName)
            let destinationURL = uniqueAssetDestinationURL(in: folderURL, preferredFileName: safeName)
            try fileManager.copyItem(at: url, to: destinationURL)
            ensureEditablePDF(at: destinationURL)

            paper.storedPDFFileName = destinationURL.lastPathComponent
            paper.originalPDFFileName = sourceName
            paper.preferredOpenPDFFileName = destinationURL.lastPathComponent
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            papers[index] = paper
            save()
            return true
        } catch {
            NSSound.beep()
            print("添加附件失败: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func replaceDefaultAttachment(for paperID: UUID, with url: URL, originalFileName: String? = nil) -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }

        do {
            var paper = papers[index]
            let existingURL = defaultOpenPDFURL(for: paper)
            let folderURL = try ensurePaperDirectory(for: &paper)
            let preferredName = originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceName = preferredName?.isEmpty == false ? preferredName! : url.lastPathComponent
            let safeName = sanitizeFileName(sourceName)
            let destinationURL = uniqueAssetDestinationURL(in: folderURL, preferredFileName: safeName)

            try fileManager.copyItem(at: url, to: destinationURL)
            ensureEditablePDF(at: destinationURL)

            if let existingURL,
               fileManager.fileExists(atPath: existingURL.path),
               existingURL.standardizedFileURL != url.standardizedFileURL,
               existingURL.standardizedFileURL != destinationURL.standardizedFileURL {
                ensureEditablePDF(at: existingURL)
                try fileManager.removeItem(at: existingURL)
            }

            paper.storedPDFFileName = destinationURL.lastPathComponent
            paper.originalPDFFileName = sourceName
            paper.preferredOpenPDFFileName = destinationURL.lastPathComponent
            paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
            papers[index] = paper
            save()
            return true
        } catch {
            NSSound.beep()
            print("替换附件失败: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func ensurePaperDirectory(for paperID: UUID) -> URL? {
        guard let index = indexOfPaper(id: paperID) else { return nil }
        do {
            var paper = papers[index]
            let folderURL = try ensurePaperDirectory(for: &paper)
            papers[index] = paper
            save()
            return folderURL
        } catch {
            NSSound.beep()
            print("创建条目文件夹失败: \(error.localizedDescription)")
            return nil
        }
    }

    func hasExistingPDFAttachment(for paper: Paper) -> Bool {
        // Use pre-computed cache when available to avoid filesystem I/O.
        if let cached = attachmentPresenceCache[paper.id] {
            return !cached.isMissing
        }
        return !attachmentURLs(for: paper).isEmpty
    }

    func attachmentURLs(for paper: Paper) -> [URL] {
        var urls: [URL] = []
        var seenPaths: Set<String> = []

        func appendIfExistingAttachment(_ url: URL) {
            let fileName = url.lastPathComponent
            guard !isInternalPaperFileName(fileName),
                  fileManager.fileExists(atPath: url.path) else {
                return
            }
            let key = url.standardizedFileURL.path
            guard seenPaths.insert(key).inserted else { return }
            urls.append(url)
        }

        for url in availablePDFURLs(for: paper) {
            appendIfExistingAttachment(url)
        }
        for url in imageURLs(for: paper) {
            appendIfExistingAttachment(url)
        }

        return urls
    }

    func paperDirectoryURL(for paper: Paper) -> URL? {
        guard let storageFolderName = paper.storageFolderName else {
            return nil
        }
        return papersDirectory.appendingPathComponent(storageFolderName, isDirectory: true)
    }

    private func ensurePaperDirectory(for paper: inout Paper) throws -> URL {
        try ensureStorageDirectories()

        let folderURL: URL
        if let existingFolderURL = paperDirectoryURL(for: paper) {
            folderURL = existingFolderURL
        } else {
            let folderName = UUID().uuidString
            folderURL = papersDirectory.appendingPathComponent(folderName, isDirectory: true)
            paper.storageFolderName = folderName
        }

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        _ = try ensureImagesDirectoryExists(at: folderURL)
        if !fileManager.fileExists(atPath: canonicalNoteURL(in: folderURL).path) {
            try paper.notes.write(to: canonicalNoteURL(in: folderURL), atomically: true, encoding: .utf8)
        }
        return folderURL
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
        return paper.imageFileNames.compactMap { imageFileName in
            let url = existingImageURL(named: imageFileName, in: folderURL)
                ?? canonicalImageURL(named: imageFileName, in: folderURL)
            guard supportedImageExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            return url
        }
    }

    func localMetadataSuggestion(for paper: Paper) -> MetadataSuggestion? {
        guard let url = pdfURL(for: paper),
              url.pathExtension.lowercased() == "pdf" else {
            return nil
        }

        let metadata = extractPDFCoreMetadata(from: url)
        let titleHasHan = containsHanCharacters(metadata.title)
        let authorsHasHan = containsHanCharacters(metadata.authors)
        let suggestion = MetadataSuggestion(
            title: metadata.title,
            englishTitle: titleHasHan ? "" : metadata.title,
            authors: metadata.authors,
            authorsEnglish: authorsHasHan ? "" : metadata.authors,
            year: metadata.year,
            source: metadata.source,
            doi: metadata.doi,
            abstractText: metadata.abstractText,
            chineseAbstract: containsHanCharacters(metadata.abstractText) ? metadata.abstractText : "",
            volume: metadata.volume,
            issue: metadata.issue,
            pages: metadata.pages,
            paperType: metadata.paperType
        ).normalized()

        let fields: [MetadataField] = [
            .title, .englishTitle, .authors, .authorsEnglish, .year, .source, .doi,
            .abstractText, .chineseAbstract, .volume, .issue, .pages, .paperType
        ]
        guard fields.contains(where: {
            !MetadataValueNormalizer.normalize($0.value(in: suggestion), for: $0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }) else {
            return nil
        }
        return suggestion
    }

    private func attachmentPresenceSignature(for paper: Paper) -> String {
        [
            paper.storageFolderName ?? "",
            paper.storedPDFFileName ?? "",
            paper.originalPDFFileName ?? "",
            paper.preferredOpenPDFFileName ?? "",
            paper.imageFileNames.joined(separator: "\u{1F}")
        ]
        .joined(separator: "\u{1E}")
    }

    private func isInternalPaperFileName(_ fileName: String) -> Bool {
        fileName == canonicalNoteFileName
            || fileName == legacyNoteFileName
            || fileName == imagesDirectoryName
            || fileName.hasPrefix(".")
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

    @discardableResult
    func removeImage(from paperID: UUID, fileName: String) -> Bool {
        guard let index = indexOfPaper(id: paperID) else { return false }
        var paper = papers[index]
        guard let imageURL = imageURL(for: paper, fileName: fileName) else { return false }
        try? fileManager.removeItem(at: imageURL)
        paper.imageFileNames.removeAll(where: { $0 == fileName })
        paper.lastEditedAtMilliseconds = Paper.currentTimestampMilliseconds()
        papers[index] = paper
        save()
        return true
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

        let targetFileName: String = {
            let base = preferredPDFFileName(for: paper)
            let currentStem = currentURL.deletingPathExtension().lastPathComponent
            // Preserve translation suffixes (-dual, -zh, -en) when renaming PDFs.
            // The base file name is generated from metadata which doesn't include these suffixes.
            let knownSuffixes = ["-dual", "-zh", "-en"]
            for suffix in knownSuffixes {
                if currentStem.hasSuffix(suffix) {
                    return base.replacingOccurrences(of: ".pdf", with: "\(suffix).pdf")
                }
            }
            return base
        }()
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
        case .library(.recentlyDeleted):
            return sidebarCountSnapshot.recentlyDeleted
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
        let base = scopedPapers(for: selection)

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

    func scopedPapers(for selection: SidebarSelection) -> [Paper] {
        switch selection {
        case .library(.all):
            return papersForStableSelection(.library(.all))
        case .library(.recentReading):
            let cutoff = Date().addingTimeInterval(-settings.recentReadingRange.interval)
            return papers.filter { paper in
                guard !paper.isDeleted else { return false }
                guard let lastOpenedAt = paper.lastOpenedAt else {
                    return false
                }
                return lastOpenedAt >= cutoff
            }
        case .library(.zombiePapers):
            let cutoff = Date().addingTimeInterval(-settings.resolvedZombiePapersInterval)
            return papers.filter { paper in
                guard !paper.isDeleted else { return false }
                guard paper.addedAtDate <= cutoff else { return false }
                guard let editedAt = paper.editedAtDate else { return true }
                return editedAt < cutoff
            }
        case .library(.unfiled):
            return papersForStableSelection(.library(.unfiled))
        case .library(.missingDOI):
            return papersForStableSelection(.library(.missingDOI))
        case .library(.missingAttachment):
            ensureAttachmentPresenceSnapshotFresh()
            return papersForStableSelection(.library(.missingAttachment))
        case .library(.recentlyDeleted):
            return papersForStableSelection(.library(.recentlyDeleted))
                .sorted {
                    ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
                }
        case .collection(let name):
            return papersForStableSelection(.collection(name))
        case .tag(let name):
            return papersForStableSelection(.tag(name))
        }
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
            zombieInterval: settings.resolvedZombiePapersInterval,
            recentlyDeletedRetentionInterval: settings.resolvedRecentlyDeletedRetentionInterval
        )
        guard current != lastDynamicCountConfig else { return }
        recomputeSidebarCountSnapshot()
    }

    private func matchesPlainText(_ query: String, in paper: Paper) -> Bool {
        paperTextContainsQuery(query, in: paper.searchIndexBlob)
    }

    private func paperTextContainsQuery(_ query: String, in source: String) -> Bool {
        guard !query.isEmpty, !source.isEmpty else { return false }
        if source.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil {
            return true
        }

        let normalizedQuery = AuthorNameParser.normalizedToken(from: query)
        guard !normalizedQuery.isEmpty else { return false }
        let normalizedSource = AuthorNameParser.normalizedToken(from: source)
        guard !normalizedSource.isEmpty else { return false }

        return normalizedSource.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func recomputeSidebarCountSnapshot(forceAttachmentRevalidation: Bool = false) {
        let perfStart = PerformanceMonitor.now()
        let dynamicConfig = DynamicCountConfig(
            recentReadingInterval: settings.recentReadingRange.interval,
            zombieInterval: settings.resolvedZombiePapersInterval,
            recentlyDeletedRetentionInterval: settings.resolvedRecentlyDeletedRetentionInterval
        )
        let now = Date()
        let recentReadingCutoff = now.addingTimeInterval(-dynamicConfig.recentReadingInterval)
        let zombieCutoff = now.addingTimeInterval(-dynamicConfig.zombieInterval)

        var snapshot = SidebarCountSnapshot.empty
        var nextStableSelectionPaperIDs: [SidebarSelection: [UUID]] = [
            .library(.all): [],
            .library(.unfiled): [],
            .library(.missingDOI): [],
            .library(.missingAttachment): [],
            .library(.recentlyDeleted): []
        ]
        var nextPaperIndexByID: [UUID: Int] = [:]
        nextPaperIndexByID.reserveCapacity(papers.count)
        var nextAttachmentPresenceCache: [UUID: AttachmentPresenceCacheEntry] = [:]
        nextAttachmentPresenceCache.reserveCapacity(papers.count)

        for (index, paper) in papers.enumerated() {
            nextPaperIndexByID[paper.id] = index

            if paper.isDeleted {
                snapshot.recentlyDeleted += 1
                nextStableSelectionPaperIDs[.library(.recentlyDeleted), default: []].append(paper.id)
                continue
            }

            snapshot.all += 1
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

            let attachmentSignature = attachmentPresenceSignature(for: paper)
            let hasMissingAttachment: Bool
            if !forceAttachmentRevalidation,
               let cached = attachmentPresenceCache[paper.id],
               cached.signature == attachmentSignature {
                hasMissingAttachment = cached.isMissing
            } else {
                hasMissingAttachment = attachmentURLs(for: paper).isEmpty
            }
            nextAttachmentPresenceCache[paper.id] = AttachmentPresenceCacheEntry(
                signature: attachmentSignature,
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
            collectionMetadata = snapshot.collectionMetadata
            tagMetadata = snapshot.tagMetadata
            if didNormalizeStoredState {
                save()
            }
        } catch {
            NSSound.beep()
            print("读取资料库失败: \(error.localizedDescription)")
        }
    }

    func suspendAutoSave() {
        autoSaveSuspended = true
    }

    func resumeAutoSave() {
        autoSaveSuspended = false
        // Flush any pending write that was skipped during suspension
        if pendingSaveTask != nil {
            flushPendingSaveNow()
        }
    }

    private func save() {
        // When in background, extend debounce to 2 s to reduce I/O pressure.
        let delay: UInt64 = autoSaveSuspended ? 2_000_000_000 : 220_000_000
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
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
                tagColorHexes: tagColorHexes,
                collectionMetadata: collectionMetadata,
                tagMetadata: tagMetadata
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

    private func taxonomyItems(for kind: TaxonomyKind) -> [String] {
        switch kind {
        case .collection:
            return collections
        case .tag:
            return tags
        }
    }

    private func setTaxonomyItems(_ items: [String], for kind: TaxonomyKind) {
        switch kind {
        case .collection:
            collections = items
        case .tag:
            tags = items
        }
    }

    private func replaceTaxonomyPrefix(kind: TaxonomyKind, oldPrefix: String, newPrefix: String) {
        let remap: (String) -> String = { value in
            guard TaxonomyHierarchy.isDescendant(value, of: oldPrefix) else { return value }
            if value == oldPrefix {
                return newPrefix
            }
            let suffix = value.dropFirst(oldPrefix.count + TaxonomyHierarchy.separator.count)
            return "\(newPrefix)\(TaxonomyHierarchy.separator)\(suffix)"
        }

        switch kind {
        case .collection:
            collections = collections.map(remap).uniquedAndSorted()
            collectionMetadata = remappedTaxonomyMetadata(collectionMetadata, using: remap)
            for index in papers.indices {
                var paper = papers[index]
                let updated = paper.collections.map(remap).uniquedAndSorted()
                if updated != paper.collections {
                    paper.collections = updated
                    papers[index] = paper
                }
            }
        case .tag:
            tags = tags.map(remap).uniquedAndSorted()
            tagMetadata = remappedTaxonomyMetadata(tagMetadata, using: remap)
            for index in papers.indices {
                var paper = papers[index]
                let updated = paper.tags.map(remap).uniquedAndSorted()
                if updated != paper.tags {
                    paper.tags = updated
                    papers[index] = paper
                }
            }

            var nextColors: [String: String] = [:]
            for (tag, color) in tagColorHexes {
                nextColors[remap(tag)] = color
            }
            tagColorHexes = nextColors
        }
    }

    private func remappedTaxonomyMetadata(
        _ metadata: [String: TaxonomyItemMetadata],
        using remap: (String) -> String
    ) -> [String: TaxonomyItemMetadata] {
        var next: [String: TaxonomyItemMetadata] = [:]
        for (path, value) in metadata {
            next[remap(path)] = value
        }
        return next
    }

    private func uniqueTaxonomyPath(_ proposedPath: String, kind: TaxonomyKind, excludingPrefix: String? = nil) -> String {
        let existing = Set(
            taxonomyItems(for: kind).filter { item in
                guard let excludingPrefix else { return true }
                return !TaxonomyHierarchy.isDescendant(item, of: excludingPrefix)
            }
        )
        guard existing.contains(proposedPath) else { return proposedPath }

        let parent = TaxonomyHierarchy.parentPath(of: proposedPath)
        let leaf = TaxonomyHierarchy.leafName(of: proposedPath)
        for index in 2...999 {
            let candidate = TaxonomyHierarchy.path(parent: parent, name: "\(leaf) \(index)")
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return proposedPath
    }

    private func syncTaxonomies() {
        let activePapers = papers.filter { !$0.isDeleted }

        let usedCollections = activePapers
            .flatMap(\.collections)
            .map(TaxonomyHierarchy.normalizedPath)
            .filter { !$0.isEmpty }
            .uniquedAndSorted()

        let usedTags = activePapers
            .flatMap(\.tags)
            .map(TaxonomyHierarchy.normalizedPath)
            .filter { !$0.isEmpty }
            .uniquedAndSorted()

        let collectionAncestors = usedCollections.flatMap { TaxonomyHierarchy.ancestors(of: $0) }
        let tagAncestors = usedTags.flatMap { TaxonomyHierarchy.ancestors(of: $0) }
        collections = (collections.map(TaxonomyHierarchy.normalizedPath) + usedCollections + collectionAncestors)
            .filter { !$0.isEmpty }
            .uniquedAndSorted()
        tags = (tags.map(TaxonomyHierarchy.normalizedPath) + usedTags + tagAncestors)
            .filter { !$0.isEmpty }
            .uniquedAndSorted()
        let validCollections = Set(collections)
        let validTags = Set(tags)
        collectionMetadata = collectionMetadata.filter { validCollections.contains($0.key) }
        tagMetadata = tagMetadata.filter { validTags.contains($0.key) }
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
        let webPageURL = (entry.fields["url"] ?? entry.fields["URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = mappedPaperType(from: entry.type)

        return Paper(
            title: title,
            authors: authors,
            year: year,
            source: source,
            doi: doi,
            abstractText: abstractText,
            chineseAbstract: containsHanCharacters(abstractText) ? abstractText : "",
            notes: "",
            paperType: type,
            volume: volume,
            issue: issue,
            pages: pages,
            webPageURL: webPageURL,
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
            let trimmedTag = TaxonomyHierarchy.normalizedPath(tag)
            guard !trimmedTag.isEmpty else { continue }
            tagColorHexes[trimmedTag] = colorHex
        }

        for (collection, metadata) in snapshot.collectionMetadata {
            let normalized = TaxonomyHierarchy.normalizedPath(collection)
            guard !normalized.isEmpty else { continue }
            collectionMetadata[normalized] = metadata
        }

        for (tag, metadata) in snapshot.tagMetadata {
            let normalized = TaxonomyHierarchy.normalizedPath(tag)
            guard !normalized.isEmpty else { continue }
            tagMetadata[normalized] = metadata
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
            webPageURL: incoming.webPageURL,
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
        normalizeDOIIdentifier(doi)
    }

    private func duplicateTitleAuthorKey(title: String, authors: String) -> String {
        let titleKey = normalizedPaperTitle(title)
        let authorKey = normalizedAuthorList(authors)
        guard !titleKey.isEmpty, !authorKey.isEmpty else { return "" }
        return "\(titleKey)|\(authorKey)"
    }

    private func normalizedAuthorList(_ authors: String) -> String {
        let parsed = AuthorNameParser.parse(raw: authors, dropEtAl: true)
            .map(normalizedPaperTitle)
            .filter { !$0.isEmpty && $0 != "unknown" && $0 != "未知" }
            .sorted()

        if !parsed.isEmpty {
            return parsed.joined(separator: "|")
        }

        let fallback = normalizedPaperTitle(authors)
        guard fallback != "unknown", fallback != "未知" else { return "" }
        return fallback
    }

    private func duplicateDisplayName(title: String, authors: String, doi: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedTitle.isEmpty ? "Untitled Paper" : trimmedTitle
        let trimmedDOI = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDOI.isEmpty else { return base }
        return "\(base) [\(trimmedDOI)]"
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
        var source: String = ""
        var doi: String = ""
        var abstractText: String = ""
        var volume: String = ""
        var issue: String = ""
        var pages: String = ""
        var paperType: String = ""
    }

    private func extractDocumentCoreMetadata(from url: URL) -> PDFCoreMetadata {
        if url.pathExtension.lowercased() == "pdf" {
            return extractPDFCoreMetadata(from: url)
        }

        var metadata = PDFCoreMetadata()
        if let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
            if let createdDate = values.creationDate {
                metadata.year = yearString(from: createdDate)
            } else if let modifiedDate = values.contentModificationDate {
                metadata.year = yearString(from: modifiedDate)
            }
        }
        metadata.source = detectSourceInFileName(url)
        return metadata
    }

    private func extractPDFCoreMetadata(from url: URL) -> PDFCoreMetadata {
        guard let document = PDFDocument(url: url) else {
            return PDFCoreMetadata()
        }

        let attributes = document.documentAttributes ?? [:]
        var metadata = PDFCoreMetadata()
        let attributeTitle = MetadataValueNormalizer.normalizeTitle(
            (attributes[PDFDocumentAttribute.titleAttribute] as? String) ?? ""
        )
        let attributeAuthors = MetadataValueNormalizer.normalizeAuthors(
            (attributes[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
        )
        let attributeSource = MetadataValueNormalizer.normalizeSource(
            (attributes[PDFDocumentAttribute.subjectAttribute] as? String) ?? ""
        )
        let attributeYear: String = {
            if let createdDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
                return yearString(from: createdDate)
            }
            if let modifiedDate = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date {
                return yearString(from: modifiedDate)
            }
            return ""
        }()

        var excerpt = ""
        let upperBound = min(document.pageCount, 8)
        for index in 0..<upperBound {
            guard let text = document.page(at: index)?.string else { continue }
            excerpt.append(text)
            excerpt.append("\n")
            if excerpt.count >= 40_000 {
                break
            }
        }
        if excerpt.count > 40_000 {
            excerpt = String(excerpt.prefix(40_000))
        }

        metadata.doi = MetadataValueNormalizer.normalizeDOI(detectDOI(in: excerpt))

        let detectedTitle = MetadataValueNormalizer.normalizeTitle(detectTitleInFrontMatter(excerpt))
        metadata.title = detectedTitle.isEmpty ? attributeTitle : detectedTitle

        let detectedAuthors = MetadataValueNormalizer.normalizeAuthors(
            detectAuthorsInFrontMatter(excerpt, title: metadata.title)
        )
        metadata.authors = detectedAuthors.isEmpty ? attributeAuthors : detectedAuthors

        let detectedYear = MetadataValueNormalizer.normalizeYear(detectPublicationYear(in: excerpt))
        metadata.year = detectedYear.isEmpty ? attributeYear : detectedYear

        let detectedSource = MetadataValueNormalizer.normalizeSource(detectSourceInFrontMatter(excerpt))
        metadata.source = detectedSource.isEmpty ? attributeSource : detectedSource

        metadata.abstractText = MetadataValueNormalizer.normalize(
            detectAbstractInFrontMatter(excerpt),
            for: .abstractText
        )

        let citationMetadata = detectCitationMetadata(in: excerpt)
        metadata.volume = MetadataValueNormalizer.normalizeVolume(citationMetadata.volume)
        metadata.issue = MetadataValueNormalizer.normalizeIssue(citationMetadata.issue)
        metadata.pages = MetadataValueNormalizer.normalizePages(citationMetadata.pages)
        metadata.paperType = inferPaperType(source: metadata.source, frontMatterText: excerpt)

        return metadata
    }

    private func detectSourceInFileName(_ url: URL) -> String {
        let parts = url.deletingPathExtension().lastPathComponent
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 4 else { return "" }
        return parts[3]
    }

    private func yearString(from date: Date) -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        if (1900...(Calendar.current.component(.year, from: .now) + 1)).contains(year) {
            return String(year)
        }
        return ""
    }

    private func containsHanCharacters(_ value: String) -> Bool {
        value.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private func detectTitleInFrontMatter(_ text: String) -> String {
        let lines = frontMatterLines(from: text, limit: 72)
        if let explicitTitle = explicitTitleInFrontMatter(lines) {
            return explicitTitle
        }

        let preferredRange: Range<Int>? = {
            guard let markerIndex = lines.firstIndex(where: { $0.lowercased().contains("publication details") }) else {
                return nil
            }
            return (markerIndex + 1)..<min(lines.count, markerIndex + 10)
        }()
        var bestCandidate = ""
        var bestScore = Int.min

        for (index, line) in lines.enumerated() {
            if isFrontMatterStopLine(line), !bestCandidate.isEmpty {
                break
            }

            let candidates = titleCandidates(startingAt: index, lines: lines)
            for candidate in candidates {
                let normalized = MetadataValueNormalizer.normalizeTitle(candidate)
                guard !normalized.isEmpty, isPotentialTitleLine(normalized) else { continue }
                var score = titleCandidateScore(normalized, lineIndex: index)
                if let preferredRange, preferredRange.contains(index) {
                    score += 24
                }
                if score > bestScore {
                    bestCandidate = normalized
                    bestScore = score
                }
            }
        }

        return bestCandidate
    }

    private func explicitTitleInFrontMatter(_ lines: [String]) -> String? {
        for line in lines.prefix(36) {
            let patterns = [
                #"(?i)^(?:title|article title|paper title)\s*[:：]\s*(.+)$"#,
                #"^(?:题名|标题|论文题目)\s*[:：]\s*(.+)$"#
            ]
            for pattern in patterns {
                guard let groups = firstRegexGroups(in: line, pattern: pattern),
                      let candidate = groups[safe: 1] else {
                    continue
                }
                let normalized = MetadataValueNormalizer.normalizeTitle(candidate)
                if !normalized.isEmpty, isPotentialTitleLine(normalized) {
                    return normalized
                }
            }
        }
        return nil
    }

    private func detectAuthorsInFrontMatter(_ text: String, title: String) -> String {
        let referenceAuthors = detectAuthorsFromReferenceFormat(text)
        if !referenceAuthors.isEmpty {
            return referenceAuthors
        }

        let titleNormalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let lines = frontMatterLines(from: text, limit: 96)
        let titleIndex = lines.firstIndex { line in
            let normalizedLine = line
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !titleNormalized.isEmpty
                && (normalizedLine == titleNormalized
                    || normalizedLine.contains(titleNormalized)
                    || titleNormalized.contains(normalizedLine))
        }

        if let titleIndex {
            let upperBound = min(lines.count, titleIndex + 24)
            var collectedAuthors: [String] = []
            for index in (titleIndex + 1)..<upperBound {
                if isFrontMatterStopLine(lines[index]) { break }
                if let authors = normalizedAuthors(fromFrontMatterLine: lines[index]) {
                    collectedAuthors.append(contentsOf: AuthorNameParser.parse(raw: authors))
                    continue
                }
                if index + 1 < upperBound {
                    let combined = "\(lines[index]); \(lines[index + 1])"
                    if let authors = normalizedAuthors(fromFrontMatterLine: combined) {
                        collectedAuthors.append(contentsOf: AuthorNameParser.parse(raw: authors))
                    }
                }
            }
            let normalized = normalizedUniqueAuthors(collectedAuthors)
            if !normalized.isEmpty {
                return normalized
            }
        }

        for line in lines.prefix(48) {
            let normalizedLine = line
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !titleNormalized.isEmpty && normalizedLine == titleNormalized {
                continue
            }

            if let authors = normalizedAuthors(fromFrontMatterLine: line) {
                return authors
            }
        }

        return ""
    }

    private func detectAuthorsFromReferenceFormat(_ text: String) -> String {
        let lines = frontMatterLines(from: text, limit: 180)
        guard let markerIndex = lines.firstIndex(where: {
            $0.lowercased().contains("reference format")
                || $0.lowercased().contains("recommended citation")
                || $0.contains("引用格式")
        }) else {
            return ""
        }

        let citation = lines[(markerIndex + 1)..<min(lines.count, markerIndex + 8)]
            .joined(separator: " ")
        let patterns = [
            #"^(.+?)\.\s*(?:19|20)\d{2}\.\s+"#,
            #"^(.+?)\s+(?:19|20)\d{2}\.\s+"#
        ]
        for pattern in patterns {
            guard let groups = firstRegexGroups(in: citation, pattern: pattern),
                  let authorSegment = groups[safe: 1] else {
                continue
            }
            let normalized = MetadataValueNormalizer.normalizeAuthors(authorSegment)
            let authors = AuthorNameParser.parse(raw: normalized)
                .filter { looksLikePersonName($0) }
            let result = normalizedUniqueAuthors(authors)
            if !result.isEmpty {
                return result
            }
        }

        return ""
    }

    private func normalizedUniqueAuthors(_ authors: [String]) -> String {
        var seen: Set<String> = []
        let normalized = authors.compactMap { rawName -> String? in
            let name = MetadataValueNormalizer.cleanSingleLine(rawName)
            guard !name.isEmpty, looksLikePersonName(name) else { return nil }
            let key = AuthorNameParser.normalizedToken(from: name)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return name
        }
        return normalized.joined(separator: ", ")
    }

    private func looksLikePersonName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,;:|/\\()[]{}<>*"))
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil {
            return false
        }
        if trimmed.contains("@") || trimmed.contains("http") {
            return false
        }
        if isLikelyFrontMatterNoise(trimmed) {
            return false
        }
        let loweredName = trimmed.lowercased()
        let titleLikeTokens = [
            "effect", "effects", "study", "analysis", "learning", "education", "research",
            "model", "impact", "teacher", "teachers", "student", "students", "using",
            "based", "review", "systematic", "development", "assessment", "approach",
            "generative", "productivity", "support", "tools", "reliance", "automation",
            "feedback", "intelligence"
        ]
        if titleLikeTokens.contains(where: { loweredName.contains($0) }) {
            return false
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, words.count <= 6 {
            return words.allSatisfy { token in
                let value = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
                guard !value.isEmpty else { return false }
                let lowered = value.lowercased()
                if ["de", "del", "der", "van", "von", "al", "bin", "da", "dos"].contains(lowered) {
                    return true
                }
                if value.count == 1 {
                    return true
                }
                guard let first = value.unicodeScalars.first else { return false }
                return CharacterSet.uppercaseLetters.contains(first)
            }
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
        let currentYear = Calendar.current.component(.year, from: .now)
        let lines = frontMatterLines(from: text, limit: 120)

        func firstValidYear(in value: String) -> String? {
            let nsValue = value as NSString
            let range = NSRange(location: 0, length: nsValue.length)
            for match in regex.matches(in: value, options: [], range: range) {
                let token = nsValue.substring(with: match.range)
                guard let year = Int(token), (1900...(currentYear + 1)).contains(year) else { continue }
                return token
            }
            return nil
        }

        let dateContextTokens = [
            "published", "publication", "copyright", "©", "received", "accepted",
            "available online", "volume", "vol.", "issue", "no."
        ]
        for line in lines {
            let lowered = line.lowercased()
            guard dateContextTokens.contains(where: { lowered.contains($0) }) else { continue }
            if let year = firstValidYear(in: line) {
                return year
            }
        }

        for line in lines {
            if let year = firstValidYear(in: line) {
                return year
            }
        }
        return ""
    }

    private func detectSourceInFrontMatter(_ text: String) -> String {
        let lines = frontMatterLines(from: text, limit: 96)
        if let source = sourceFromReferenceFormat(lines) {
            return source
        }

        if let markerIndex = lines.firstIndex(where: { $0.lowercased().contains("publication details") }) {
            let lowerBound = max(0, markerIndex - 6)
            let fragments = lines[lowerBound..<markerIndex].filter { line in
                !isLikelyPublicationBoilerplate(line)
            }
            let maxFragmentCount = min(3, fragments.count)
            for length in stride(from: maxFragmentCount, through: 1, by: -1) {
                let candidate = fragments.suffix(length).joined(separator: " ")
                let source = MetadataValueNormalizer.normalizeSource(candidate)
                if !source.isEmpty, !isLikelyFrontMatterNoise(source), source.count >= 5 {
                    return source
                }
            }
        }

        for line in lines.prefix(48) {
            let lowered = line.lowercased()
            guard line.count >= 4, line.count <= 180 else { continue }
            if isLikelyFrontMatterNoise(line) {
                continue
            }
            if let source = sourceFromCitationLine(line) {
                return source
            }
            if lowered.contains("journal homepage")
                || lowered.contains("contents lists available") {
                continue
            }
            if lowered.contains("journal of")
                || lowered.contains("proceedings")
                || lowered.contains("conference")
                || lowered.contains("transactions on")
                || lowered.contains("期刊")
                || lowered.contains("学报")
                || lowered.contains("会议") {
                return MetadataValueNormalizer.normalizeSource(line)
            }
        }

        return ""
    }

    private func sourceFromReferenceFormat(_ lines: [String]) -> String? {
        guard let markerIndex = lines.firstIndex(where: {
            $0.lowercased().contains("reference format")
                || $0.lowercased().contains("recommended citation")
                || $0.contains("引用格式")
        }) else {
            return nil
        }

        let citation = lines[(markerIndex + 1)..<min(lines.count, markerIndex + 8)]
            .joined(separator: " ")
        let patterns = [
            #"(?i)\bIn\s+(.+?)\s*\("#,
            #"(?i)\bIn\s+(.+?)\.\s+"#,
            #",\s*([^,]{4,140}?)\s*,\s*\d{1,4}\s*[:(]"#
        ]
        for pattern in patterns {
            guard let groups = firstRegexGroups(in: citation, pattern: pattern),
                  let rawSource = groups[safe: 1] else {
                continue
            }
            let source = MetadataValueNormalizer.normalizeSource(rawSource)
            if !source.isEmpty {
                return source
            }
        }
        return nil
    }

    private func isLikelyPublicationBoilerplate(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return isLikelyFrontMatterNoise(line)
            || lowered.hasPrefix("publisher:")
            || lowered.contains("registered in")
            || lowered.hasPrefix("office:")
            || lowered.contains("subscription information")
            || lowered.contains("http")
    }

    private func sourceFromCitationLine(_ line: String) -> String? {
        let patterns = [
            #"(?i)^(.{4,140}?)\s+\bvol(?:ume)?\.?\s*\d+\b.*$"#,
            #"(?i)^(.{4,140}?)\s+\b\d{1,4}\s*\(\s*[A-Za-z]?\d+[A-Za-z]?\s*\).*$"#,
            #"^(.{4,140}?)\s+第\s*\d+\s*卷.*$"#,
            #"^(.{4,140}?)\s+\d+\s*卷\s*\d+\s*期.*$"#
        ]
        for pattern in patterns {
            guard let groups = firstRegexGroups(in: line, pattern: pattern),
                  let rawSource = groups[safe: 1] else {
                continue
            }
            let source = MetadataValueNormalizer.normalizeSource(rawSource)
            if !source.isEmpty {
                return source
            }
        }
        return nil
    }

    private func detectAbstractInFrontMatter(_ text: String) -> String {
        let lines = frontMatterLines(from: text, limit: 180)
        var fragments: [String] = []
        var isCollecting = false

        for line in lines {
            if !isCollecting {
                guard let payload = abstractPayload(fromStartLine: line) else { continue }
                isCollecting = true
                if !payload.isEmpty {
                    fragments.append(payload)
                }
                continue
            }

            if isAbstractStopLine(line) {
                break
            }
            fragments.append(line)
            if fragments.joined(separator: " ").count >= 1_800 {
                break
            }
        }

        let abstract = MetadataValueNormalizer.cleanSingleLine(fragments.joined(separator: " "))
        guard abstract.count >= 24 else { return "" }
        return String(abstract.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func abstractPayload(fromStartLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()

        if lowered == "abstract" || lowered == "summary" || trimmed == "摘要" {
            return ""
        }

        let patterns = [
            #"(?i)^abstract\s*[:：.\-]?\s*(.+)$"#,
            #"(?i)^summary\s*[:：.\-]?\s*(.+)$"#,
            #"^摘要\s*[:：]?\s*(.+)$"#
        ]
        for pattern in patterns {
            if let groups = firstRegexGroups(in: trimmed, pattern: pattern),
               let payload = groups[safe: 1] {
                return payload
            }
        }
        return nil
    }

    private func isAbstractStopLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered == "keywords" || lowered.hasPrefix("keywords:")
            || lowered.hasPrefix("key words")
            || lowered == "introduction"
            || lowered.hasPrefix("1 introduction")
            || lowered.hasPrefix("1. introduction")
            || lowered == "references"
            || lowered.hasPrefix("acknowledg") {
            return true
        }
        if line.hasPrefix("关键词") || line.hasPrefix("引言") || line.hasPrefix("参考文献") {
            return true
        }
        return false
    }

    private func inferPaperType(source: String, frontMatterText: String) -> String {
        let normalized = "\(source) \(frontMatterLines(from: frontMatterText, limit: 48).joined(separator: " "))"
        let lowered = normalized.lowercased()
        if lowered.contains("proceedings")
            || lowered.contains("conference")
            || normalized.contains("会议") {
            return "会议论文"
        }
        if lowered.contains("journal")
            || lowered.contains("transactions on")
            || normalized.contains("期刊")
            || normalized.contains("学报") {
            return "期刊文章"
        }
        return ""
    }

    private func detectCitationMetadata(in text: String) -> (volume: String, issue: String, pages: String) {
        let frontMatter = frontMatterLines(from: text, limit: 140)
            .prefix(140)
            .joined(separator: "\n")
        let normalized = MetadataValueNormalizer.cleanSingleLine(frontMatter)
        var volume = ""
        var issue = ""
        var pages = ""

        if let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\bvol(?:ume)?\.?\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b.*?\b(?:no\.?|number|issue)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b.*?\b([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?|e\d+)\b"#
        ) {
            volume = match[safe: 1] ?? ""
            issue = match[safe: 2] ?? ""
            pages = match[safe: 3] ?? ""
        }

        if volume.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\bvolume\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b.*?\bissue\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b.*?\bpages?\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?|e\d+)\b"#
           ) {
            volume = match[safe: 1] ?? ""
            issue = match[safe: 2] ?? ""
            pages = match[safe: 3] ?? ""
        }

        if volume.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"第\s*([A-Za-z]?\d+[A-Za-z]?)\s*卷\s*第?\s*([A-Za-z]?\d+[A-Za-z]?)\s*期.*?([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?)"#
           ) {
            volume = match[safe: 1] ?? ""
            issue = match[safe: 2] ?? ""
            pages = match[safe: 3] ?? ""
        }

        if volume.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b([1-9]\d{0,3})\s*:\s*([A-Za-z]?\d+[A-Za-z]?)\s*,\s*([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?)\b"#
           ) {
            volume = match[safe: 1] ?? ""
            issue = match[safe: 2] ?? ""
            pages = match[safe: 3] ?? ""
        }

        if let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\bvol(?:ume)?\.?\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b[,\s;|]*(?:no\.?|number|issue)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b"#
        ) {
            if volume.isEmpty {
                volume = match[safe: 1] ?? ""
            }
            if issue.isEmpty {
                issue = match[safe: 2] ?? ""
            }
        }

        if volume.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\bvol(?:ume)?\.?\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b"#
           ) {
            volume = match[safe: 1] ?? ""
        }

        if issue.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b(?:issue|number|no\.?)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b"#
           ) {
            issue = match[safe: 1] ?? ""
        }

        if let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b([A-Za-z]?\d{1,4}[A-Za-z]?)\s*\(\s*([A-Za-z]?\d{1,4}[A-Za-z]?)\s*\)\s*[:,]?\s*(?:pp?\.?|pages?)?\s*([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?|e\d+)\b"#
        ) {
            if volume.isEmpty {
                volume = match[safe: 1] ?? ""
            }
            if issue.isEmpty {
                issue = match[safe: 2] ?? ""
            }
            if pages.isEmpty {
                pages = match[safe: 3] ?? ""
            }
        }

        if let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b([1-9]\d{0,3})\s*\(\s*(?:19|20)\d{2}\s*\)\s*([A-Za-z]?\d{4,}[A-Za-z]?)\b"#
        ) {
            if volume.isEmpty {
                volume = match[safe: 1] ?? ""
            }
            if pages.isEmpty {
                pages = match[safe: 2] ?? ""
            }
        }

        if pages.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b(?:pp?\.?|pages?)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?|e\d+)\b"#
           ) {
            pages = match[safe: 1] ?? ""
        }

        if pages.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b(?:页码|页)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?\s*[-–—]\s*[A-Za-z]?\d+[A-Za-z]?)\b"#
           ) {
            pages = match[safe: 1] ?? ""
        }

        if pages.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\barticle\s+(?:number|no\.?)\s*[:：]?\s*([A-Za-z]?\d+[A-Za-z]?)\b"#
           ) {
            pages = match[safe: 1] ?? ""
        }

        if pages.isEmpty,
           let match = firstRegexGroups(
            in: normalized,
            pattern: #"(?i)\b([1-9]\d{0,2})\s+pages\b"#
           ) {
            pages = match[safe: 1] ?? ""
        }

        return (volume, issue, pages)
    }

    private func firstRegexGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return "" }
            return nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func frontMatterLines(from text: String, limit: Int) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(limit)

        for line in text.split(whereSeparator: \.isNewline) {
            let normalized = MetadataValueNormalizer.cleanSingleLine(String(line as Substring))
            guard !normalized.isEmpty else { continue }
            lines.append(normalized)
            if lines.count >= limit {
                break
            }
        }

        return lines
    }

    private func titleCandidates(startingAt index: Int, lines: [String]) -> [String] {
        guard lines.indices.contains(index) else { return [] }
        let line = lines[index]
        var candidates = [line]

        var combined = line
        for nextIndex in (index + 1)..<min(lines.count, index + 3) {
            let nextLine = lines[nextIndex]
            guard !isLikelyAuthorLine(nextLine),
                  !isFrontMatterStopLine(nextLine),
                  !isLikelyFrontMatterNoise(nextLine) else {
                break
            }
            combined += " \(nextLine)"
            if combined.count <= 280 {
                candidates.append(combined)
            }
        }

        return candidates
    }

    private func isPotentialTitleLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let wordCount = line.split(whereSeparator: \.isWhitespace).count
        guard line.count >= 8, line.count <= 240, wordCount >= 3 else { return false }
        if isLikelyFrontMatterNoise(line) {
            return false
        }
        if lowered.contains("abstract")
            || lowered.contains("keywords")
            || lowered.contains("publication details")
            || lowered.contains("instructions for authors")
            || lowered.contains("registered office")
            || lowered.contains("publisher:")
            || lowered.contains("downloaded by")
            || lowered.contains("article views")
            || lowered.contains("view related articles")
            || lowered.contains("see discussions")
            || lowered.contains("researchgate")
            || lowered.contains("doi")
            || lowered.contains("issn")
            || lowered.contains("isbn")
            || lowered.contains("vol.")
            || lowered.contains("volume ")
            || lowered.contains("issue ")
            || lowered.contains("copyright")
            || lowered.contains("received")
            || lowered.contains("accepted")
            || lowered.contains("available online") {
            return false
        }
        if line.contains("@") || lowered.contains("http") || lowered.contains("www.") {
            return false
        }
        return true
    }

    private func titleCandidateScore(_ line: String, lineIndex: Int) -> Int {
        let wordCount = line.split(whereSeparator: \.isWhitespace).count
        var score = 0
        score += max(0, 40 - lineIndex)
        score += min(40, wordCount * 3)
        if (40...180).contains(line.count) {
            score += 18
        }
        if line.contains(":") || line.contains("?") {
            score += 6
        }
        if line.range(of: #"[a-z]"#, options: .regularExpression) != nil,
           line.range(of: #"[A-Z]"#, options: .regularExpression) != nil {
            score += 5
        }
        if isLikelyAuthorLine(line) {
            score -= 30
        }
        return score
    }

    private func normalizedAuthors(fromFrontMatterLine line: String) -> String? {
        guard line.count >= 3, line.count <= 180 else { return nil }
        guard !isLikelyFrontMatterNoise(line) else { return nil }

        let lowered = line.lowercased()
        if lowered.contains("abstract")
            || lowered.contains("keywords")
            || lowered.contains("journal")
            || lowered.contains("doi")
            || lowered.contains("received")
            || lowered.contains("accepted")
            || lowered.contains("available online") {
            return nil
        }

        let separators = [" and ", " & ", "，", ",", ";", "；", "、", "与", "和"]
        let containsSeparator = separators.contains { lowered.contains($0.lowercased()) }
        if !containsSeparator, !looksLikePersonName(line) {
            return nil
        }

        let normalized = MetadataValueNormalizer.normalizeAuthors(line)
        guard !normalized.isEmpty else { return nil }
        let names = AuthorNameParser.parse(raw: normalized)
        guard !names.isEmpty else { return nil }
        let plausibleNames = names.filter { looksLikePersonName($0) }
        guard plausibleNames.count == names.count else { return nil }
        return plausibleNames.joined(separator: ", ")
    }

    private func isLikelyAuthorLine(_ line: String) -> Bool {
        normalizedAuthors(fromFrontMatterLine: line) != nil
    }

    private func isFrontMatterStopLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered == "abstract"
            || lowered.hasPrefix("abstract ")
            || lowered.hasPrefix("abstract:")
            || lowered.hasPrefix("keywords")
            || lowered.hasPrefix("introduction")
            || lowered.hasPrefix("1 introduction")
            || lowered.hasPrefix("摘要")
            || lowered.hasPrefix("关键词")
    }

    private func isLikelyFrontMatterNoise(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("contents lists available")
            || lowered.contains("journal homepage")
            || lowered.contains("downloaded from")
            || lowered.contains("downloaded by")
            || lowered.contains("all rights reserved")
            || lowered.contains("creative commons")
            || lowered.contains("open access")
            || lowered.contains("crossmark")
            || lowered.contains("sciencedirect")
            || lowered.contains("springerlink")
            || lowered.contains("wiley online library")
            || lowered.contains("taylor & francis")
            || lowered.contains("elsevier")
            || lowered.contains("publication details")
            || lowered.contains("instructions for authors")
            || lowered.contains("registered office")
            || lowered.contains("cookie policy")
            || lowered.contains("terms and conditions")
            || lowered.contains("researchgate")
            || lowered.contains("see discussions")
            || lowered.contains("article views")
            || lowered.contains("view related articles")
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
        let now = Date()
        if let lastOpenedAt = papers[index].lastOpenedAt,
           now.timeIntervalSince(lastOpenedAt) < 1.5 {
            return
        }
        papers[index].lastOpenedAt = now
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
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
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
                .filter { fileName in
                    guard !fileName.hasPrefix(".") else { return false }
                    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                    return supportedAttachmentFileExtensions.contains(ext)
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { folderURL.appendingPathComponent($0, isDirectory: false) }
        }

        if let url = resolvedPDFURL(for: paper) {
            return [url]
        }

        return []
    }

    private func translatedPreferredPDFURL(for paper: Paper) -> URL? {
        guard settings.preferTranslatedPDF else { return nil }

        let candidates = availablePDFURLs(for: paper).filter { url in
            url.pathExtension.lowercased() == "pdf"
                && url.deletingPathExtension().lastPathComponent.hasSuffix("-dual")
                && fileManager.fileExists(atPath: url.path)
        }
        guard !candidates.isEmpty else { return nil }

        let preferredBaseNames = [
            normalizedPDFFileName(paper.preferredOpenPDFFileName),
            normalizedPDFFileName(paper.storedPDFFileName),
            normalizedPDFFileName(paper.originalPDFFileName)
        ]
        .compactMap { $0 }
        .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }

        for baseName in preferredBaseNames {
            let expected = "\(baseName)-dual.pdf"
            if let match = candidates.first(where: { $0.lastPathComponent == expected }) {
                return match
            }
        }

        return candidates.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }.first
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
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if !supportedImageExtensions.contains(fileExtension) {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Array where Element == String {
    func uniquedAndSorted() -> [String] {
        Array(Set(self)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
