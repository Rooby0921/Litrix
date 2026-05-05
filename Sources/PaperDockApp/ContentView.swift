import AppKit
import Darwin
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private let litrixPaperIDsUTType = UTType(exportedAs: "com.rooby.litrix.paper-ids")
private let litrixTaxonomyItemUTType = UTType(exportedAs: "com.rooby.litrix.taxonomy-item")

private let contentViewAddedTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

private enum TableRowHeightMode {
    case expanded
    case compact
}

private enum CenterDropPromptKind {
    case externalImport
    case litrixPaper
}

private enum TranslationTaskPhase: Hashable {
    case queued
    case running
    case completed
    case failed
}

private struct TranslationStatusDisplayEntry: Identifiable, Hashable {
    var id: UUID { paperID }
    var paperID: UUID
    var title: String
    var phase: TranslationTaskPhase
    var progress: Double
    var message: String?
}

private enum TaxonomyCreationRelation: Hashable {
    case root
    case parent
    case sibling
    case child
}

private struct TaxonomyCreationContext: Identifiable, Hashable {
    var id = UUID()
    var kind: TaxonomyKind
    var relation: TaxonomyCreationRelation
    var referencePath: String?
}

private struct TaxonomyEditTarget: Identifiable, Hashable {
    var kind: TaxonomyKind
    var path: String

    var id: String {
        "\(kind.rawValue):\(path)"
    }
}

private enum TaxonomyDropPlacement: Hashable {
    case sibling
    case child
}

private struct TaxonomyDropTarget: Hashable {
    var kind: TaxonomyKind
    var path: String
    var placement: TaxonomyDropPlacement
}

private enum SidebarSectionKind: Hashable {
    case collections
    case tags
}

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspace: WorkspaceState

    @State private var sidebarSelection: SidebarSelection = .library(.all)
    @State private var selectedPaperID: UUID?
    @State private var selectedPaperIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var isSearchInProgress = false
    @State private var activeSearchProgressToken: UUID?
    @State private var toolbarSearchField: AdvancedSearchField?
    @State private var isPDFImporterPresented = false
    @State private var isBibTeXImporterPresented = false
    @State private var isLitrixImporterPresented = false
    @State private var isDOIImportSheetPresented = false
    @State private var isImportPopoverPresented = false
    @State private var isExportPopoverPresented = false
    @State private var doiImportDraft = ""
    @State private var isDOIImportAvailable = true
    @State private var taxonomyDraftName = ""
    @State private var isCreatingCollectionInline = false
    @State private var alertMessage: String?
    @State private var metadataReturnedContentPrompt: MetadataReturnedContentPromptState?
    @State private var customRefreshSource: MetadataRefreshSource = .api
    @State private var updatingPaperIDs: Set<UUID> = []
    @State private var metadataRefreshQueue: [MetadataRefreshQueueItem] = []
    @State private var activeMetadataRefreshItem: MetadataRefreshQueueItem?
    @State private var metadataRefreshWorkerTask: Task<Void, Never>?
    @State private var metadataPlannedTasks: [TaskStatusEntry] = []
    @State private var metadataCompletedTasks: [TaskStatusEntry] = []
    @State private var translationPlannedTasks: [TaskStatusEntry] = []
    @State private var translationQueuedTasks: [TaskStatusEntry] = []
    @State private var translationCompletedTasks: [TaskStatusEntry] = []
    @State private var translationFailedTasks: [TaskStatusEntry] = []
    @State private var translationQueue: [PDF2ZHTranslationJob] = []
    @State private var activeTranslationJobs: [UUID: PDF2ZHTranslationJob] = [:]
    @State private var translationJobTasks: [UUID: Task<Void, Never>] = [:]
    @State private var activeTranslationProcesses: [UUID: Process] = [:]
    @State private var translationProgressByPaperID: [UUID: Double] = [:]
    @State private var isTranslationQueuePaused = false
    @State private var isAPIToolPopoverPresented = false
    @State private var isCheckingAPIConnectionFromTool = false
    @State private var apiToolKeyDraft = ""
    @State private var apiToolEndpointDraft = ""
    @State private var apiToolModelDraft = ""
    @State private var apiToolStatusText = ""
    @State private var apiToolConnectionResult = ""
    @State private var isPDFImportInProgress = false
    @State private var isPDFImportProgressVisible = false
    @State private var pdfImportTask: Task<Void, Never>?
    @State private var pendingDocumentImportURLs: [URL] = []
    @State private var pendingDocumentImportURLKeys: Set<String> = []
    @State private var pdfImportProcessedCount = 0
    @State private var pdfImportTotalCount = 0
    @State private var pdfImportStatusText = ""
    @State private var localKeyMonitor: Any?
    @State private var lastCommandOnlyKeyCode: UInt16?
    @State private var lastCommandOnlyEventTimestamp: TimeInterval = 0
    @State private var didApplyInitialWindowSize = false
    @State private var configuredWindowNumber: Int?
    @State private var observedToolbarIdentifier: ObjectIdentifier?
    @State private var toolbarDisplayModeObservation: NSKeyValueObservation?
    @State private var windowSizePersistenceObservers: [NSObjectProtocol] = []
    @State private var appLifecycleObservers: [NSObjectProtocol] = []
    @State private var isAppInBackground = false
    @State private var isDropTargeted = false
    @State private var centerDropPromptKind: CenterDropPromptKind = .externalImport
    @State private var sortOrder = [KeyPathComparator(\Paper.addedAtMilliseconds, order: .reverse)]
    @State private var isInspectorPanelOnscreen = false
    @State private var rightPaneMode: RightPaneMode = .details
    @State private var centerPaneMode: CenterPaneMode = .papers
    @State private var isCenterPaneTransitioning = false
    @State private var lastInspectedPaperID: UUID?
    @State private var hoveredPreviewImageURL: URL?
    @State private var activeQuickLookURL: URL?
    @State private var imageViewZoomScale: CGFloat = 1
    @State private var imageViewGestureBaseScale: CGFloat?
    @State private var selectedImageItemID: String?
    @State private var hoveredImageMetadataItemID: String?
    @State private var pendingImageMetadataHoverTask: Task<Void, Never>?
    @State private var imageGalleryPreheatTask: Task<Void, Never>?
    @State private var pendingPaperRevealInAllPapers: UUID?
    @State private var pendingDeletePaper: Paper?
    @State private var pendingPermanentDeletePaper: Paper?
    @State private var pendingImageDelete: PendingImageDelete?
    @State private var isImageSelectionLocked = false
    @State private var isAbstractColumnSettingsPresented = false
    @State private var isTitleColumnSettingsPresented = false
    @State private var isImpactFactorColumnSettingsPresented = false
    @State private var isTimeColumnSettingsPresented = false
    @State private var isTagColumnSettingsPresented = false
    @State private var isImpactFactorProgressVisible = false
    @State private var impactFactorProgressProcessedCount = 0
    @State private var impactFactorProgressTotalCount = 0
    @State private var impactFactorProgressStatusText = ""
    @State private var abstractTranslationRequestsInFlight: Set<AbstractTranslationRequest> = []
    @State private var abstractTranslationFailedRequests: Set<AbstractTranslationRequest> = []
    @State private var abstractDisplayRevision = 0
    @State private var titleTranslationRequestsInFlight: Set<TitleTranslationRequest> = []
    @State private var titleTranslationFailedRequests: Set<TitleTranslationRequest> = []
    @State private var lastSpacePreviewToggleTime: TimeInterval = 0
    @State private var toolbarSearchFocusRequest: UUID?
    @State private var isCollectionsCollapsed = false
    @State private var isTagsCollapsed = false
    @State private var collapsedCollectionPaths: Set<String> = []
    @State private var collapsedTagPaths: Set<String> = []
    @State private var hoveredSidebarSelection: SidebarSelection?
    @State private var hoveredSidebarSection: SidebarSectionKind?
    @State private var isCustomRefreshChooserPresented = false
    @State private var customRefreshTargetPaperIDs: [UUID] = []
    @State private var taxonomyCreationContext: TaxonomyCreationContext?
    @State private var editingCollectionName: String?
    @State private var editingTagName: String?
    @State private var targetedDropCollection: String?
    @State private var targetedDropTag: String?
    @State private var draggingTaxonomyPath: String?
    @State private var draggingTaxonomyKind: TaxonomyKind?
    @State private var taxonomyDropTarget: TaxonomyDropTarget?
    @State private var inlineRenameDraft = ""
    @State private var taxonomyEditTarget: TaxonomyEditTarget?
    @State private var taxonomyEditTitle = ""
    @State private var taxonomyEditDescription = ""
    @State private var taxonomyEditIconSystemName = ""
    @State private var taxonomyEditColor = Color.secondary
    @State private var activeCellEditTarget: TableCellEditTarget?
    @State private var hoveredTableCellTarget: TableCellEditTarget?
    @State private var cellEditDraft = ""
    @State private var previousSidebarSelection: SidebarSelection = .library(.all)
    @State private var sidebarSelectionMemory: [SidebarSelection: SidebarSelectionState] = [:]
    @State private var cachedSortedPapers: [Paper] = []
    @State private var cachedSortedPaperIDs: [UUID] = []
    @State private var cachedSortedPaperIDSet: Set<UUID> = []
    @State private var cachedSortedPaperIndexByID: [UUID: Int] = [:]
    @State private var cachedAttachmentStatusByID: [UUID: Bool] = [:]
    @State private var cachedImageURLsByID: [UUID: [URL]] = [:]
    @State private var cachedImageGalleryItems: [ImageGalleryItem] = []
    @State private var cachedImageGalleryItemByID: [String: ImageGalleryItem] = [:]
    @State private var sortedResultIDCache: [SortedResultCacheKey: [UUID]] = [:]
    @State private var sortedResultCacheOrder: [SortedResultCacheKey] = []
    @State private var pendingSortedPapersRecomputeTask: Task<Void, Never>?
    @State private var paperTableRefreshNonce = UUID()
    @State private var centerSelectedRowRequestNonce = UUID()
    @State private var isFilterEnabled = false
    @State private var filterMatchMode: FilterMatchMode = .all
    @State private var filterConditions: [PaperFilterCondition] = []
    @State private var isQuickCitationOverlayPresented = false
    @State private var quickCitationQuery = ""
    @State private var quickCitationResultIDs: [UUID] = []
    @State private var quickCitationHighlightedPaperID: UUID?
    @State private var quickCitationStatusText = ""
    @FocusState private var isQuickCitationFieldFocused: Bool
    @FocusState private var isNewCollectionFieldFocused: Bool
    @FocusState private var isInlineRenameFocused: Bool
    private let inspectorPanelWidth: CGFloat = 360
    private let documentImportBatchSize = 5
    private let maximumDocumentImportCount = 10_000
    private let maximumAutomaticDOIEnrichmentCount = 80
    private let supportedDocumentImportExtensions: Set<String> = [
        "pdf",
        "doc", "docx",
        "xls", "xlsx", "csv",
        "ppt", "pptx",
        "epub", "mobi",
        "html", "htm",
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic",
        "txt", "rtf", "md"
    ]
    private let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "webp"
    ]
    private let sortedResultCacheLimit = 12

    private struct MetadataRefreshQueueItem {
        var paperID: UUID
        var mode: MetadataRefreshMode
        var fields: [MetadataField]
        var showErrorsInAlert: Bool
    }

    private struct TaskStatusEntry: Identifiable, Hashable {
        var id = UUID()
        var paperID: UUID
        var title: String
        var timestamp: Date
        var progress: Double? = nil
        var message: String? = nil
    }

    private struct MetadataReturnedContentPromptState: Identifiable, Hashable {
        var id = UUID()
        var content: String
    }

    private struct PDF2ZHTranslationJob: Identifiable, Hashable {
        var id = UUID()
        var paperID: UUID
        var title: String
        var sourceURL: URL
        var translatedURL: URL
        var outputURL: URL
        var activationLines: [String]
        var baseURL: String
        var model: String
        var enableThinking: Bool
        var enqueuedAt: Date
    }

    private struct PDF2ZHRunResult {
        var succeeded: Bool
        var message: String?
    }

    private enum PDF2ZHTimeoutReason {
        case noOutput
        case highProgressStall
        case hardLimit
    }

    private final class PDF2ZHRunMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var startedAt = Date()
        private var lastActivityAt = Date()
        private var progress: Double = 0
        private var timeoutReason: PDF2ZHTimeoutReason?

        func recordActivity(progress: Double?) {
            lock.lock()
            lastActivityAt = Date()
            if let progress {
                self.progress = max(self.progress, progress)
            }
            lock.unlock()
        }

        func stalledReason(
            now: Date,
            noOutputTimeout: TimeInterval,
            highProgressTimeout: TimeInterval,
            hardTimeout: TimeInterval
        ) -> PDF2ZHTimeoutReason? {
            lock.lock()
            defer { lock.unlock() }

            if now.timeIntervalSince(startedAt) >= hardTimeout {
                timeoutReason = .hardLimit
                return .hardLimit
            }

            let idle = now.timeIntervalSince(lastActivityAt)
            if progress >= 0.94, idle >= highProgressTimeout {
                timeoutReason = .highProgressStall
                return .highProgressStall
            }

            if idle >= noOutputTimeout {
                timeoutReason = .noOutput
                return .noOutput
            }

            return nil
        }

        func currentTimeoutReason() -> PDF2ZHTimeoutReason? {
            lock.lock()
            defer { lock.unlock() }
            return timeoutReason
        }
    }

    private struct AbstractTranslationRequest: Hashable {
        var paperID: UUID
        var language: AbstractDisplayLanguage
    }

    private struct AbstractColumnPresentation {
        var text: String
        var translationRequest: AbstractTranslationRequest?
    }

    private struct TitleTranslationRequest: Hashable {
        var paperID: UUID
        var language: AbstractDisplayLanguage
    }

    private struct TitleColumnPresentation {
        var text: String
        var isPlaceholder: Bool
        var translationRequest: TitleTranslationRequest?
    }

    private enum RightPaneMode {
        case details
        case filter
    }

    private enum MetadataRefreshSource {
        case api
        case local
        case web
    }

    private enum CenterPaneMode {
        case papers
        case images
    }

    private enum FilterMatchMode: String, CaseIterable, Identifiable {
        case any
        case all

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .any:
                return "Match Any Filter"
            case .all:
                return "Match All Filters"
            }
        }
    }

    private enum FilterOperator: String, CaseIterable, Identifiable {
        case contains
        case equals
        case beginsWith
        case notEmpty
        case isEmpty

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .contains:
                return "Contains"
            case .equals:
                return "Equals"
            case .beginsWith:
                return "Begins With"
            case .notEmpty:
                return "Is Not Empty"
            case .isEmpty:
                return "Is Empty"
            }
        }

        var needsValue: Bool {
            switch self {
            case .contains, .equals, .beginsWith:
                return true
            case .notEmpty, .isEmpty:
                return false
            }
        }
    }

    private struct PaperFilterCondition: Identifiable, Hashable {
        var id = UUID()
        var column: PaperTableColumn = .title
        var filterOperator: FilterOperator = .contains
        var value: String = ""
    }

    private struct SidebarSelectionState {
        var selectedPaperID: UUID?
        var selectedPaperIDs: Set<UUID>
    }

    private struct PendingImageDelete: Identifiable, Hashable {
        var paperID: UUID
        var fileName: String
        var url: URL

        var id: String {
            "\(paperID.uuidString)|\(fileName)"
        }
    }

    fileprivate struct ImageGalleryItem: Identifiable, Hashable {
        var id: String
        var paperID: UUID
        var imageURL: URL
        var title: String
        var authors: String
        var year: String
        var source: String
    }

    fileprivate struct ImageGalleryTileView: View {
        let item: ImageGalleryItem
        let isSelected: Bool
        let isLocked: Bool
        let language: AppLanguage
        @Binding var popoverItemID: String?
        let onTap: () -> Void
        let onDoubleTap: () -> Void
        let onViewInPapers: () -> Void
        let onViewInDetail: () -> Void
        let onDelete: () -> Void
        let onHover: (Bool) -> Void

        @State private var isHovered = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailImageView(
                    url: item.imageURL,
                    maxPixel: 528,
                    placeholderOpacity: 0.12,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(item.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { onTap() }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded(onDoubleTap)
            )
            .contextMenu {
                Button(language == .english ? "Show in Item Page" : "在条目页显示") {
                    onViewInPapers()
                }
                Button(language == .english ? "View in Detail" : "在详情页中查看") {
                    onViewInDetail()
                }
                Divider()
                Button(language == .english ? "Delete" : "删除", role: .destructive) {
                    onDelete()
                }
            }
            .onHover { hovering in
                isHovered = hovering
                onHover(hovering)
            }
            .popover(
                isPresented: Binding(
                    get: { popoverItemID == item.id },
                    set: { isPresented in
                        if !isPresented, popoverItemID == item.id {
                            popoverItemID = nil
                        }
                    }
                ),
                arrowEdge: .trailing
            ) {
                ImageMetadataPopoverCard(item: item, language: language)
                    .padding(2)
            }
        }

        private var backgroundFillColor: Color {
            if isSelected {
                return Color.accentColor.opacity(0.16)
            }
            if isLocked && isHovered {
                return Color.secondary.opacity(0.1)
            }
            return Color(nsColor: .controlBackgroundColor).opacity(0.38)
        }

        private var borderColor: Color {
            isSelected
                ? Color(red: 50.0 / 255.0, green: 172.0 / 255.0, blue: 119.0 / 255.0).opacity(0.9)
                : Color.secondary.opacity(0.2)
        }

        private var borderWidth: CGFloat {
            isSelected ? 1.3 : 0.9
        }
    }

    fileprivate struct PaperImageThumbnailView: View {
        let item: ImageGalleryItem
        let size: CGFloat
        let maxPixel: CGFloat
        let language: AppLanguage
        let isInteractive: Bool
        let onOpen: () -> Void
        let onDelete: () -> Void
        let onHoverChanged: (Bool) -> Void

        @State private var isHovered = false

        var body: some View {
            let hoverPadding: CGFloat = 5
            ThumbnailImageView(url: item.imageURL, maxPixel: maxPixel, placeholderOpacity: 0.16)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(isInteractive && isHovered ? 1.045 : 1)
                .shadow(color: Color.black.opacity(isInteractive && isHovered ? 0.18 : 0), radius: isInteractive && isHovered ? 8 : 0, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(isInteractive && isHovered ? 0.28 : 0.18), lineWidth: isInteractive && isHovered ? 0.9 : 0.6)
                )
                .padding(hoverPadding)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.18, dampingFraction: 0.72), value: isHovered)
                .onHover { hovering in
                    let effectiveHovering = isInteractive && hovering
                    isHovered = effectiveHovering
                    onHoverChanged(effectiveHovering)
                }
                .contextMenu {
                    Button(language == .english ? "Open" : "查看", action: onOpen)
                    Button(language == .english ? "Delete" : "删除", role: .destructive, action: onDelete)
                }
                .onChange(of: isInteractive) { _, enabled in
                    if !enabled {
                        isHovered = false
                        onHoverChanged(false)
                    }
                }
        }
    }

    private struct SortedResultCacheKey: Hashable {
        var selection: SidebarSelection
        var searchText: String
        var searchFieldRawValue: String
        var sortSignature: String
        var filterSignature: String
        var recentReadingRange: RecentReadingRange
        var zombieThreshold: ZombiePaperThreshold
        var recentlyDeletedRetentionDays: Int
        var dataRevision: Int
    }

    private var currentNavigationTitle: String {
        sidebarSelection.displayTitle(for: settings.appLanguage)
    }

    var body: some View {
        applyLifecycleHandlers(
            to: workspaceRoot
            .background(
                WindowConfigurator { window in
                    configureWindow(window)
                }
            )
            .fileImporter(
                isPresented: $isPDFImporterPresented,
                allowedContentTypes: documentImportContentTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    importDocumentsAndExtractMetadata(urls)
                }
            }
            .fileImporter(
                isPresented: $isBibTeXImporterPresented,
                allowedContentTypes: bibTeXImportContentTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    importBibTeX(urls)
                }
            }
            .fileImporter(
                isPresented: $isLitrixImporterPresented,
                allowedContentTypes: litrixImportContentTypes,
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result,
                   let first = urls.first {
                    importLitrixArchive(from: first)
                }
            }
            .sheet(isPresented: $isDOIImportSheetPresented) {
                DOIImportSheet(
                    doi: $doiImportDraft,
                    onCancel: {
                        isDOIImportSheetPresented = false
                    },
                    onImport: {
                        importPaperViaDOI()
                    }
                )
                .presentationDetents([.height(220)])
            }
            .sheet(isPresented: $workspace.isAdvancedSearchPresented, content: advancedSearchSheet)
            .sheet(item: $taxonomyCreationContext) { context in
                TaxonomyCreationSheet(
                    kind: context.kind,
                    name: $taxonomyDraftName,
                    onSave: {
                        saveTaxonomy(context: context)
                    }
                )
                .presentationDetents([.height(220)])
            }
            .sheet(item: $taxonomyEditTarget) { target in
                TaxonomyEditSheet(
                    kind: target.kind,
                    title: $taxonomyEditTitle,
                    itemDescription: $taxonomyEditDescription,
                    iconSystemName: $taxonomyEditIconSystemName,
                    color: $taxonomyEditColor,
                    onCancel: {
                        taxonomyEditTarget = nil
                    },
                    onSave: {
                        saveTaxonomyEdit(target)
                    }
                )
                .presentationDetents([.height(430)])
            }
            .sheet(item: $activeCellEditTarget) { target in
                TableCellEditSheet(
                    title: localized(
                        chinese: "编辑\(target.column.displayName(for: settings.appLanguage))",
                        english: "Edit \(target.column.displayName)"
                    ),
                    value: $cellEditDraft,
                    isMultiline: target.column.prefersMultilineEditor,
                    onCancel: {
                        activeCellEditTarget = nil
                    },
                    onSave: {
                        saveCellEdit(target)
                    }
                )
                .presentationDetents(target.column.prefersMultilineEditor ? [.height(440)] : [.height(220)])
            }
            .sheet(isPresented: $isAbstractColumnSettingsPresented) {
                AbstractColumnSettingsSheet(
                    language: settings.appLanguage,
                    selection: $settings.abstractDisplayLanguage
                )
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $isTitleColumnSettingsPresented) {
                TitleColumnSettingsSheet(
                    language: settings.appLanguage,
                    selection: $settings.titleDisplayLanguage
                )
                .presentationDetents([.height(260)])
            }
            .sheet(isPresented: $isImpactFactorColumnSettingsPresented) {
                ImpactFactorColumnSettingsSheet(
                    language: settings.appLanguage,
                    apiKey: $settings.easyScholarAPIKey,
                    fields: $settings.easyScholarFields,
                    abbreviations: $settings.easyScholarAbbreviations,
                    colorHexes: $settings.easyScholarColorHexes
                )
                .presentationDetents([.height(440)])
            }
            .sheet(isPresented: $isTimeColumnSettingsPresented) {
                TimeColumnSettingsSheet(
                    language: settings.appLanguage,
                    dateFormat: $settings.paperTimestampDateFormat
                )
                .presentationDetents([.height(390)])
            }
            .sheet(isPresented: $isTagColumnSettingsPresented) {
                TagColumnSettingsSheet(
                    language: settings.appLanguage,
                    displayMode: $settings.tagColumnDisplayMode
                )
                .presentationDetents([.height(260)])
            }
            .sheet(item: $metadataReturnedContentPrompt) { prompt in
                MetadataReturnedContentPrompt(
                    content: prompt.content,
                    onDismiss: {
                        metadataReturnedContentPrompt = nil
                    }
                )
            }
            .alert(
                "提示",
                isPresented: alertPresented,
                actions: {
                    Button("好", role: .cancel) {}
                },
                message: {
                    Text(alertMessage ?? "")
                }
            )
            .onChange(of: settings.abstractDisplayLanguage) { _, _ in
                markAbstractDisplayNeedsRefresh()
            }
            .onChange(of: settings.titleDisplayLanguage) { _, _ in
                markTitleDisplayNeedsRefresh()
            }
            .onChange(of: settings.easyScholarColorHexes) { _, _ in
                markPaperDisplayNeedsRefresh()
            }
            .confirmationDialog(
                localized(chinese: "删除文献", english: "Delete Paper"),
                isPresented: deleteConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingDeletePaper
            ) { paper in
                Button(localized(chinese: "删除", english: "Delete"), role: .destructive) {
                    deletePaper(paper)
                }

                Button(localized(chinese: "取消", english: "Cancel"), role: .cancel) {}
            } message: { paper in
                Text(deleteConfirmationMessage(for: paper))
            }
            .alert(
                localized(chinese: "彻底删除文献", english: "Permanently Delete Paper"),
                isPresented: permanentDeleteConfirmationPresented,
                presenting: pendingPermanentDeletePaper
            ) { paper in
                Button(localized(chinese: "彻底删除", english: "Delete Permanently"), role: .destructive) {
                    permanentlyDeletePaper(paper)
                }
                Button(localized(chinese: "取消", english: "Cancel"), role: .cancel) {}
            } message: { paper in
                Text(permanentDeleteConfirmationMessage(for: paper))
            }
            .alert(
                localized(chinese: "删除图片", english: "Delete Image"),
                isPresented: imageDeleteConfirmationPresented,
                presenting: pendingImageDelete
            ) { image in
                Button(localized(chinese: "删除", english: "Delete"), role: .destructive) {
                    deleteImage(image)
                }
                Button(localized(chinese: "取消", english: "Cancel"), role: .cancel) {}
            } message: { image in
                Text(
                    localized(
                        chinese: "将永久删除图片“\(image.fileName)”。此操作不可撤销。",
                        english: "“\(image.fileName)” will be permanently deleted. This cannot be undone."
                    )
                )
            }
            .popover(isPresented: $isCustomRefreshChooserPresented, arrowEdge: .top) {
                CustomRefreshFieldChooserPopover(
                    selectedFields: Binding(
                        get: { settings.metadataCustomRefreshFields },
                        set: { settings.metadataCustomRefreshFields = $0 }
                    ),
                    language: settings.appLanguage,
                    onRun: {
                        beginCustomRefreshSelection(
                            forPaperIDs: customRefreshTargetPaperIDs,
                            source: customRefreshSource
                        )
                        isCustomRefreshChooserPresented = false
                    }
                )
            }
        )
    }

    private func applyLifecycleHandlers<Root: View>(to view: Root) -> some View {
        let withLifecycle = applyAppearDisappearHandlers(to: view)
        let withPrimaryChanges = applyPrimaryChangeHandlers(to: withLifecycle)
        let withFilterChanges = applyFilterChangeHandlers(to: withPrimaryChanges)
        return applySelectionAndFocusHandlers(to: withFilterChanges)
    }

    private func applyAppearDisappearHandlers<Root: View>(to view: Root) -> some View {
        view
            .onAppear {
                handleViewAppear()
            }
            .onDisappear {
                handleViewDisappear()
            }
    }

    private func applyPrimaryChangeHandlers<Root: View>(to view: Root) -> some View {
        view
            .onChange(of: isAPIToolPopoverPresented) { _, isPresented in
                handleAPIToolPopoverChange(isPresented: isPresented)
            }
            .onChange(of: sidebarSelection) { _, selection in
                handleSidebarSelectionChanged(selection)
            }
            .onChange(of: searchText) {
                scheduleSortedPapersRecompute(
                    delayNanoseconds: 180_000_000,
                    showSearchProgress: true
                )
            }
            .onChange(of: toolbarSearchField) {
                scheduleSortedPapersRecompute(
                    delayNanoseconds: 90_000_000,
                    showSearchProgress: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .onChange(of: sortOrder) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: store.dataRevision) {
                handleStoreDataRevisionChange()
            }
    }

    private func applyFilterChangeHandlers<Root: View>(to view: Root) -> some View {
        view
            .onChange(of: isFilterEnabled) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: filterMatchMode) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: filterConditions) {
                scheduleSortedPapersRecompute(delayNanoseconds: 90_000_000)
            }
            .onChange(of: settings.recentReadingRange) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: settings.zombiePapersThreshold) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: settings.recentlyDeletedRetentionDays) {
                store.purgeExpiredDeletedPapers()
                clearSortedResultIDCache()
                scheduleSortedPapersRecompute()
            }
    }

    private func applySelectionAndFocusHandlers<Root: View>(to view: Root) -> some View {
        view
            .onChange(of: selectedPaperID) {
                handleSelectedPaperChange()
            }
            .onChange(of: selectedPaperIDs) {
                normalizeSelectedPaperSelection()
            }
            .onChange(of: workspace.searchFocusNonce) {
                revealSearchFieldAndFocus()
            }
            .onChange(of: workspace.noteEditorRequestNonce) {
                openNoteEditorWindow()
            }
            .onChange(of: workspace.fileMenuActionNonce) {
                handleWorkspaceFileMenuAction()
            }
            .onChange(of: workspace.viewMenuActionNonce) {
                handleWorkspaceViewMenuAction()
            }
            .onChange(of: centerPaneMode) { _, mode in
                handleCenterPaneModeChange(mode)
                withAnimation(.easeIn(duration: 0.12)) { isCenterPaneTransitioning = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    withAnimation(.easeOut(duration: 0.18)) { isCenterPaneTransitioning = false }
                }
            }
            .onChange(of: settings.appLanguage) {
                reassertWindowTitle()
                rebuildImageGalleryCache(from: cachedSortedPapers, imageURLsMap: cachedImageURLsByID)
            }
    }

    private var workspaceRoot: some View {
        workspaceLayout
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar { mainToolbar }
            .overlay(alignment: .topTrailing) {
                inspectorColumn
                    .frame(width: inspectorPanelWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(x: isInspectorPanelOnscreen ? 0 : inspectorPanelWidth)
                    .opacity(isInspectorPanelOnscreen ? 1 : 0)
                    .allowsHitTesting(isInspectorPanelOnscreen)
                    .accessibilityHidden(!isInspectorPanelOnscreen)
                    .animation(inspectorSlideAnimation, value: isInspectorPanelOnscreen)
                    .zIndex(1)
            }
            .overlay {
                if isPDFImportProgressVisible {
                    PDFImportProgressOverlay(
                        processedCount: pdfImportProcessedCount,
                        totalCount: pdfImportTotalCount,
                        statusText: pdfImportStatusText
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if isImpactFactorProgressVisible {
                    PDFImportProgressOverlay(
                        processedCount: impactFactorProgressProcessedCount,
                        totalCount: impactFactorProgressTotalCount,
                        statusText: impactFactorProgressStatusText
                    )
                    .transition(.opacity)
                }
            }
            .overlay {
                if isQuickCitationOverlayPresented {
                    QuickCitationOverlay(
                        query: $quickCitationQuery,
                        highlightedPaperID: $quickCitationHighlightedPaperID,
                        isSearchFocused: $isQuickCitationFieldFocused,
                        statusText: quickCitationStatusText,
                        results: quickCitationResults,
                        onCancel: dismissQuickCitationOverlay,
                        onSubmitQuery: runQuickCitationSearch,
                        onSelectPaper: applyQuickCitation,
                        onMoveSelection: moveQuickCitationSelection(offset:)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(25)
                }
            }
            // Bottom-right task status overlay: replaces the old popover by showing
            // active metadata/translation tasks directly in the window.
            .overlay(alignment: .bottomTrailing) {
                taskStatusBarOverlay
                    .animation(.easeInOut(duration: 0.2), value: statusBarEntries.count)
            }
    }

    private var workspaceLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        } content: {
            centerPane
                .navigationTitle(currentNavigationTitle)
        } detail: {
            Color.clear
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(currentNavigationTitle)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ToolbarSearchField(
                text: $searchText,
                selectedField: $toolbarSearchField,
                placeholder: toolbarSearchPlaceholder,
                allFieldsTitle: settings.appLanguage == .english ? "All Fields" : "全部字段",
                focusRequest: toolbarSearchFocusRequest,
                isSearching: isSearchInProgress,
                language: settings.appLanguage
            )
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
            .help(settings.appLanguage == .english ? "Search" : "搜索")
            .accessibilityLabel(settings.appLanguage == .english ? "Search" : "搜索")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                centerPaneMode = centerPaneMode == .images ? .papers : .images
            } label: {
                toolbarModeToggleLabel(
                    "photo.on.rectangle.angled",
                    title: localized(chinese: "图库", english: "Gallery"),
                    isActive: centerPaneMode == .images,
                    activeColor: Color(red: 50.0 / 255.0, green: 172.0 / 255.0, blue: 119.0 / 255.0)
                )
            }
            .buttonStyle(.plain)
            .help(localized(chinese: "图片视图", english: "Image View"))
            .accessibilityLabel(localized(chinese: "图片视图", english: "Image View"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isExportPopoverPresented = false
                    isImportPopoverPresented.toggle()
                } label: {
                    toolbarIconLabel("square.and.arrow.down", title: localized(chinese: "导入", english: "Import"))
                }
                .buttonStyle(.plain)
                .help(localized(chinese: "导入", english: "Import"))
                .accessibilityLabel(localized(chinese: "导入", english: "Import"))
                .popover(isPresented: $isImportPopoverPresented, arrowEdge: .top) {
                    ImportActionsPopover(
                        language: settings.appLanguage,
                        canImportDOI: isDOIImportAvailable,
                        onImportPDF: {
                            isImportPopoverPresented = false
                            presentPDFImportPanel()
                        },
                        onImportBibTeX: {
                            isImportPopoverPresented = false
                            presentBibTeXImportPanel()
                        },
                        onImportLitrix: {
                            isImportPopoverPresented = false
                            presentLitrixImportPanel()
                        },
                        onImportDOI: {
                            isImportPopoverPresented = false
                            doiImportDraft = ""
                            isDOIImportSheetPresented = true
                        }
                    )
                    .presentationCompactAdaptation(.none)
                }

                Button {
                    isImportPopoverPresented = false
                    isExportPopoverPresented.toggle()
                } label: {
                    toolbarIconLabel("square.and.arrow.up", title: localized(chinese: "导出", english: "Export"))
                }
                .buttonStyle(.plain)
                .help(localized(chinese: "导出", english: "Export"))
                .accessibilityLabel(localized(chinese: "导出", english: "Export"))
                .popover(isPresented: $isExportPopoverPresented, arrowEdge: .top) {
                    ExportActionsPopover(
                        language: settings.appLanguage,
                        isPaperExportDisabled: exportScopePapers.isEmpty,
                        onExportBibTeX: {
                            isExportPopoverPresented = false
                            exportBibTeX(for: exportScopePapers)
                        },
                        onExportDetailed: {
                            isExportPopoverPresented = false
                            exportDetailed(for: exportScopePapers)
                        },
                        onExportAttachments: {
                            isExportPopoverPresented = false
                            exportAttachments(for: exportScopePapers)
                        },
                        onExportLitrix: {
                            isExportPopoverPresented = false
                            exportLitrixArchive()
                        }
                    )
                    .presentationCompactAdaptation(.none)
                }
        }

        ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if !isAPIToolPopoverPresented {
                        apiToolKeyDraft = settings.metadataAPIKey.isEmpty
                            ? settings.resolvedAPIKey
                            : settings.metadataAPIKey
                        apiToolEndpointDraft = settings.metadataAPIBaseURL.isEmpty
                            ? settings.resolvedAPIEndpoint.absoluteString
                            : settings.metadataAPIBaseURL
                        apiToolModelDraft = settings.metadataModel.isEmpty
                            ? settings.resolvedModel
                            : settings.metadataModel
                        apiToolStatusText = ""
                        apiToolConnectionResult = ""
                    } else {
                        persistAPIToolDraftsIfNeeded()
                    }
                    isAPIToolPopoverPresented.toggle()
                } label: {
                    toolbarIconLabel("network", title: "API")
                }
                .buttonStyle(.plain)
                .help(localized(chinese: "API链接测试", english: "API Connectivity Test"))
                .accessibilityLabel(localized(chinese: "API链接测试", english: "API Connectivity Test"))
                .popover(isPresented: $isAPIToolPopoverPresented, arrowEdge: .top) {
                    APILinkPopover(
                        endpoint: $apiToolEndpointDraft,
                        model: $apiToolModelDraft,
                        apiKey: $apiToolKeyDraft,
                        isChecking: $isCheckingAPIConnectionFromTool,
                        statusText: $apiToolStatusText,
                        resultText: $apiToolConnectionResult,
                        onCheckConnection: {
                            checkAPIConnectionFromToolbarTool(
                                apiKeyInput: apiToolKeyDraft,
                                endpointInput: apiToolEndpointDraft,
                                modelInput: apiToolModelDraft
                            )
                        }
                    )
                    .presentationCompactAdaptation(.none)
                }

        }

        ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    presentRightPane(.filter)
                } label: {
                    toolbarModeToggleLabel(
                        "line.3.horizontal.decrease.circle",
                        title: localized(chinese: "筛选", english: "Filter"),
                        isActive: isInspectorPanelOnscreen && rightPaneMode == .filter,
                        activeColor: Color(red: 0, green: 136.0 / 255.0, blue: 1.0)
                    )
                }
                .buttonStyle(.plain)
                .help(localized(chinese: "筛选", english: "Filter"))
                .accessibilityLabel(localized(chinese: "筛选", english: "Filter"))

                Button {
                    presentRightPane(.details)
                } label: {
                    toolbarModeToggleLabel(
                        "info.circle",
                        title: localized(chinese: "详情", english: "Details"),
                        isActive: isInspectorPanelOnscreen && rightPaneMode == .details,
                        activeColor: Color(red: 0, green: 136.0 / 255.0, blue: 1.0)
                    )
                }
                .buttonStyle(.plain)
                .help(localized(chinese: "详情", english: "Details"))
                .accessibilityLabel(localized(chinese: "详情", english: "Details"))
        }
    }

    private var toolbarSearchPlaceholder: String {
        if let toolbarSearchField {
            if settings.appLanguage == .english {
                return "Search \(toolbarSearchField.title)"
            }
            return "搜索\(toolbarSearchField.title(for: settings.appLanguage))"
        }
        return settings.appLanguage == .english ? "Search" : "搜索"
    }

    private struct ToolbarLiquidGlassIcon: View {
        let systemName: String
        let title: String
        let showsTitle: Bool
        var isActive = false
        var activeColor = Color(red: 0, green: 136.0 / 255.0, blue: 1.0)
        @State private var isHovered = false

        var body: some View {
            let showsBackground = isActive || isHovered
            VStack(spacing: 2) {
                ZStack {
                    if showsBackground {
                        ToolbarGlassOrb()
                        if isActive {
                            Circle()
                                .fill(activeColor)
                            Circle()
                                .fill(Color(red: 26.0 / 255.0, green: 26.0 / 255.0, blue: 26.0 / 255.0).opacity(0.45))
                        } else {
                            Circle()
                                .fill(Color.primary.opacity(0.18))
                        }
                    }
                    Image(systemName: systemName)
                        .font(.system(size: 15.5, weight: isActive ? .semibold : .regular))
                        .imageScale(.medium)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.86))
                        .frame(width: 18, height: 18, alignment: .center)
                }
                .frame(width: 30, height: 30, alignment: .center)

                if showsTitle {
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(width: 54)
                }
            }
            .frame(width: showsTitle ? 58 : 30, height: showsTitle ? 44 : 30, alignment: .center)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .accessibilityLabel(title)
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        ZStack(alignment: .topLeading) {
            InspectorNativeGlassBackground()
                .ignoresSafeArea(edges: .top)

            activeRightPane
                .id(rightPaneMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.16), value: rightPaneMode)
                .clipped()
        }
        .contentShape(Rectangle())
        .onHover { _ in }
    }

    private var inspectorSlideAnimation: Animation {
        .snappy(duration: 0.2, extraBounce: 0)
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func toolbarIconLabel(_ systemName: String, title: String) -> some View {
        ToolbarLiquidGlassIcon(
            systemName: systemName,
            title: title,
            showsTitle: !settings.toolbarIconOnly,
            isActive: false,
            activeColor: Color.accentColor
        )
    }

    @ViewBuilder
    private func toolbarModeToggleLabel(
        _ systemName: String,
        title: String,
        isActive: Bool,
        activeColor: Color
    ) -> some View {
        ToolbarLiquidGlassIcon(
            systemName: systemName,
            title: title,
            showsTitle: !settings.toolbarIconOnly,
            isActive: isActive,
            activeColor: activeColor
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletePaper != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletePaper = nil
                }
            }
        )
    }

    private var permanentDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingPermanentDeletePaper != nil },
            set: { isPresented in
                if !isPresented {
                    pendingPermanentDeletePaper = nil
                }
            }
        )
    }

    private var imageDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingImageDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImageDelete = nil
                }
            }
        )
    }

    @ViewBuilder
    private func advancedSearchSheet() -> some View {
        AdvancedSearchView(store: store, isPresented: $workspace.isAdvancedSearchPresented) { paper in
            selectSinglePaper(paper.id)
            if let resolved = store.paper(id: paper.id) {
                store.openPDF(for: resolved)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            List {
                Section {
                    ForEach(SystemLibrary.allCases, id: \.self) { item in
                        let selection = SidebarSelection.library(item)
                        SidebarItemRow(
                            title: item.displayTitle(for: settings.appLanguage),
                            count: store.count(for: .library(item)),
                            systemImage: item.icon,
                            isHovered: hoveredSidebarSelection == selection,
                            isSelected: sidebarSelection == selection
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredSidebarSelection = hovering ? selection : (hoveredSidebarSelection == selection ? nil : hoveredSidebarSelection)
                        }
                        .onTapGesture {
                            sidebarSelection = selection
                        }
                        .tag(selection)
                    }
                } header: {
                    SidebarSectionHeader(title: localized(chinese: "文库", english: "Library"))
                }

                Section {
                    if !isCollectionsCollapsed {
                        if store.collections.isEmpty {
                            SidebarPlaceholderRow(title: localized(chinese: "暂无分类", english: "No Collections"))
                        } else {
                            ForEach(visibleTaxonomyNodes(for: .collection), id: \.path) { node in
                                collectionSidebarRow(node)
                            }
                        }

                        if isCreatingCollectionInline {
                            InlineCollectionCreator(
                                name: $taxonomyDraftName,
                                isFocused: $isNewCollectionFieldFocused,
                                onSubmit: saveInlineCollection,
                                onCancel: cancelInlineCollectionCreation
                            )
                        }
                    }
                } header: {
                    SidebarCollapsibleHeader(
                        title: localized(chinese: "分类", english: "Collections"),
                        isCollapsed: isCollectionsCollapsed,
                        isHovered: hoveredSidebarSection == .collections,
                        onAdd: {
                            beginInlineCollectionCreation()
                        },
                        onToggle: {
                            withSidebarTreeAnimation {
                                isCollectionsCollapsed.toggle()
                            }
                        }
                    )
                        .onHover { hovering in
                            hoveredSidebarSection = hovering ? .collections : (hoveredSidebarSection == .collections ? nil : hoveredSidebarSection)
                        }
                        .contextMenu {
                            Button(localized(chinese: "新建分类", english: "New Collection")) {
                                beginInlineCollectionCreation()
                            }
                            Divider()
                            Button(isCollectionsCollapsed
                                ? localized(chinese: "展开", english: "Expand")
                                : localized(chinese: "折叠", english: "Collapse")) {
                                withSidebarTreeAnimation {
                                    isCollectionsCollapsed.toggle()
                                }
                            }
                        }
                }

                Section {
                    if !isTagsCollapsed {
                        if store.tags.isEmpty {
                            SidebarPlaceholderRow(title: localized(chinese: "暂无标签", english: "No Tags"))
                        } else {
                            ForEach(visibleTaxonomyNodes(for: .tag), id: \.path) { node in
                                tagSidebarRow(node)
                            }
                        }
                    }
                } header: {
                    SidebarCollapsibleHeader(
                        title: localized(chinese: "标签", english: "Tags"),
                        isCollapsed: isTagsCollapsed,
                        isHovered: hoveredSidebarSection == .tags,
                        onAdd: {
                            beginTaxonomyCreation(kind: .tag, relation: .root, referencePath: nil)
                        },
                        onToggle: {
                            withSidebarTreeAnimation {
                                isTagsCollapsed.toggle()
                            }
                        }
                    )
                    .onHover { hovering in
                        hoveredSidebarSection = hovering ? .tags : (hoveredSidebarSection == .tags ? nil : hoveredSidebarSection)
                    }
                    .contextMenu {
                        Button(localized(chinese: "新建标签", english: "New Tag")) {
                            beginTaxonomyCreation(kind: .tag, relation: .root, referencePath: nil)
                        }

                        Divider()

                        Button(isTagsCollapsed
                            ? localized(chinese: "展开", english: "Expand")
                            : localized(chinese: "折叠", english: "Collapse")) {
                            withSidebarTreeAnimation {
                                isTagsCollapsed.toggle()
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 30)
        }
        .background {
            SidebarLiquidGlassBackground()
                .ignoresSafeArea()
        }
    }

    private var collectionTree: [TaxonomyNode] {
        TaxonomyNode.tree(from: store.collections)
    }

    private var tagTree: [TaxonomyNode] {
        TaxonomyNode.tree(from: store.tags)
    }

    private func visibleTaxonomyNodes(for kind: TaxonomyKind) -> [TaxonomyNode] {
        let collapsedPaths = collapsedTaxonomyPaths(for: kind)
        let roots = kind == .collection ? collectionTree : tagTree
        var result: [TaxonomyNode] = []

        func append(_ node: TaxonomyNode) {
            result.append(node)
            guard !collapsedPaths.contains(node.path) else { return }
            node.children.forEach(append)
        }

        roots.forEach(append)
        return result
    }

    private func collapsedTaxonomyPaths(for kind: TaxonomyKind) -> Set<String> {
        kind == .collection ? collapsedCollectionPaths : collapsedTagPaths
    }

    private func isTaxonomyNodeExpanded(_ node: TaxonomyNode, kind: TaxonomyKind) -> Bool {
        !collapsedTaxonomyPaths(for: kind).contains(node.path)
    }

    private func toggleTaxonomyNode(_ node: TaxonomyNode, kind: TaxonomyKind) {
        guard node.hasChildren else { return }
        withSidebarTreeAnimation {
            if kind == .collection {
                if collapsedCollectionPaths.contains(node.path) {
                    collapsedCollectionPaths.remove(node.path)
                } else {
                    collapsedCollectionPaths.insert(node.path)
                }
            } else {
                if collapsedTagPaths.contains(node.path) {
                    collapsedTagPaths.remove(node.path)
                } else {
                    collapsedTagPaths.insert(node.path)
                }
            }
        }
    }

    private func withSidebarTreeAnimation(_ updates: () -> Void) {
        withAnimation(.easeInOut(duration: 0.22), updates)
    }

    @ViewBuilder
    private func collectionSidebarRow(_ node: TaxonomyNode) -> some View {
        let collection = node.path
        let selection = SidebarSelection.collection(collection)
        Group {
            if editingCollectionName == collection {
                InlineRenameSidebarRow(
                    systemImage: "folder",
                    indentationLevel: node.depth,
                    name: $inlineRenameDraft,
                    onSubmit: {
                        saveInlineCollectionRename(original: collection)
                    },
                    onCancel: cancelInlineRename
                )
                .focused($isInlineRenameFocused)
            } else {
                SidebarTaxonomyRow(
                    title: node.name,
                    count: taxonomyDisplayCount(for: node, kind: .collection),
                    systemImage: taxonomyIcon(for: collection, kind: .collection, hasChildren: node.hasChildren),
                    color: nil,
                    iconTint: taxonomyIconTint(for: collection, kind: .collection),
                    depth: node.depth,
                    hasChildren: node.hasChildren,
                    isExpanded: isTaxonomyNodeExpanded(node, kind: .collection),
                    isHovered: hoveredSidebarSelection == selection || taxonomyDropTarget?.kind == .collection && taxonomyDropTarget?.path == node.path,
                    isSelected: sidebarSelection == selection,
                    dropPlacement: taxonomyDropTarget?.kind == .collection && taxonomyDropTarget?.path == node.path ? taxonomyDropTarget?.placement : nil,
                    onToggle: {
                        toggleTaxonomyNode(node, kind: .collection)
                    }
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSidebarSelection = hovering ? selection : (hoveredSidebarSelection == selection ? nil : hoveredSidebarSelection)
        }
        .onTapGesture {
            guard editingCollectionName != collection else { return }
            sidebarSelection = selection
        }
        .onTapGesture(count: 2) {
            guard editingCollectionName != collection else { return }
            sidebarSelection = selection
            toggleTaxonomyNode(node, kind: .collection)
        }
        .listRowBackground(sidebarDropTargetBackground(isTargeted: targetedDropCollection == collection))
        .background(
            SidebarPaperDropReceiver(
                isTargeted: dropTargetBinding(forCollection: collection),
                onDropPaperIDs: { ids in
                    assignDroppedPaperIDs(ids, toCollection: collection)
                }
            )
        )
        .tag(selection)
        .onDrag {
            draggingTaxonomyPath = collection
            draggingTaxonomyKind = .collection
            return taxonomyDragItemProvider(kind: .collection, path: collection)
        }
        .onDrop(
            of: [litrixTaxonomyItemUTType],
            delegate: TaxonomyRowDropDelegate(
                kind: .collection,
                target: node,
                draggingPath: $draggingTaxonomyPath,
                draggingKind: $draggingTaxonomyKind,
                dropTarget: $taxonomyDropTarget,
                onMove: { source, target, placement in
                    store.moveTaxonomyItem(
                        kind: .collection,
                        sourcePath: source,
                        targetPath: target,
                        asChild: placement == .child
                    )
                    if placement == .child {
                        collapsedCollectionPaths.remove(target)
                    }
                }
            )
        )
        .contextMenu {
            taxonomyHierarchyContextMenu(kind: .collection, node: node)

            Divider()

            Button(localized(chinese: "编辑", english: "Edit")) {
                beginTaxonomyEdit(kind: .collection, path: collection)
            }

            Divider()

            Button(localized(chinese: "删除", english: "Delete"), role: .destructive) {
                if case .collection(let selectedCollection) = sidebarSelection,
                   selectedCollection == collection {
                    sidebarSelection = .library(.all)
                }
                store.deleteCollection(named: collection)
            }
        }
    }

    @ViewBuilder
    private func tagSidebarRow(_ node: TaxonomyNode) -> some View {
        let tag = node.path
        let selection = SidebarSelection.tag(tag)
        Group {
            if editingTagName == tag {
                InlineRenameSidebarRow(
                    systemImage: nil,
                    leadingDotColor: tagColor(for: tag),
                    indentationLevel: node.depth,
                    name: $inlineRenameDraft,
                    onSubmit: {
                        saveInlineTagRename(original: tag)
                    },
                    onCancel: cancelInlineRename
                )
                .focused($isInlineRenameFocused)
            } else {
                SidebarTaxonomyRow(
                    title: node.name,
                    count: taxonomyDisplayCount(for: node, kind: .tag),
                    systemImage: taxonomyIcon(for: tag, kind: .tag, hasChildren: node.hasChildren),
                    color: tagColor(for: tag),
                    iconTint: taxonomyIconTint(for: tag, kind: .tag),
                    depth: node.depth,
                    hasChildren: node.hasChildren,
                    isExpanded: isTaxonomyNodeExpanded(node, kind: .tag),
                    isHovered: hoveredSidebarSelection == selection || taxonomyDropTarget?.kind == .tag && taxonomyDropTarget?.path == node.path,
                    isSelected: sidebarSelection == selection,
                    dropPlacement: taxonomyDropTarget?.kind == .tag && taxonomyDropTarget?.path == node.path ? taxonomyDropTarget?.placement : nil,
                    onToggle: {
                        toggleTaxonomyNode(node, kind: .tag)
                    }
                )
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSidebarSelection = hovering ? selection : (hoveredSidebarSelection == selection ? nil : hoveredSidebarSelection)
        }
        .onTapGesture {
            guard editingTagName != tag else { return }
            sidebarSelection = selection
        }
        .onTapGesture(count: 2) {
            guard editingTagName != tag else { return }
            sidebarSelection = selection
            toggleTaxonomyNode(node, kind: .tag)
        }
        .listRowBackground(sidebarDropTargetBackground(isTargeted: targetedDropTag == tag))
        .background(
            SidebarPaperDropReceiver(
                isTargeted: dropTargetBinding(forTag: tag),
                onDropPaperIDs: { ids in
                    assignDroppedPaperIDs(ids, toTag: tag)
                }
            )
        )
        .tag(selection)
        .onDrag {
            draggingTaxonomyPath = tag
            draggingTaxonomyKind = .tag
            return taxonomyDragItemProvider(kind: .tag, path: tag)
        }
        .onDrop(
            of: [litrixTaxonomyItemUTType],
            delegate: TaxonomyRowDropDelegate(
                kind: .tag,
                target: node,
                draggingPath: $draggingTaxonomyPath,
                draggingKind: $draggingTaxonomyKind,
                dropTarget: $taxonomyDropTarget,
                onMove: { source, target, placement in
                    store.moveTaxonomyItem(
                        kind: .tag,
                        sourcePath: source,
                        targetPath: target,
                        asChild: placement == .child
                    )
                    if placement == .child {
                        collapsedTagPaths.remove(target)
                    }
                }
            )
        )
        .contextMenu {
            taxonomyHierarchyContextMenu(kind: .tag, node: node)

            Divider()

            Button(localized(chinese: "编辑", english: "Edit")) {
                beginTaxonomyEdit(kind: .tag, path: tag)
            }

            Menu(localized(chinese: "快捷数字", english: "Quick Number")) {
                ForEach(1...9, id: \.self) { number in
                    Button {
                        settings.assignQuickNumber(number, toTag: tag)
                    } label: {
                        HStack {
                            Text("\(number)")
                            if settings.quickNumber(forTag: tag) == number {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()
                Button(localized(chinese: "移除快捷数字", english: "Remove Quick Number")) {
                    settings.removeQuickNumber(forTag: tag)
                }
            }

            Button(localized(chinese: "颜色", english: "Color")) {
                presentTagColorPanel(for: tag)
            }

            Button(localized(chinese: "移除颜色", english: "Remove Color")) {
                store.setTagColor(hex: nil, forTag: tag)
            }

            Divider()

            Button(localized(chinese: "删除", english: "Delete"), role: .destructive) {
                if case .tag(let selectedTag) = sidebarSelection, selectedTag == tag {
                    sidebarSelection = .library(.all)
                }
                settings.removeQuickNumber(forTag: tag)
                store.deleteTag(named: tag)
            }
        }
    }

    @ViewBuilder
    private func taxonomyHierarchyContextMenu(kind: TaxonomyKind, node: TaxonomyNode) -> some View {
        Button(localized(
            chinese: kind == .collection ? "添加上级分类" : "添加上级标签",
            english: kind == .collection ? "Add Parent Collection" : "Add Parent Tag"
        )) {
            beginTaxonomyCreation(kind: kind, relation: .parent, referencePath: node.path)
        }
        .disabled(maximumDescendantDepth(of: node) >= TaxonomyHierarchy.maximumDepth)

        Button(localized(
            chinese: kind == .collection ? "添加同级分类" : "添加同级标签",
            english: kind == .collection ? "Add Sibling Collection" : "Add Sibling Tag"
        )) {
            beginTaxonomyCreation(kind: kind, relation: .sibling, referencePath: node.path)
        }

        Button(localized(
            chinese: kind == .collection ? "添加下级分类" : "添加下级标签",
            english: kind == .collection ? "Add Child Collection" : "Add Child Tag"
        )) {
            beginTaxonomyCreation(kind: kind, relation: .child, referencePath: node.path)
        }
        .disabled(node.depth + 1 >= TaxonomyHierarchy.maximumDepth)

        Divider()

        Button(localized(chinese: "折叠", english: "Collapse")) {
            withSidebarTreeAnimation {
                if kind == .collection {
                    collapsedCollectionPaths.insert(node.path)
                } else {
                    collapsedTagPaths.insert(node.path)
                }
            }
        }
        .disabled(!node.hasChildren || !isTaxonomyNodeExpanded(node, kind: kind))

        Button(localized(chinese: "展开", english: "Expand")) {
            withSidebarTreeAnimation {
                if kind == .collection {
                    collapsedCollectionPaths.remove(node.path)
                } else {
                    collapsedTagPaths.remove(node.path)
                }
            }
        }
        .disabled(!node.hasChildren || isTaxonomyNodeExpanded(node, kind: kind))
    }

    private func maximumDescendantDepth(of node: TaxonomyNode) -> Int {
        max(node.depth + 1, node.children.map(maximumDescendantDepth).max() ?? node.depth + 1)
    }

    private func taxonomyDisplayCount(for node: TaxonomyNode, kind: TaxonomyKind) -> Int {
        let ownCount = kind == .collection
            ? store.count(for: .collection(node.path))
            : store.count(for: .tag(node.path))
        return ownCount + node.children.reduce(0) { partial, child in
            partial + taxonomyDisplayCount(for: child, kind: kind)
        }
    }

    @ViewBuilder
    private func sidebarDropTargetBackground(isTargeted: Bool) -> some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
        } else {
            Color.clear
        }
    }

    private func dropTargetBinding(forCollection collection: String) -> Binding<Bool> {
        Binding(
            get: { targetedDropCollection == collection },
            set: { isTargeted in
                targetedDropCollection = isTargeted ? collection : nil
            }
        )
    }

    private func dropTargetBinding(forTag tag: String) -> Binding<Bool> {
        Binding(
            get: { targetedDropTag == tag },
            set: { isTargeted in
                targetedDropTag = isTargeted ? tag : nil
            }
        )
    }

    private func setCenterPaperDragPromptVisible(_ isVisible: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDropTargeted = isVisible
            centerDropPromptKind = isVisible ? .litrixPaper : .externalImport
        }
    }

    private var centerPane: some View {
        VStack(spacing: 0) {
            switch centerPaneMode {
            case .papers:
                papersTable
                    .transition(.opacity)
            case .images:
                imagesPane
                    .transition(.opacity)
            }
        }
        .overlay {
            if isCenterPaneTransitioning {
                CenterPaneLoadingOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(16)
                    .overlay {
                        centerDropPrompt
                    }
            }
        }
        .background(
            CenterPaneDropReceiver(
                isTargeted: $isDropTargeted,
                promptKind: $centerDropPromptKind,
                onImportExternalFiles: { urls in
                    importDocumentsAndExtractMetadata(urls, autoAssignTo: sidebarSelection)
                },
                // Allow dropping existing papers directly into a collection from the center pane.
                onDropInternalPaperIDs: { ids in
                    guard case .collection(let collection) = sidebarSelection else { return }
                    assignDroppedPaperIDs(ids, toCollection: collection)
                }
            )
        )
    }

    @ViewBuilder
    private var centerDropPrompt: some View {
        switch centerDropPromptKind {
        case .externalImport:
            Text(localized(chinese: "拖拽文献文件到这里即可导入", english: "Drop paper files here to import"))
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
        case .litrixPaper:
            VStack(alignment: .leading, spacing: 8) {
                Text(localized(chinese: "拖拽文献说明", english: "Paper Dragging"))
                    .font(.headline.weight(.semibold))
                Label(
                    localized(chinese: "拖到外部 AI，可直接就这篇文献提问", english: "Drop onto an external AI app to ask about the paper"),
                    systemImage: "sparkles"
                )
                Label(
                    localized(chinese: "拖到左侧分类或标签，可快速添加分类/标签", english: "Drop onto a sidebar collection or tag to assign it"),
                    systemImage: "tag"
                )
                Label(
                    localized(chinese: "拖到聊天、邮件等外部程序，可作为文献文件发送", english: "Drop onto chat, mail, or other apps to send the paper file"),
                    systemImage: "paperplane"
                )
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var imagesPane: some View {
        GeometryReader { geometry in
            ScrollView {
                if imageGalleryItems.isEmpty {
                    ContentUnavailableView(
                        localized(chinese: "暂无图片", english: "No Images"),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(
                            localized(
                                chinese: "当前筛选结果里还没有图片。请先在详情栏粘贴图片或导入包含图片的条目。",
                                english: "No images in the current result set yet. Paste an image in the inspector or import papers with images."
                            )
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.top, 36)
                } else {
                    // Use the live geometry width directly. That keeps the gallery compressing
                    // inside the current center pane instead of pushing the whole window wider
                    // when the sidebar is reopened while the right pane is visible.
                    let effectiveWidth = max(220, geometry.size.width - imageGalleryReservedTrailingWidth - 32)
                    let columnCount = max(1, Int((effectiveWidth + 16) / (imageTileWidth + 16)))
                    // Waterfall/masonry layout: items distribute round-robin into equal-width columns
                    // so tiles of varying height pack naturally without large gaps.
                    let columns = waterfallDistribute(items: imageGalleryItems, columnCount: columnCount)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, columnItems in
                            VStack(spacing: 16) {
                                ForEach(columnItems) { item in
                                    imageGalleryTile(for: item)
                                }
                            }
                            .frame(width: imageTileWidth, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.trailing, imageGalleryReservedTrailingWidth + 16)
                    .padding(.vertical, 14)
                }
            }
            .background(ScrollElasticityConfigurator())
            .background(Color(nsColor: .textBackgroundColor))
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let base = imageViewGestureBaseScale ?? imageViewZoomScale
                    if imageViewGestureBaseScale == nil {
                        imageViewGestureBaseScale = imageViewZoomScale
                    }
                    let next = clampedImageZoom(base * value)
                    withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                        imageViewZoomScale = next
                    }
                }
                .onEnded { _ in
                    imageViewGestureBaseScale = nil
                }
        )
    }

    private func waterfallDistribute(items: [ImageGalleryItem], columnCount: Int) -> [[ImageGalleryItem]] {
        // Round-robin distribution: item 0→col 0, item 1→col 1, item 2→col 0, etc.
        let count = max(1, columnCount)
        var columns = Array(repeating: [ImageGalleryItem](), count: count)
        for (i, item) in items.enumerated() {
            columns[i % count].append(item)
        }
        return columns
    }

    private var papersTable: some View {
        let sortState = paperTableSortState
        return PaperTableView(
            papers: sortedPapers,
            language: settings.appLanguage,
            visibleColumns: visiblePaperTableColumns,
            fullColumnOrder: normalizedPaperTableColumnOrder,
            columnVisibility: paperTableColumnVisibilityMap,
            columnWidths: paperTableColumnWidthMap,
            selectedPaperID: selectedPaperID,
            selectedPaperIDs: selectedPaperIDs,
            translatingPaperIDs: Set(activeTranslationJobs.keys),
            contentRevision: tableContentRevision,
            rowHeight: effectiveDeterministicTableRowHeight,
            baseRowHeight: settings.resolvedTableRowHeight,
            maximumRowHeightMultiplier: settings.resolvedMaximumTableRowHeightMultiplier,
            centerRequestNonce: centerSelectedRowRequestNonce,
            sortColumn: sortState?.column,
            sortOrder: sortState?.order ?? .reverse,
            cellContent: { paper, column in
                paperTableCellContent(for: paper, column: column)
            },
            onSelectRows: { rowIDs, clickedRowID in
                let nextSelection = Set(rowIDs)
                let nextPrimaryID =
                    clickedRowID.flatMap { nextSelection.contains($0) ? $0 : nil }
                    ?? selectedPaperID.flatMap { nextSelection.contains($0) ? $0 : nil }
                    ?? primarySelection(from: nextSelection)
                guard selectedPaperIDs != nextSelection || selectedPaperID != nextPrimaryID else {
                    return
                }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedPaperIDs = nextSelection
                    selectedPaperID = nextPrimaryID
                }
            },
            onDoubleClickRow: { rowID in
                selectedPaperIDs = [rowID]
                selectedPaperID = rowID
                if let paper = store.paper(id: rowID) {
                    store.openPDF(for: paper)
                }
            },
            onColumnOrderChange: { newOrder in
                settings.applyPaperTableColumnOrder(newOrder)
            },
            onColumnWidthChange: { column, width in
                settings.setPaperTableColumnWidth(width, for: column)
            },
            onSetColumnVisibility: { column, isVisible in
                updateTableColumnVisibility(column, isVisible: isVisible)
            },
            onSortChange: { column, order in
                applyPaperTableSort(column, order: order)
            },
            onOpenColumnSettings: { column in
                openColumnSettings(for: column)
            },
            onInternalDragActiveChange: { isActive in
                setCenterPaperDragPromptVisible(isActive)
            },
            onHoverCellChange: { paperID, column in
                if let paperID, let column {
                    hoveredTableCellTarget = TableCellEditTarget(paperID: paperID, column: column)
                } else {
                    hoveredTableCellTarget = nil
                }
            },
            dragPayload: { paper in
                PaperDragPayload(
                    paperIDs: paperDragIDs(for: paper),
                    fileURL: store.defaultOpenPDFURL(for: paper),
                    dragDisplayName: store.defaultOpenPDFURL(for: paper)?.lastPathComponent
                )
            }
        )
        .overlay {
            if sortedPapers.isEmpty {
                ContentUnavailableView(
                    emptyPapersTitle,
                    systemImage: emptyPapersSystemImage,
                    description: Text(emptyPapersDescription)
                )
            }
        }
    }

    private var tableContentRevision: Int {
        store.dataRevision
            &+ abstractDisplayRevision
            &+ paperTableRefreshNonce.hashValue
            &+ settings.resolvedPaperTimestampDateFormat.hashValue
            &+ settings.tagColumnDisplayMode.rawValue.hashValue
            &+ settings.tableSelectionTextColorHex.hashValue
    }

    private var emptyPapersTitle: String {
        if case .library(.recentlyDeleted) = sidebarSelection {
            return localized(chinese: "最近删除为空", english: "Recently Deleted is Empty")
        }
        return localized(chinese: "还没有文献", english: "No Papers Yet")
    }

    private var emptyPapersSystemImage: String {
        if case .library(.recentlyDeleted) = sidebarSelection {
            return "trash"
        }
        return "books.vertical"
    }

    private var emptyPapersDescription: String {
        if case .library(.recentlyDeleted) = sidebarSelection {
            return localized(
                chinese: "删除的文献会在这里保留 \(settings.recentlyDeletedRetentionDays) 天。",
                english: "Deleted papers stay here for \(settings.recentlyDeletedRetentionDays) days."
            )
        }
        return localized(
            chinese: "先导入 PDF，或者直接导入当前工作区下的 /papers。",
            english: "Import a PDF, or import the /papers folder in the current workspace."
        )
    }

    private var imageGalleryItems: [ImageGalleryItem] {
        cachedImageGalleryItems
    }

    private var imageGalleryReservedTrailingWidth: CGFloat {
        isInspectorPanelOnscreen ? inspectorPanelWidth + 20 : 0
    }

    private var imageTileWidth: CGFloat {
        min(420, max(140, 220 * imageViewZoomScale))
    }

    private func clampedImageZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.62), 2.4)
    }

    private func imageGalleryTile(for item: ImageGalleryItem) -> some View {
        ImageGalleryTileView(
            item: item,
            isSelected: selectedImageItemID == item.id,
            isLocked: isImageSelectionLocked,
            language: settings.appLanguage,
            popoverItemID: $hoveredImageMetadataItemID,
            onTap: { selectImageItem(item); isImageSelectionLocked = true },
            onDoubleTap: { selectImageItem(item); isImageSelectionLocked = true; openImageInSystemApp(item.imageURL) },
            onViewInPapers: {
                revealPaperInAllPapers(item.paperID, closeImageView: true)
            },
            onViewInDetail: { rightPaneMode = .details; showRightPane() },
            onDelete: { requestDeleteImage(paperID: item.paperID, fileName: item.imageURL.lastPathComponent, url: item.imageURL) },
            onHover: { hovering in
                handleImageMetadataHover(for: item, hovering: hovering)
            }
        )
    }

    private func selectImageItem(_ item: ImageGalleryItem) {
        selectedImageItemID = item.id
        hoveredPreviewImageURL = item.imageURL
        selectedPaperID = item.paperID
        selectedPaperIDs = [item.paperID]
    }

    private func handleImageMetadataHover(for item: ImageGalleryItem, hovering: Bool) {
        pendingImageMetadataHoverTask?.cancel()
        pendingImageMetadataHoverTask = nil

        if hovering {
            hoveredPreviewImageURL = item.imageURL
            pendingImageMetadataHoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                hoveredImageMetadataItemID = item.id
            }
            return
        }

        if hoveredPreviewImageURL?.standardizedFileURL == item.imageURL.standardizedFileURL {
            hoveredPreviewImageURL = nil
        }
        if hoveredImageMetadataItemID == item.id {
            hoveredImageMetadataItemID = nil
        }
    }

    private func alignImageSelectionWithVisibleResults() {
        let visibleIDs = Set(imageGalleryItems.map(\.id))
        if let selectedImageItemID, visibleIDs.contains(selectedImageItemID) {
            return
        }
        if let first = imageGalleryItems.first {
            selectImageItem(first)
        } else {
            selectedImageItemID = nil
        }
    }

    private var selectedImagePreviewURL: URL? {
        guard let selectedImageItemID,
              let item = cachedImageGalleryItemByID[selectedImageItemID],
              FileManager.default.fileExists(atPath: item.imageURL.path) else {
            return nil
        }
        return item.imageURL
    }

    private func dismissImageGalleryInteractionState(closePreview: Bool = false) {
        pendingImageMetadataHoverTask?.cancel()
        pendingImageMetadataHoverTask = nil
        hoveredImageMetadataItemID = nil
        isImageSelectionLocked = false
        if closePreview,
           let activeQuickLookURL,
           selectedImagePreviewURL?.standardizedFileURL == activeQuickLookURL.standardizedFileURL,
           QuickLookPreviewManager.shared.isPreviewing(url: activeQuickLookURL) {
            QuickLookPreviewManager.shared.closePreview()
            self.activeQuickLookURL = nil
        }
        hoveredPreviewImageURL = nil
    }

    private func revealPaperInAllPapers(_ paperID: UUID, closeImageView: Bool) {
        pendingPaperRevealInAllPapers = paperID
        searchText = ""
        toolbarSearchField = nil
        isFilterEnabled = false
        sidebarSelectionMemory[.library(.all)] = SidebarSelectionState(
            selectedPaperID: paperID,
            selectedPaperIDs: [paperID]
        )

        if closeImageView {
            dismissImageGalleryInteractionState(closePreview: false)
            centerPaneMode = .papers
        }

        if sidebarSelection != .library(.all) {
            sidebarSelection = .library(.all)
        }

        attemptPendingPaperRevealIfPossible()
    }

    private func attemptPendingPaperRevealIfPossible() {
        guard let pendingPaperID = pendingPaperRevealInAllPapers,
              cachedSortedPaperIDSet.contains(pendingPaperID) else {
            return
        }
        selectSinglePaper(pendingPaperID)
        centerSelectedRowRequestNonce = UUID()
        pendingPaperRevealInAllPapers = nil
    }

    private func rebuildImageGalleryCache() {
        rebuildImageGalleryCache(from: cachedSortedPapers, imageURLsMap: cachedImageURLsByID)
    }

    private func rebuildImageGalleryCache(from papers: [Paper], imageURLsMap: [UUID: [URL]]) {
        var items: [ImageGalleryItem] = []
        items.reserveCapacity(papers.count)

        let unknownTitle = localized(chinese: "未命名文献", english: "Untitled Paper")
        let unknownAuthor = localized(chinese: "未知作者", english: "Unknown Author")
        let unknownJournal = localized(chinese: "未知期刊", english: "Unknown Journal")

        for paper in papers {
            let urls = imageURLsMap[paper.id] ?? (paper.imageFileNames.isEmpty ? [] : store.imageURLs(for: paper))
            guard !urls.isEmpty else { continue }
            let summary = paperMetadataSummary(
                for: paper,
                unknownTitle: unknownTitle,
                unknownAuthor: unknownAuthor,
                unknownJournal: unknownJournal
            )
            // Only raster image formats are shown in the gallery view.
            for url in urls {
                let standardized = url.standardizedFileURL
                let ext = standardized.pathExtension.lowercased()
                guard supportedImageExtensions.contains(ext) else { continue }
                items.append(
                    ImageGalleryItem(
                        id: "\(paper.id.uuidString)|\(standardized.path)",
                        paperID: paper.id,
                        imageURL: standardized,
                        title: summary.title,
                        authors: summary.authors,
                        year: summary.year,
                        source: summary.source
                    )
                )
            }
        }

        cachedImageGalleryItems = items

        var itemMap: [String: ImageGalleryItem] = [:]
        itemMap.reserveCapacity(items.count)
        for item in items {
            itemMap[item.id] = item
        }
        cachedImageGalleryItemByID = itemMap
    }

    private func paperMetadataSummary(
        for paper: Paper,
        unknownTitle: String? = nil,
        unknownAuthor: String? = nil,
        unknownJournal: String? = nil
    ) -> (title: String, authors: String, year: String, source: String) {
        let resolvedUnknownTitle = unknownTitle ?? localized(chinese: "未命名文献", english: "Untitled Paper")
        let resolvedUnknownAuthor = unknownAuthor ?? localized(chinese: "未知作者", english: "Unknown Author")
        let resolvedUnknownJournal = unknownJournal ?? localized(chinese: "未知期刊", english: "Unknown Journal")

        return (
            title: paper.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? resolvedUnknownTitle : paper.title,
            authors: paper.authors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? resolvedUnknownAuthor : paper.authors,
            year: paper.year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : paper.year,
            source: paper.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? resolvedUnknownJournal : paper.source
        )
    }

    private func paperImageMetadataItem(for paper: Paper, url: URL) -> ImageGalleryItem {
        let summary = paperMetadataSummary(for: paper)
        let standardizedURL = url.standardizedFileURL
        return ImageGalleryItem(
            id: "\(paper.id.uuidString)|\(standardizedURL.path)",
            paperID: paper.id,
            imageURL: standardizedURL,
            title: summary.title,
            authors: summary.authors,
            year: summary.year,
            source: summary.source
        )
    }

    private func preheatImageGalleryThumbnailsIfNeeded() {
        imageGalleryPreheatTask?.cancel()
        imageGalleryPreheatTask = nil
        guard centerPaneMode == .images else { return }
        guard !cachedImageGalleryItems.isEmpty else { return }
        let urls = Array(cachedImageGalleryItems.prefix(36)).map(\.imageURL)
        let maxPixel = max(420, imageTileWidth * 2.4)
        imageGalleryPreheatTask = Task(priority: .utility) {
            await ImageThumbnailPipeline.shared.prefetch(urls: urls, maxPixel: maxPixel, limit: 36)
        }
    }

    private var paperTableColumnVisibilityMap: [PaperTableColumn: Bool] {
        var visibility: [PaperTableColumn: Bool] = [:]
        for column in PaperTableColumn.allCases {
            visibility[column] = settings.paperTableColumnVisibility[column]
        }
        return visibility
    }

    private var paperTableColumnWidthMap: [PaperTableColumn: CGFloat] {
        var widths: [PaperTableColumn: CGFloat] = [:]
        for column in PaperTableColumn.allCases {
            widths[column] = settings.paperTableColumnWidth(for: column)
        }
        return widths
    }

    private func paperTableColumnWidth(_ column: PaperTableColumn) -> CGFloat {
        settings.paperTableColumnWidth(for: column)
    }

    private func updateTableColumnVisibility(_ column: PaperTableColumn, isVisible: Bool) {
        var options = settings.paperTableColumnVisibility
        options[column] = isVisible
        guard options != settings.paperTableColumnVisibility else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            settings.paperTableColumnVisibility = options
        }
    }

    private var paperTableViewIdentity: String {
        "\(paperTableVisibilitySignature)|\(paperTableRowHeightSignature)|\(workspace.tableColumnRefreshNonce.uuidString)|\(paperTableRefreshNonce.uuidString)"
    }

    private var paperTableRowHeightSignature: String {
        let multiplier = Int((settings.resolvedTableRowHeightMultiplier * 100).rounded())
        let height = Int(effectiveDeterministicTableRowHeight.rounded())
        return "\(multiplier):\(height)"
    }

    private var paperTableVisibilitySignature: String {
        PaperTableColumn.allCases.map { column in
            "\(column.rawValue):\(settings.paperTableColumnVisibility[column] ? "1" : "0")"
        }
        .joined(separator: "|")
    }

    private var normalizedPaperTableColumnOrder: [PaperTableColumn] {
        var result: [PaperTableColumn] = []
        for column in settings.paperTableColumnOrder where column != .englishTitle && !result.contains(column) {
            result.append(column)
        }
        for column in PaperTableColumn.defaultOrder where !result.contains(column) {
            result.append(column)
        }
        return result
    }

    private var visiblePaperTableColumns: [PaperTableColumn] {
        let visible = normalizedPaperTableColumnOrder.filter { settings.paperTableColumnVisibility[$0] }
        return visible.isEmpty ? [normalizedPaperTableColumnOrder.first ?? .title] : visible
    }

    private var paperTableSortState: (column: PaperTableColumn, order: SortOrder)? {
        guard let comparator = sortOrder.first,
              let column = paperTableColumn(forSortKeyPath: comparator.keyPath) else {
            return nil
        }
        return (column, comparator.order)
    }

    private func applyPaperTableSort(_ column: PaperTableColumn, order: SortOrder) {
        sortOrder = [paperTableSortComparator(for: column, order: order)]
    }

    private func paperTableColumn(forSortKeyPath keyPath: PartialKeyPath<Paper>) -> PaperTableColumn? {
        switch keyPath {
        case \Paper.title: return .title
        case \Paper.englishTitle: return .englishTitle
        case \Paper.authors: return .authors
        case \Paper.authorsEnglish: return .authorsEnglish
        case \Paper.year: return .year
        case \Paper.source: return .source
        case \Paper.addedAtMilliseconds: return .addedTime
        case \Paper.editedSortKey: return .editedTime
        case \Paper.tagsSortKey: return .tags
        case \Paper.rating: return .rating
        case \Paper.imageSortKey: return .image
        case \Paper.attachmentSortKey: return .attachmentStatus
        case \Paper.notes: return .note
        case \Paper.abstractText: return .abstractText
        case \Paper.chineseAbstract: return .chineseAbstract
        case \Paper.rqs: return .rqs
        case \Paper.conclusion: return .conclusion
        case \Paper.results: return .results
        case \Paper.category: return .category
        case \Paper.impactFactor: return .impactFactor
        case \Paper.samples: return .samples
        case \Paper.participantType: return .participantType
        case \Paper.variables: return .variables
        case \Paper.dataCollection: return .dataCollection
        case \Paper.dataAnalysis: return .dataAnalysis
        case \Paper.methodology: return .methodology
        case \Paper.theoreticalFoundation: return .theoreticalFoundation
        case \Paper.educationalLevel: return .educationalLevel
        case \Paper.country: return .country
        case \Paper.keywords: return .keywords
        case \Paper.limitations: return .limitations
        case \Paper.webPageURL: return .webPageURL
        default: return nil
        }
    }

    private func paperTableSortComparator(
        for column: PaperTableColumn,
        order: SortOrder
    ) -> KeyPathComparator<Paper> {
        switch column {
        case .title: return KeyPathComparator(\Paper.title, order: order)
        case .englishTitle: return KeyPathComparator(\Paper.englishTitle, order: order)
        case .authors: return KeyPathComparator(\Paper.authors, order: order)
        case .authorsEnglish: return KeyPathComparator(\Paper.authorsEnglish, order: order)
        case .year: return KeyPathComparator(\Paper.year, order: order)
        case .source: return KeyPathComparator(\Paper.source, order: order)
        case .addedTime: return KeyPathComparator(\Paper.addedAtMilliseconds, order: order)
        case .editedTime: return KeyPathComparator(\Paper.editedSortKey, order: order)
        case .tags: return KeyPathComparator(\Paper.tagsSortKey, order: order)
        case .rating: return KeyPathComparator(\Paper.rating, order: order)
        case .image: return KeyPathComparator(\Paper.imageSortKey, order: order)
        case .attachmentStatus: return KeyPathComparator(\Paper.attachmentSortKey, order: order)
        case .note: return KeyPathComparator(\Paper.notes, order: order)
        case .abstractText: return KeyPathComparator(\Paper.abstractText, order: order)
        case .chineseAbstract: return KeyPathComparator(\Paper.chineseAbstract, order: order)
        case .rqs: return KeyPathComparator(\Paper.rqs, order: order)
        case .conclusion: return KeyPathComparator(\Paper.conclusion, order: order)
        case .results: return KeyPathComparator(\Paper.results, order: order)
        case .category: return KeyPathComparator(\Paper.category, order: order)
        case .impactFactor: return KeyPathComparator(\Paper.impactFactor, order: order)
        case .samples: return KeyPathComparator(\Paper.samples, order: order)
        case .participantType: return KeyPathComparator(\Paper.participantType, order: order)
        case .variables: return KeyPathComparator(\Paper.variables, order: order)
        case .dataCollection: return KeyPathComparator(\Paper.dataCollection, order: order)
        case .dataAnalysis: return KeyPathComparator(\Paper.dataAnalysis, order: order)
        case .methodology: return KeyPathComparator(\Paper.methodology, order: order)
        case .theoreticalFoundation: return KeyPathComparator(\Paper.theoreticalFoundation, order: order)
        case .educationalLevel: return KeyPathComparator(\Paper.educationalLevel, order: order)
        case .country: return KeyPathComparator(\Paper.country, order: order)
        case .keywords: return KeyPathComparator(\Paper.keywords, order: order)
        case .limitations: return KeyPathComparator(\Paper.limitations, order: order)
        case .webPageURL: return KeyPathComparator(\Paper.webPageURL, order: order)
        }
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var configuredPaperTableColumns: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumnForEach(visiblePaperTableColumns, id: \.self) { column in
            paperTableColumnContent(for: column)
        }
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private func paperTableColumnContent(for column: PaperTableColumn) -> some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        switch column {
        case .title: titleTableColumn
        case .englishTitle: englishTitleTableColumn
        case .authors: authorsTableColumn
        case .authorsEnglish: authorsEnglishTableColumn
        case .year: yearTableColumn
        case .source: sourceTableColumn
        case .addedTime: addedTimeTableColumn
        case .editedTime: editedTimeTableColumn
        case .tags: tagsTableColumn
        case .rating: ratingTableColumn
        case .image: imageTableColumn
        case .attachmentStatus: attachmentStatusTableColumn
        case .note: noteTableColumn
        case .abstractText: metadataTableColumn(.abstractText, value: \.abstractText)
        case .chineseAbstract: metadataTableColumn(.chineseAbstract, value: \.chineseAbstract)
        case .rqs: metadataTableColumn(.rqs, value: \.rqs)
        case .conclusion: metadataTableColumn(.conclusion, value: \.conclusion)
        case .results: metadataTableColumn(.results, value: \.results)
        case .category: metadataTableColumn(.category, value: \.category)
        case .impactFactor: impactFactorTableColumn
        case .samples: metadataTableColumn(.samples, value: \.samples)
        case .participantType: metadataTableColumn(.participantType, value: \.participantType)
        case .variables: metadataTableColumn(.variables, value: \.variables)
        case .dataCollection: metadataTableColumn(.dataCollection, value: \.dataCollection)
        case .dataAnalysis: metadataTableColumn(.dataAnalysis, value: \.dataAnalysis)
        case .methodology: metadataTableColumn(.methodology, value: \.methodology)
        case .theoreticalFoundation: metadataTableColumn(.theoreticalFoundation, value: \.theoreticalFoundation)
        case .educationalLevel: metadataTableColumn(.educationalLevel, value: \.educationalLevel)
        case .country: metadataTableColumn(.country, value: \.country)
        case .keywords: metadataTableColumn(.keywords, value: \.keywords)
        case .limitations: metadataTableColumn(.limitations, value: \.limitations)
        case .webPageURL: metadataTableColumn(.webPageURL, value: \.webPageURL)
        }
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var titleTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.title.displayName(for: settings.appLanguage), value: \.title) { paper in
            titleDisplayCell(for: paper)
        }
        .width(min: 0, ideal: paperTableColumnWidth(.title), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var authorsTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.authors.displayName(for: settings.appLanguage), value: \.authors) { paper in
            paperCell(for: paper, column: .authors) {
                Text(paper.authors.isEmpty ? "Unknown" : paper.authors)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.authors.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.authors), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var englishTitleTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.englishTitle.displayName(for: settings.appLanguage), value: \.englishTitle) { paper in
            paperCell(for: paper, column: .englishTitle) {
                Text(paper.englishTitle.isEmpty ? "—" : paper.englishTitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.englishTitle.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.englishTitle), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var authorsEnglishTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.authorsEnglish.displayName(for: settings.appLanguage), value: \.authorsEnglish) { paper in
            paperCell(for: paper, column: .authorsEnglish) {
                Text(paper.authorsEnglish.isEmpty ? "—" : paper.authorsEnglish)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.authorsEnglish.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.authorsEnglish), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var yearTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.year.displayName(for: settings.appLanguage), value: \.year) { paper in
            paperCell(for: paper, column: .year) {
                Text(paper.year.isEmpty ? "—" : paper.year)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.year.isEmpty ? .secondary : .primary)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.year), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var sourceTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.source.displayName(for: settings.appLanguage), value: \.source) { paper in
            paperCell(for: paper, column: .source) {
                Text(paper.source.isEmpty ? "—" : paper.source)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.source.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.source), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var addedTimeTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.addedTime.displayName(for: settings.appLanguage), value: \.addedAtMilliseconds) { paper in
            paperCell(for: paper, column: .addedTime) {
                Text(formattedAddedTime(from: paper.addedAtMilliseconds))
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.addedTime), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var editedTimeTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.editedTime.displayName(for: settings.appLanguage), value: \.editedSortKey) { paper in
            paperCell(for: paper, column: .editedTime) {
                Text(formattedEditedTime(from: paper.lastEditedAtMilliseconds))
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.editedTime), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var tagsTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.tags.displayName(for: settings.appLanguage), value: \.tagsSortKey) { paper in
            paperCell(for: paper, column: .tags) {
                tagsDotCell(for: paper)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.tags), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var ratingTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.rating.displayName(for: settings.appLanguage), value: \.rating) { paper in
            paperCell(for: paper, column: .rating) {
                StarRatingBadge(rating: paper.rating)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.rating), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var imageTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.image.displayName(for: settings.appLanguage), value: \.imageSortKey) { paper in
            paperCell(for: paper, column: .image) {
                paperImageStrip(for: paper)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.image), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var noteTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.note.displayName(for: settings.appLanguage), value: \.notes) { paper in
            let text = noteCellText(for: paper)
            paperCell(for: paper, column: .note) {
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(text == "—" ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.note), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var attachmentStatusTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(localized(chinese: "附件", english: "Attachment"), value: \.attachmentSortKey) { paper in
            paperCell(for: paper, column: .attachmentStatus) {
                attachmentStatusCell(for: paper)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.attachmentStatus), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private func metadataTableColumn(
        _ column: PaperTableColumn,
        value: KeyPath<Paper, String>
    ) -> some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(column.displayName(for: settings.appLanguage), value: value) { paper in
            metadataTextCell(for: paper, value: paper[keyPath: value], isVisible: true, column: column)
        }
        .width(min: 0, ideal: paperTableColumnWidth(column), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var impactFactorTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(PaperTableColumn.impactFactor.displayName(for: settings.appLanguage), value: \.impactFactor) { paper in
            impactFactorDisplayCell(for: paper)
        }
        .width(min: 0, ideal: paperTableColumnWidth(.impactFactor), max: nil)
    }

    private func paperTableCellContent(for paper: Paper, column: PaperTableColumn) -> AnyView {
        switch column {
        case .title:
            return AnyView(titleDisplayCell(for: paper))
        case .englishTitle:
            return AnyView(
                paperCell(for: paper, column: .englishTitle) {
                    Text(paper.englishTitle.isEmpty ? "—" : paper.englishTitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: paper.englishTitle.isEmpty))
                        .lineLimit(tableTextLineLimit)
                }
            )
        case .authors:
            return AnyView(
                paperCell(for: paper, column: .authors) {
                    Text(paper.authors.isEmpty ? "Unknown" : paper.authors)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: paper.authors.isEmpty))
                        .lineLimit(tableTextLineLimit)
                }
            )
        case .authorsEnglish:
            return AnyView(
                paperCell(for: paper, column: .authorsEnglish) {
                    Text(paper.authorsEnglish.isEmpty ? "—" : paper.authorsEnglish)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: paper.authorsEnglish.isEmpty))
                        .lineLimit(tableTextLineLimit)
                }
            )
        case .year:
            return AnyView(
                paperCell(for: paper, column: .year) {
                    Text(paper.year.isEmpty ? "—" : paper.year)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: paper.year.isEmpty))
                }
            )
        case .source:
            return AnyView(
                paperCell(for: paper, column: .source) {
                    Text(paper.source.isEmpty ? "—" : paper.source)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: paper.source.isEmpty))
                        .lineLimit(tableTextLineLimit)
                }
            )
        case .addedTime:
            return AnyView(
                paperCell(for: paper, column: .addedTime) {
                    Text(formattedAddedTime(from: paper.addedAtMilliseconds))
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: true))
                        .lineLimit(1)
                }
            )
        case .editedTime:
            return AnyView(
                paperCell(for: paper, column: .editedTime) {
                    Text(formattedEditedTime(from: paper.lastEditedAtMilliseconds))
                        .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: true))
                        .lineLimit(1)
                }
            )
        case .tags:
            return AnyView(
                paperCell(for: paper, column: .tags) {
                    tagsDotCell(for: paper)
                }
            )
        case .rating:
            return AnyView(
                paperCell(for: paper, column: .rating) {
                    StarRatingBadge(rating: paper.rating)
                }
            )
        case .image:
            return AnyView(
                paperCell(for: paper, column: .image) {
                    paperImageStrip(for: paper)
                }
            )
        case .attachmentStatus:
            return AnyView(
                paperCell(for: paper, column: .attachmentStatus) {
                    attachmentStatusCell(for: paper)
                }
            )
        case .note:
            let text = noteCellText(for: paper)
            return AnyView(
                paperCell(for: paper, column: .note) {
                    Text(text)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: text == "—"))
                        .lineLimit(tableTextLineLimit)
                }
            )
        case .abstractText:
            return AnyView(abstractDisplayCell(for: paper))
        case .chineseAbstract:
            return AnyView(metadataTextCell(for: paper, value: paper.chineseAbstract, isVisible: true, column: .chineseAbstract))
        case .rqs:
            return AnyView(metadataTextCell(for: paper, value: paper.rqs, isVisible: true, column: .rqs))
        case .conclusion:
            return AnyView(metadataTextCell(for: paper, value: paper.conclusion, isVisible: true, column: .conclusion))
        case .results:
            return AnyView(metadataTextCell(for: paper, value: paper.results, isVisible: true, column: .results))
        case .category:
            return AnyView(metadataTextCell(for: paper, value: paper.category, isVisible: true, column: .category))
        case .impactFactor:
            return AnyView(impactFactorDisplayCell(for: paper))
        case .samples:
            return AnyView(metadataTextCell(for: paper, value: paper.samples, isVisible: true, column: .samples))
        case .participantType:
            return AnyView(metadataTextCell(for: paper, value: paper.participantType, isVisible: true, column: .participantType))
        case .variables:
            return AnyView(metadataTextCell(for: paper, value: paper.variables, isVisible: true, column: .variables))
        case .dataCollection:
            return AnyView(metadataTextCell(for: paper, value: paper.dataCollection, isVisible: true, column: .dataCollection))
        case .dataAnalysis:
            return AnyView(metadataTextCell(for: paper, value: paper.dataAnalysis, isVisible: true, column: .dataAnalysis))
        case .methodology:
            return AnyView(metadataTextCell(for: paper, value: paper.methodology, isVisible: true, column: .methodology))
        case .theoreticalFoundation:
            return AnyView(metadataTextCell(for: paper, value: paper.theoreticalFoundation, isVisible: true, column: .theoreticalFoundation))
        case .educationalLevel:
            return AnyView(metadataTextCell(for: paper, value: paper.educationalLevel, isVisible: true, column: .educationalLevel))
        case .country:
            return AnyView(metadataTextCell(for: paper, value: paper.country, isVisible: true, column: .country))
        case .keywords:
            return AnyView(metadataTextCell(for: paper, value: paper.keywords, isVisible: true, column: .keywords))
        case .limitations:
            return AnyView(metadataTextCell(for: paper, value: paper.limitations, isVisible: true, column: .limitations))
        case .webPageURL:
            return AnyView(metadataTextCell(for: paper, value: paper.webPageURL, isVisible: true, column: .webPageURL))
        }
    }

    private var detailPane: some View {
        Group {
            if let binding = inspectorPaperBinding {
                PaperInspectorModern(
                    paper: binding,
                    metadataOrder: Binding(
                        get: { settings.inspectorMetadataOrder },
                        set: { settings.inspectorMetadataOrder = $0 }
                    ),
                    language: settings.appLanguage,
                    allCollections: store.collections,
                    allTags: store.tags,
                    tagColorHexes: store.tagColorHexes,
                    imageURLs: store.imageURLs(for: binding.wrappedValue),
                    isUpdatingMetadata: isUpdatingMetadata(for: binding.wrappedValue),
                    onRefreshAllMetadata: {
                        if let paper = inspectorPaper {
                            refreshMetadata(
                                forPaperIDs: [paper.id],
                                mode: .refreshAll,
                                customFields: nil,
                                showErrorsInAlert: true
                            )
                        }
                    },
                    onRefreshMissingMetadata: {
                        if let paper = inspectorPaper {
                            refreshMetadata(
                                forPaperIDs: [paper.id],
                                mode: .refreshMissing,
                                customFields: nil,
                                showErrorsInAlert: true
                            )
                        }
                    },
                    onCustomRefreshMetadata: {
                        if let paper = inspectorPaper {
                            openCustomRefreshFieldChooser(forPaperIDs: [paper.id])
                        }
                    },
                    onExportBibTeX: {
                        if let paper = inspectorPaper {
                            exportBibTeX(for: paper)
                        }
                    },
                    onPasteImage: {
                        guard let paper = inspectorPaper else { return }
                        Task { @MainActor in
                            let pasted = await store.addImageFromPasteboard(to: paper.id)
                            if !pasted {
                                alertMessage = "Clipboard does not contain an image."
                            } else {
                                refreshPapersImmediately([paper.id], alignSelection: false)
                                rebuildImageGalleryCache()
                            }
                        }
                    },
                    onRevealImage: { fileName in
                        if let paper = inspectorPaper {
                            store.revealImage(for: paper.id, fileName: fileName)
                        }
                    },
                    onDeleteImage: { fileName in
                        if let paper = inspectorPaper,
                           let url = store.imageURL(for: paper, fileName: fileName) {
                            requestDeleteImage(paperID: paper.id, fileName: fileName, url: url)
                        }
                    },
                    onHoverImagePreview: { url in
                        hoveredPreviewImageURL = url
                    },
                    onAssignCollection: { collection, assigned in
                        store.setCollection(collection, assigned: assigned, forPaperID: binding.wrappedValue.id)
                    },
                    onAssignTag: { tag, assigned in
                        store.setTag(tag, assigned: assigned, forPaperID: binding.wrappedValue.id)
                    }
                )
            } else {
                Color.clear
            }
        }
    }

    private var filterPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Clearance for the window toolbar (mirrors PaperInspectorModern)
                    Color.clear
                        .frame(height: 0)
                        .padding(.top, 10)

                    Toggle("Filter", isOn: $isFilterEnabled)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Match Mode")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Picker("Match Mode", selection: $filterMatchMode) {
                            ForEach(FilterMatchMode.allCases) { mode in
                                Text(filterMatchModeDisplayName(mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    ForEach($filterConditions) { $condition in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(condition.column.displayName(for: settings.appLanguage))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    removeFilterCondition(condition.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }

                            Picker("Column", selection: $condition.column) {
                                ForEach(visiblePaperTableColumns, id: \.self) { column in
                                    Text(column.displayName(for: settings.appLanguage)).tag(column)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Picker("Operator", selection: $condition.filterOperator) {
                                ForEach(FilterOperator.allCases) { op in
                                    Text(filterOperatorDisplayName(op)).tag(op)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if condition.filterOperator.needsValue {
                                TextField("Value", text: $condition.value)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Add Filter Condition") {
                        addFilterCondition()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(ScrollElasticityConfigurator())
        }
        .onAppear {
            if filterConditions.isEmpty {
                addFilterCondition()
            }
        }
    }

    @ViewBuilder
    private var activeRightPane: some View {
        switch rightPaneMode {
        case .details:
            detailPane
        case .filter:
            filterPane
        }
    }

    private var bibTeXImportContentTypes: [UTType] {
        if let bibType = UTType(filenameExtension: "bib") {
            return [bibType, .plainText, .text]
        }
        return [.plainText, .text]
    }

    private var documentImportContentTypes: [UTType] {
        var types: [UTType] = [.folder]
        for ext in supportedDocumentImportExtensions.sorted() {
            guard let type = UTType(filenameExtension: ext),
                  !types.contains(type) else {
                continue
            }
            types.append(type)
        }
        return types
    }

    private var attachmentImportContentTypes: [UTType] {
        documentImportContentTypes.filter { $0 != .folder }
    }

    private var litrixImportContentTypes: [UTType] {
        if let litrixType = UTType(filenameExtension: "litrix") {
            return [litrixType, .zip]
        }
        return [.zip, .data]
    }

    private func handleWorkspaceFileMenuAction() {
        guard let action = workspace.pendingFileMenuAction else { return }

        switch action {
        case .importPDF:
            presentPDFImportPanel()
        case .importBibTeX:
            presentBibTeXImportPanel()
        case .importLitrix:
            presentLitrixImportPanel()
        case .importDOI:
            guard isDOIImportAvailable else {
                alertMessage = localized(
                    chinese: "当前无法连接 DOI 元数据服务，请稍后再试。",
                    english: "DOI metadata service is unavailable. Try again later."
                )
                return
            }
            doiImportDraft = ""
            isDOIImportSheetPresented = true
        case .exportBibTeX:
            guard !exportScopePapers.isEmpty else {
                alertMessage = localized(chinese: "当前没有可导出的文献。", english: "No papers to export.")
                return
            }
            exportBibTeX(for: exportScopePapers)
        case .exportDetailed:
            guard !exportScopePapers.isEmpty else {
                alertMessage = localized(chinese: "当前没有可导出的文献。", english: "No papers to export.")
                return
            }
            exportDetailed(for: exportScopePapers)
        case .exportAttachments:
            guard !exportScopePapers.isEmpty else {
                alertMessage = localized(chinese: "当前没有可导出的文献。", english: "No papers to export.")
                return
            }
            exportAttachments(for: exportScopePapers)
        case .exportLitrix:
            exportLitrixArchive()
        }
    }

    private func handleWorkspaceViewMenuAction() {
        guard let action = workspace.pendingViewMenuAction else { return }

        switch action {
        case .toggleRightPane:
            toggleDetailsPaneVisibility()
        case .showFilterPane:
            presentRightPane(.filter)
        case .toggleImageView:
            centerPaneMode = centerPaneMode == .images ? .papers : .images
        case .applyExpandedRowHeight:
            applyTableRowHeightMode(.expanded)
        case .applyCompactRowHeight:
            applyTableRowHeightMode(.compact)
        }
    }

    private func applyTableRowHeightMode(_ mode: TableRowHeightMode) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            switch mode {
            case .expanded:
                settings.applyExpandedRowHeight()
            case .compact:
                settings.applyCompactRowHeight()
            }
        }

        if selectedPaperID != nil {
            centerSelectedRowRequestNonce = UUID()
        }
    }

    private func presentPDFImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = documentImportContentTypes
        panel.title = localized(chinese: "导入文献文件或文件夹", english: "Import Papers or Folders")
        panel.prompt = localized(chinese: "导入", english: "Import")
        guard panel.runModal() == .OK else { return }
        importDocumentsAndExtractMetadata(panel.urls)
    }

    private func presentAttachmentOpenPanel(for paper: Paper) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = attachmentImportContentTypes
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.title = localized(chinese: "添加附件", english: "Add Attachment")
        panel.prompt = localized(chinese: "选择附件", english: "Choose Attachment")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if store.attachFile(to: paper.id, from: url, originalFileName: url.lastPathComponent) {
            refreshPapersImmediately([paper.id], alignSelection: false)
        } else {
            alertMessage = localized(chinese: "附件添加失败。", english: "Failed to add the attachment.")
        }
    }

    private func presentAttachmentReplacementPanel(for paper: Paper) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = attachmentImportContentTypes
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.title = localized(chinese: "替换附件", english: "Replace Attachment")
        panel.prompt = localized(chinese: "替换", english: "Replace")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if store.replaceDefaultAttachment(for: paper.id, with: url, originalFileName: url.lastPathComponent) {
            refreshPapersImmediately([paper.id], alignSelection: false)
        } else {
            alertMessage = localized(chinese: "附件替换失败。", english: "Failed to replace the attachment.")
        }
    }

    private func presentBibTeXImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = bibTeXImportContentTypes
        panel.title = localized(chinese: "导入 BibTeX", english: "Import BibTeX")
        panel.prompt = localized(chinese: "导入", english: "Import")
        guard panel.runModal() == .OK else { return }
        importBibTeX(panel.urls)
    }

    private func presentLitrixImportPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = litrixImportContentTypes
        panel.title = localized(chinese: "导入 Litrix", english: "Import Litrix")
        panel.prompt = localized(chinese: "导入", english: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importLitrixArchive(from: url)
    }

    private var sortedPapers: [Paper] {
        cachedSortedPapers
    }

    private var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return store.paper(id: selectedPaperID)
    }

    private var selectedPapers: [Paper] {
        let orderedIDs = sortedVisiblePaperIDs(from: selectedPaperIDs)
        return orderedIDs.compactMap { paperID in
            guard let index = cachedSortedPaperIndexByID[paperID],
                  sortedPapers.indices.contains(index) else {
                return nil
            }
            return sortedPapers[index]
        }
    }

    private var exportScopePapers: [Paper] {
        if !selectedPapers.isEmpty {
            return selectedPapers
        }
        return sortedPapers
    }

    private var inspectorPaperID: UUID? {
        selectedPaperID ?? lastInspectedPaperID
    }

    private var inspectorPaper: Paper? {
        guard let inspectorPaperID else { return nil }
        return store.paper(id: inspectorPaperID)
    }

    private var selectedPaperBinding: Binding<Paper>? {
        guard let selectedPaperID else { return nil }
        return binding(for: selectedPaperID)
    }

    private var inspectorPaperBinding: Binding<Paper>? {
        guard let inspectorPaperID else { return nil }
        return binding(for: inspectorPaperID)
    }

    private func binding(for paperID: UUID) -> Binding<Paper>? {
        guard let paper = store.paper(id: paperID) else { return nil }
        return Binding(
            get: { store.paper(id: paperID) ?? paper },
            set: { updated in
                store.updatePaper(updated)
                if let refreshed = store.paper(id: paperID) {
                    refreshEditedPaperImmediately(refreshed)
                }
            }
        )
    }

    private func primarySelection(from ids: Set<UUID>) -> UUID? {
        if let firstVisible = sortedVisiblePaperIDs(from: ids).first {
            return firstVisible
        }
        return ids.first
    }

    private func selectSinglePaper(_ paperID: UUID?) {
        selectedPaperID = paperID
        if let paperID {
            selectedPaperIDs = [paperID]
        } else {
            selectedPaperIDs = []
        }
    }

    private func normalizeSelectedPaperSelection() {
        let normalized = selectedPaperIDs.intersection(cachedSortedPaperIDSet)
        if normalized != selectedPaperIDs {
            selectedPaperIDs = normalized
            return
        }

        if let selectedPaperID, selectedPaperIDs.contains(selectedPaperID) {
            return
        }

        selectedPaperID = primarySelection(from: selectedPaperIDs)
    }

    private func handleSelectedPaperChange() {
        workspace.setSelectedPaperID(selectedPaperID)
        if let selectedPaperID {
            lastInspectedPaperID = selectedPaperID
        }
        hoveredPreviewImageURL = nil
        hoveredImageMetadataItemID = nil
    }

    private func handleViewAppear() {
        previousSidebarSelection = sidebarSelection
        scheduleSortedPapersRecompute()
        alignSelectionWithVisibleResults()
        workspace.setSelectedPaperID(selectedPaperID)
        installLocalKeyMonitorIfNeeded()
        checkDOIImportAvailability()
        installAppLifecycleObservers()
    }

    private func handleViewDisappear() {
        rememberSidebarSelectionState(for: sidebarSelection)
        persistAPIToolDraftsIfNeeded()
        removeLocalKeyMonitor()
        removeToolbarDisplayModeObserver()
        removeWindowSizePersistenceObservers()
        removeAppLifecycleObservers()
        pdfImportTask?.cancel()
        pdfImportTask = nil
        pendingSortedPapersRecomputeTask?.cancel()
        pendingSortedPapersRecomputeTask = nil
        pendingImageMetadataHoverTask?.cancel()
        pendingImageMetadataHoverTask = nil
        imageGalleryPreheatTask?.cancel()
        imageGalleryPreheatTask = nil
        isQuickCitationOverlayPresented = false
        isQuickCitationFieldFocused = false
        activeTranslationProcesses.values.forEach { process in
            if process.isRunning {
                process.terminate()
            }
        }
        activeTranslationProcesses.removeAll()
        translationJobTasks.values.forEach { $0.cancel() }
        translationJobTasks.removeAll()
    }

    private func handleAPIToolPopoverChange(isPresented: Bool) {
        if !isPresented {
            persistAPIToolDraftsIfNeeded()
        }
    }

    private func handleStoreDataRevisionChange() {
        clearSortedResultIDCache()
        refreshVisiblePapersFromStore()
        scheduleSortedPapersRecompute(delayNanoseconds: 90_000_000)
    }

    private func refreshVisiblePapersFromStore() {
        guard !cachedSortedPapers.isEmpty else { return }
        var didChange = false
        let refreshed = cachedSortedPapers.map { paper -> Paper in
            guard let current = store.paper(id: paper.id) else { return paper }
            if current != paper {
                didChange = true
            }
            return current
        }
        if didChange {
            applySortedPaperCache(refreshed)
            paperTableRefreshNonce = UUID()
        }
    }

    private func handleSidebarSelectionChanged(_ selection: SidebarSelection) {
        rememberSidebarSelectionState(for: previousSidebarSelection)
        previousSidebarSelection = selection
        restoreSidebarSelectionState(for: selection)
        attemptPendingPaperRevealIfPossible()
        cancelInlineRename()
        reassertWindowTitle()
        scheduleSortedPapersRecompute()
    }

    private func handleCenterPaneModeChange(_ mode: CenterPaneMode) {
        // Defer state changes to the next run loop to avoid EnvironmentObject
        // assertion failures during view hierarchy transitions (StarRatingBadge
        // reading SettingsStore during layout before the environment is fully wired).
        if mode == .papers {
            DispatchQueue.main.async {
                selectedImageItemID = nil
                dismissImageGalleryInteractionState(closePreview: false)
                imageGalleryPreheatTask?.cancel()
                imageGalleryPreheatTask = nil
                clearSortedResultIDCache()
                paperTableRefreshNonce = UUID()
                scheduleSortedPapersRecompute()
                attemptPendingPaperRevealIfPossible()
            }
        } else {
            DispatchQueue.main.async {
                rebuildImageGalleryCache(from: cachedSortedPapers, imageURLsMap: cachedImageURLsByID)
                alignImageSelectionWithVisibleResults()
                preheatImageGalleryThumbnailsIfNeeded()
            }
        }
    }

    private func alignSelectionWithVisibleResults() {
        selectedPaperIDs = selectedPaperIDs.intersection(cachedSortedPaperIDSet)

        if let selectedPaperID,
           cachedSortedPaperIDSet.contains(selectedPaperID) {
            if !selectedPaperIDs.contains(selectedPaperID) {
                selectedPaperIDs.insert(selectedPaperID)
            }
            attemptPendingPaperRevealIfPossible()
            return
        }

        selectSinglePaper(sortedPapers.first?.id)
        attemptPendingPaperRevealIfPossible()
    }

    private func rememberSidebarSelectionState(for selection: SidebarSelection) {
        sidebarSelectionMemory[selection] = SidebarSelectionState(
            selectedPaperID: selectedPaperID,
            selectedPaperIDs: selectedPaperIDs
        )
    }

    private func restoreSidebarSelectionState(for selection: SidebarSelection) {
        guard let remembered = sidebarSelectionMemory[selection] else { return }
        selectedPaperID = remembered.selectedPaperID
        selectedPaperIDs = remembered.selectedPaperIDs
    }

    private func scheduleSortedPapersRecompute(
        delayNanoseconds: UInt64 = 0,
        alignSelection: Bool = true,
        showSearchProgress: Bool = false
    ) {
        // When backgrounded, use a large debounce so we don't churn CPU
        let effectiveDelay = isAppInBackground
            ? max(delayNanoseconds, 500_000_000)
            : delayNanoseconds
        let progressToken: UUID?
        if showSearchProgress {
            let token = UUID()
            activeSearchProgressToken = token
            isSearchInProgress = true
            progressToken = token
        } else {
            progressToken = nil
        }
        pendingSortedPapersRecomputeTask?.cancel()
        pendingSortedPapersRecomputeTask = Task { @MainActor in
            defer {
                if let progressToken, activeSearchProgressToken == progressToken {
                    isSearchInProgress = false
                    activeSearchProgressToken = nil
                }
            }
            if effectiveDelay > 0 {
                try? await Task.sleep(nanoseconds: effectiveDelay)
            }
            guard !Task.isCancelled else { return }
            await recomputeSortedPapers()
            if alignSelection {
                alignSelectionWithVisibleResults()
            }
            pendingSortedPapersRecomputeTask = nil
        }
    }

    private func recomputeSortedPapers() async {
        let perfStart = PerformanceMonitor.now()
        let cacheKey = makeSortedResultCacheKey()
        if let cachedIDs = sortedResultIDCache[cacheKey] {
            applySortedPaperCache(resolvePapers(from: cachedIDs))
            PerformanceMonitor.logElapsed(
                "ContentView.recomputeSortedPapers",
                from: perfStart,
                thresholdMS: 12
            ) {
                "scope=\(sidebarSelection.performanceLabel), searchLength=\(searchText.count), result=\(cachedSortedPapers.count), mode=cacheHit"
            }
            return
        }

        // Capture values needed for background filter/sort before leaving MainActor.
        let base = store.scopedPapers(for: sidebarSelection)
        let capturedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedSearchField = toolbarSearchField
        let capturedFilterEnabled = isFilterEnabled
        let capturedFilterMatchMode = filterMatchMode
        let capturedFilterConditions = filterConditions
        let capturedSortOrder = sortOrder
        let capturedSelection = sidebarSelection
        let isNaturalOrder = usesNaturalOrderForCurrentSort

        // Full-text search: collect PDF URLs before entering the detached Task.
        // PDFDocument URL initializer is not thread-safe in all code paths, so we build
        // the URL map on the main actor and only do PDFDocument(string:) off-thread.
        let capturedPDFURLMap: [UUID: URL]?
        if capturedSearchField == .fullText {
            var map: [UUID: URL] = [:]
            for paper in base {
                if let url = store.defaultOpenPDFURL(for: paper) {
                    map[paper.id] = url
                }
            }
            capturedPDFURLMap = map
        } else {
            capturedPDFURLMap = nil
        }

        // Offload text search to keep typing smooth.
        let searched = await Task.detached(priority: .userInitiated) {
            let pdfTextMap: [UUID: String]?
            if let capturedPDFURLMap {
                pdfTextMap = Self.buildPDFTextCache(paperIDToURL: capturedPDFURLMap)
            } else {
                pdfTextMap = nil
            }
            return Self.applySearchQuery(
                to: base,
                searchText: capturedSearchText,
                searchField: capturedSearchField,
                pdfTextByPaperID: pdfTextMap
            )
        }.value
        let needsAttachmentStatusSnapshot = capturedFilterEnabled
            && capturedFilterConditions.contains(where: { $0.column == .attachmentStatus })
        let attachmentStatusSnapshot: [UUID: Bool]
        if needsAttachmentStatusSnapshot {
            var snapshot: [UUID: Bool] = [:]
            snapshot.reserveCapacity(searched.count)
            for paper in searched {
                snapshot[paper.id] = cachedAttachmentStatusByID[paper.id] ?? store.hasExistingPDFAttachment(for: paper)
            }
            attachmentStatusSnapshot = snapshot
        } else {
            attachmentStatusSnapshot = [:]
        }

        let filtered = await Task.detached(priority: .userInitiated) {
            Self.applyRuleFilters(
                to: searched,
                isEnabled: capturedFilterEnabled,
                matchMode: capturedFilterMatchMode,
                conditions: capturedFilterConditions,
                attachmentStatusByPaperID: attachmentStatusSnapshot
            )
        }.value

        // Keep sort off the main thread as before.
        let (result, sortMode): ([Paper], String) = await Task.detached(priority: .userInitiated) {
            if case .library(.recentReading) = capturedSelection {
                return (filtered.sorted {
                    ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
                }, "recentReading")
            } else if case .library(.recentlyDeleted) = capturedSelection {
                return (filtered.sorted {
                    ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
                }, "recentlyDeleted")
            } else if isNaturalOrder {
                // Check if already sorted to avoid unnecessary work.
                var alreadySorted = true
                if filtered.count > 1 {
                    for i in 1..<filtered.count {
                        if filtered[i - 1].addedAtMilliseconds < filtered[i].addedAtMilliseconds {
                            alreadySorted = false
                            break
                        }
                    }
                }
                if alreadySorted {
                    return (filtered, "naturalOrder")
                }
                return (filtered.sorted(using: capturedSortOrder), "naturalOrderFallback")
            } else {
                return (filtered.sorted(using: capturedSortOrder), "custom")
            }
        }.value

        applySortedPaperCache(result)
        cacheSortedResultIDs(result.map(\.id), for: cacheKey)
        PerformanceMonitor.logElapsed(
            "ContentView.recomputeSortedPapers",
            from: perfStart,
            thresholdMS: 12
        ) {
            "scope=\(sidebarSelection.performanceLabel), searchLength=\(searchText.count), base=\(base.count), searched=\(searched.count), filtered=\(filtered.count), result=\(result.count), mode=\(sortMode)"
        }
    }

    private var usesNaturalOrderForCurrentSort: Bool {
        guard sortOrder.count == 1 else { return false }
        let comparator = sortOrder[0]
        return comparator.order == .reverse && comparator.keyPath == \Paper.addedAtMilliseconds
    }

    private func makeSortedResultCacheKey() -> SortedResultCacheKey {
        SortedResultCacheKey(
            selection: sidebarSelection,
            searchText: searchText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
            searchFieldRawValue: toolbarSearchField?.rawValue ?? "__all__",
            sortSignature: sortOrderSignature,
            filterSignature: filterSignature,
            recentReadingRange: settings.recentReadingRange,
            zombieThreshold: settings.zombiePapersThreshold,
            recentlyDeletedRetentionDays: settings.recentlyDeletedRetentionDays,
            dataRevision: store.dataRevision
        )
    }

    private var sortOrderSignature: String {
        sortOrder
            .map { comparator in
                "\(sortIdentifier(for: comparator.keyPath)):\(comparator.order == .reverse ? "desc" : "asc")"
            }
            .joined(separator: "|")
    }

    private var filterSignature: String {
        guard isFilterEnabled else { return "off" }
        let conditions = filterConditions.map { condition in
            "\(condition.column.rawValue):\(condition.filterOperator.rawValue):\(condition.value.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return "\(filterMatchMode.rawValue)|\(conditions.joined(separator: "|"))"
    }

    private func sortIdentifier(for keyPath: PartialKeyPath<Paper>) -> String {
        switch keyPath {
        case \Paper.title: return "title"
        case \Paper.englishTitle: return "englishTitle"
        case \Paper.authors: return "authors"
        case \Paper.authorsEnglish: return "authorsEnglish"
        case \Paper.year: return "year"
        case \Paper.source: return "source"
        case \Paper.addedAtMilliseconds: return "addedAt"
        case \Paper.editedSortKey: return "editedAt"
        case \Paper.tagsSortKey: return "tags"
        case \Paper.rating: return "rating"
        case \Paper.imageSortKey: return "image"
        case \Paper.attachmentSortKey: return "attachment"
        case \Paper.notes: return "note"
        case \Paper.rqs: return "rqs"
        case \Paper.conclusion: return "conclusion"
        case \Paper.results: return "results"
        case \Paper.category: return "category"
        case \Paper.impactFactor: return "impactFactor"
        case \Paper.samples: return "samples"
        case \Paper.participantType: return "participantType"
        case \Paper.variables: return "variables"
        case \Paper.dataCollection: return "dataCollection"
        case \Paper.dataAnalysis: return "dataAnalysis"
        case \Paper.methodology: return "methodology"
        case \Paper.theoreticalFoundation: return "theoreticalFoundation"
        case \Paper.educationalLevel: return "educationalLevel"
        case \Paper.country: return "country"
        case \Paper.keywords: return "keywords"
        case \Paper.limitations: return "limitations"
        case \Paper.webPageURL: return "webPageURL"
        default: return "unknown"
        }
    }

    private func cacheSortedResultIDs(_ ids: [UUID], for key: SortedResultCacheKey) {
        sortedResultIDCache[key] = ids
        sortedResultCacheOrder.removeAll { $0 == key }
        sortedResultCacheOrder.append(key)
        while sortedResultCacheOrder.count > sortedResultCacheLimit {
            let oldest = sortedResultCacheOrder.removeFirst()
            sortedResultIDCache.removeValue(forKey: oldest)
        }
    }

    private func clearSortedResultIDCache() {
        sortedResultIDCache.removeAll(keepingCapacity: true)
        sortedResultCacheOrder.removeAll(keepingCapacity: true)
    }

    private func resolvePapers(from ids: [UUID]) -> [Paper] {
        ids.compactMap { store.paper(id: $0) }
    }

    private func applySortedPaperCache(_ papers: [Paper]) {
        // Apply without animation to avoid per-row animation cost on large tables.
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            cachedSortedPapers = papers
        }
        cachedSortedPaperIDs = papers.map(\.id)
        cachedSortedPaperIDSet = Set(cachedSortedPaperIDs)
        var indexMap: [UUID: Int] = [:]
        var attachmentMap: [UUID: Bool] = [:]
        var imageURLsMap: [UUID: [URL]] = [:]
        let needsAttachmentStatusCache = visiblePaperTableColumns.contains(.attachmentStatus)
        let needsImageURLCache = visiblePaperTableColumns.contains(.image) || centerPaneMode == .images
        indexMap.reserveCapacity(cachedSortedPaperIDs.count)
        if needsAttachmentStatusCache {
            attachmentMap.reserveCapacity(cachedSortedPaperIDs.count)
        }
        if needsImageURLCache {
            imageURLsMap.reserveCapacity(cachedSortedPaperIDs.count)
        }
        for (index, id) in cachedSortedPaperIDs.enumerated() {
            indexMap[id] = index
            let paper = papers[index]
            if needsAttachmentStatusCache {
                attachmentMap[id] = store.hasExistingPDFAttachment(for: paper)
            }
            if needsImageURLCache, !paper.imageFileNames.isEmpty {
                imageURLsMap[id] = store.imageURLs(for: paper)
            }
        }
        cachedSortedPaperIndexByID = indexMap
        cachedAttachmentStatusByID = attachmentMap
        cachedImageURLsByID = imageURLsMap
        attemptPendingPaperRevealIfPossible()
        if centerPaneMode == .images {
            rebuildImageGalleryCache(from: papers, imageURLsMap: imageURLsMap)
            alignImageSelectionWithVisibleResults()
            preheatImageGalleryThumbnailsIfNeeded()
        } else {
            cachedImageGalleryItems = []
            cachedImageGalleryItemByID = [:]
        }
    }

    private func isSortedByAddedTimeDescending(_ papers: [Paper]) -> Bool {
        guard papers.count > 1 else { return true }
        for index in 1..<papers.count where papers[index - 1].addedAtMilliseconds < papers[index].addedAtMilliseconds {
            return false
        }
        return true
    }

    private func sortedVisiblePaperIDs(from candidateIDs: Set<UUID>) -> [UUID] {
        let scoped = candidateIDs.intersection(cachedSortedPaperIDSet)
        guard !scoped.isEmpty else { return [] }
        let ordered = scoped.compactMap { paperID -> (Int, UUID)? in
            guard let index = cachedSortedPaperIndexByID[paperID] else { return nil }
            return (index, paperID)
        }
        .sorted { $0.0 < $1.0 }
        return ordered.map(\.1)
    }

    nonisolated private static func applySearchQuery(
        to papers: [Paper],
        searchText: String,
        searchField: AdvancedSearchField?,
        pdfTextByPaperID: [UUID: String]? = nil
    ) -> [Paper] {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchText.isEmpty else { return papers }

        if let searchField {
            if searchField == .fullText, let pdfTextByPaperID {
                return papers.filter { paper in
                    guard (paper.storedPDFFileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false),
                          let pdfText = pdfTextByPaperID[paper.id],
                          !pdfText.isEmpty else {
                        return false
                    }
                    return textContainsQuery(normalizedSearchText, in: pdfText)
                }
            }
            return papers.filter { paper in
                textContainsQuery(normalizedSearchText, in: searchField.value(in: paper))
            }
        }

        guard let query = LibrarySearchQuery.parse(normalizedSearchText) else {
            return papers
        }

        return papers.filter { paper in
            switch query {
            case .plainText(let plainText):
                return textContainsQuery(plainText, in: paper.searchIndexBlob)
            case .citation(let citation):
                return citation.matches(paper)
            }
        }
    }

    // MARK: - Full-text search cache

    nonisolated(unsafe) private static var pdfTextCache: [UUID: String] = [:]

    /// Extract PDF text into a PaperID→text map, with a capped in-memory cache.
    /// - PDFDocument(url:).string is the only viable way to extract text on macOS.
    /// - Cache is capped at 500 papers (~200MB worst-case) and cleared when exceeded.
    /// - Uses nonisolated(unsafe) because it runs inside a detached Task; the cache
    ///   is append-only and contention is benign (duplicate work at most).
    nonisolated private static func buildPDFTextCache(paperIDToURL: [UUID: URL]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        result.reserveCapacity(paperIDToURL.count)

        for (paperID, url) in paperIDToURL {
            if let cached = pdfTextCache[paperID], !cached.isEmpty {
                result[paperID] = cached
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let document = PDFDocument(url: url) else { continue }
            guard let text = document.string, !text.isEmpty else { continue }
            pdfTextCache[paperID] = text
            result[paperID] = text
        }

        // Limit cache to prevent memory growth.
        if pdfTextCache.count > 500 {
            pdfTextCache.removeAll(keepingCapacity: true)
        }

        return result
    }

    nonisolated private static func textContainsQuery(_ query: String, in source: String) -> Bool {
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

    nonisolated private static func applyRuleFilters(
        to papers: [Paper],
        isEnabled: Bool,
        matchMode: FilterMatchMode,
        conditions: [PaperFilterCondition],
        attachmentStatusByPaperID: [UUID: Bool]
    ) -> [Paper] {
        guard isEnabled else { return papers }
        let activeConditions = conditions.filter { condition in
            condition.filterOperator.needsValue
                ? !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : true
        }
        guard !activeConditions.isEmpty else { return papers }

        return papers.filter { paper in
            switch matchMode {
            case .any:
                return activeConditions.contains { condition in
                    filterCondition(
                        condition,
                        matches: paper,
                        attachmentStatusByPaperID: attachmentStatusByPaperID
                    )
                }
            case .all:
                return activeConditions.allSatisfy { condition in
                    filterCondition(
                        condition,
                        matches: paper,
                        attachmentStatusByPaperID: attachmentStatusByPaperID
                    )
                }
            }
        }
    }

    nonisolated private static func filterCondition(
        _ condition: PaperFilterCondition,
        matches paper: Paper,
        attachmentStatusByPaperID: [UUID: Bool]
    ) -> Bool {
        let source = filterSourceValue(
            for: condition.column,
            paper: paper,
            attachmentStatusByPaperID: attachmentStatusByPaperID
        )
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch condition.filterOperator {
        case .contains:
            guard !normalizedValue.isEmpty else { return true }
            return normalizedSource.localizedCaseInsensitiveContains(normalizedValue)
        case .equals:
            guard !normalizedValue.isEmpty else { return true }
            return normalizedSource.caseInsensitiveCompare(normalizedValue) == .orderedSame
        case .beginsWith:
            guard !normalizedValue.isEmpty else { return true }
            return normalizedSource.lowercased().hasPrefix(normalizedValue.lowercased())
        case .notEmpty:
            return !normalizedSource.isEmpty
        case .isEmpty:
            return normalizedSource.isEmpty
        }
    }

    nonisolated private static func filterSourceValue(
        for column: PaperTableColumn,
        paper: Paper,
        attachmentStatusByPaperID: [UUID: Bool]
    ) -> String {
        switch column {
        case .title:
            return paper.title
        case .englishTitle:
            return paper.englishTitle
        case .authors:
            return paper.authors
        case .authorsEnglish:
            return paper.authorsEnglish
        case .year:
            return paper.year
        case .source:
            return paper.source
        case .addedTime:
            return formattedAddedTimeStatic(from: paper.addedAtMilliseconds)
        case .editedTime:
            return formattedEditedTimeStatic(from: paper.lastEditedAtMilliseconds)
        case .tags:
            return paper.tags.joined(separator: ", ")
        case .rating:
            return String(paper.rating)
        case .image:
            return paper.imageFileNames.joined(separator: ", ")
        case .attachmentStatus:
            let hasAttachment = attachmentStatusByPaperID[paper.id] ?? false
            return hasAttachment ? "Attached" : "Missing"
        case .note:
            return paper.notes
        case .abstractText:
            return paper.abstractText
        case .chineseAbstract:
            return paper.chineseAbstract
        case .rqs:
            return paper.rqs
        case .conclusion:
            return paper.conclusion
        case .results:
            return paper.results
        case .category:
            return paper.category
        case .impactFactor:
            return paper.impactFactor
        case .samples:
            return paper.samples
        case .participantType:
            return paper.participantType
        case .variables:
            return paper.variables
        case .dataCollection:
            return paper.dataCollection
        case .dataAnalysis:
            return paper.dataAnalysis
        case .methodology:
            return paper.methodology
        case .theoreticalFoundation:
            return paper.theoreticalFoundation
        case .educationalLevel:
            return paper.educationalLevel
        case .country:
            return paper.country
        case .keywords:
            return paper.keywords
        case .limitations:
            return paper.limitations
        case .webPageURL:
            return paper.webPageURL
        }
    }

    nonisolated private static func formattedAddedTimeStatic(from milliseconds: Int64) -> String {
        formattedAddedTimeStatic(from: milliseconds, dateFormat: SettingsStore.defaultPaperTimestampDateFormat)
    }

    nonisolated private static func formattedAddedTimeStatic(from milliseconds: Int64, dateFormat: String) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        let trimmed = dateFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != SettingsStore.defaultPaperTimestampDateFormat else {
            return contentViewAddedTimeFormatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = trimmed
        return formatter.string(from: date)
    }

    nonisolated private static func formattedEditedTimeStatic(from milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        return formattedAddedTimeStatic(from: milliseconds)
    }

    private func filterMatchModeDisplayName(_ mode: FilterMatchMode) -> String {
        guard settings.appLanguage == .chinese else { return mode.displayName }

        switch mode {
        case .any:
            return "匹配任一条件"
        case .all:
            return "匹配全部条件"
        }
    }

    private func filterOperatorDisplayName(_ filterOperator: FilterOperator) -> String {
        guard settings.appLanguage == .chinese else { return filterOperator.displayName }

        switch filterOperator {
        case .contains:
            return "包含"
        case .equals:
            return "等于"
        case .beginsWith:
            return "开头为"
        case .notEmpty:
            return "非空"
        case .isEmpty:
            return "为空"
        }
    }

    private func addFilterCondition() {
        let defaultColumn = visiblePaperTableColumns.first ?? .title
        filterConditions.append(
            PaperFilterCondition(
                column: defaultColumn,
                filterOperator: .contains,
                value: ""
            )
        )
    }

    private func removeFilterCondition(_ id: UUID) {
        filterConditions.removeAll { $0.id == id }
    }

    private func importDocumentsAndExtractMetadata(_ urls: [URL], autoAssignTo: SidebarSelection? = nil) {
        guard !urls.isEmpty else { return }
        guard !isPDFImportInProgress else {
            enqueuePendingDocumentImport(urls)
            return
        }

        let collected = collectImportableDocumentURLs(from: urls)
        let documentURLs = Array(collected.urls.prefix(maximumDocumentImportCount))
        guard !documentURLs.isEmpty else {
            alertMessage = localized(
                chinese: "没有找到可导入的文献文件。",
                english: "No importable paper files were found."
            )
            return
        }

        let batches = makePDFImportBatches(from: documentURLs, batchSize: documentImportBatchSize)
        guard !batches.isEmpty else { return }

        isPDFImportInProgress = true
        isPDFImportProgressVisible = documentURLs.count >= documentImportBatchSize
        pdfImportTotalCount = documentURLs.count
        pdfImportProcessedCount = 0
        pdfImportStatusText = "准备导入 \(documentURLs.count) 篇文献..."

        pdfImportTask?.cancel()
        pdfImportTask = Task { @MainActor in
            var aggregateResult = PDFImportResult.empty

            defer {
                let wasCancelled = Task.isCancelled
                isPDFImportInProgress = false
                isPDFImportProgressVisible = false
                pdfImportTotalCount = 0
                pdfImportProcessedCount = 0
                pdfImportStatusText = ""
                pdfImportTask = nil
                if !wasCancelled {
                    startPendingDocumentImportIfNeeded()
                }
            }

            for (batchIndex, batch) in batches.enumerated() {
                guard !Task.isCancelled else { return }
                pdfImportStatusText = "正在导入第 \(batchIndex + 1)/\(batches.count) 批..."
                let batchResult = store.importPDFs(from: batch, shouldPersist: false)
                mergePDFImportResult(batchResult, into: &aggregateResult)
                pdfImportProcessedCount = min(pdfImportTotalCount, pdfImportProcessedCount + batch.count)
                await Task.yield()
                try? await Task.sleep(nanoseconds: 15_000_000)
            }

            guard !Task.isCancelled else { return }

            if !aggregateResult.importedPaperIDs.isEmpty {
                store.finalizePendingPDFImportIfNeeded()
                let importedPaperIDs = aggregateResult.importedPaperIDs
                Task { @MainActor in
                    await enrichImportedCitationMetadataFromDOI(importedPaperIDs)
                }
            }

            // Auto-assign imported papers to the currently selected collection/tag
            if let autoAssignTo, !aggregateResult.importedPaperIDs.isEmpty {
                let ids = aggregateResult.importedPaperIDs
                switch autoAssignTo {
                case .collection(let name):
                    setCollection(name, assigned: true, forPaperIDs: ids)
                case .tag(let name):
                    setTag(name, assigned: true, forPaperIDs: ids)
                default:
                    break
                }
                refreshSortedPapersImmediately()
            }

            pdfImportStatusText = "正在整理导入结果..."
            scheduleSortedPapersRecompute()
            alignSelectionWithVisibleResults()

            let imported = aggregateResult.importedPaperIDs.compactMap { store.paper(id: $0) }

            var messages: [String] = []
            if collected.totalFound > maximumDocumentImportCount {
                messages.append(
                    localized(
                        chinese: "本次最多导入 \(maximumDocumentImportCount) 个文件，已跳过其余 \(collected.totalFound - maximumDocumentImportCount) 个。",
                        english: "Imported at most \(maximumDocumentImportCount) files; skipped \(collected.totalFound - maximumDocumentImportCount) extra file(s)."
                    )
                )
            }
            if !aggregateResult.duplicateTitles.isEmpty {
                let uniqueTitles = Array(NSOrderedSet(array: aggregateResult.duplicateTitles)) as? [String]
                    ?? aggregateResult.duplicateTitles
                let previewTitles = uniqueTitles.prefix(6).joined(separator: "\n")
                let suffix = uniqueTitles.count > 6 ? "\n..." : ""
                messages.append(
                    localized(
                        chinese: "已导入，但发现可能重复的文献：\n\(previewTitles)\(suffix)",
                        english: "Imported, with possible duplicate paper(s):\n\(previewTitles)\(suffix)"
                    )
                )
            }

            if !aggregateResult.failedFiles.isEmpty {
                let preview = aggregateResult.failedFiles.prefix(8).joined(separator: "、")
                let suffix = aggregateResult.failedFiles.count > 8 ? "..." : ""
                messages.append("导入失败：\(preview)\(suffix)")
            }

            if !messages.isEmpty {
                alertMessage = messages.joined(separator: "\n\n")
            } else {
                alertMessage = localized(
                    chinese: "成功导入 \(imported.count) 篇文献。",
                    english: "Imported \(imported.count) paper(s) successfully."
                )
            }
        }
    }

    private func enqueuePendingDocumentImport(_ urls: [URL]) {
        var appendedCount = 0
        for url in urls {
            let key = url.standardizedFileURL.path
            guard pendingDocumentImportURLKeys.insert(key).inserted else { continue }
            pendingDocumentImportURLs.append(url)
            appendedCount += 1
        }

        guard appendedCount > 0 else { return }

        if isPDFImportProgressVisible {
            pdfImportStatusText = "当前批次导入中，已排队 \(pendingDocumentImportURLs.count) 个文件..."
        }
    }

    private func startPendingDocumentImportIfNeeded() {
        guard !isPDFImportInProgress, !pendingDocumentImportURLs.isEmpty else { return }
        let urls = pendingDocumentImportURLs
        pendingDocumentImportURLs.removeAll(keepingCapacity: true)
        pendingDocumentImportURLKeys.removeAll(keepingCapacity: true)
        importDocumentsAndExtractMetadata(urls)
    }

    private func collectImportableDocumentURLs(from urls: [URL]) -> (urls: [URL], totalFound: Int) {
        var collected: [URL] = []
        var seen: Set<String> = []

        func appendIfImportable(_ url: URL) {
            guard isImportableDocumentURL(url) else { return }
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            collected.append(url)
        }

        for url in urls {
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }

                for case let childURL as URL in enumerator {
                    guard collected.count < maximumDocumentImportCount else {
                        if isImportableDocumentURL(childURL) {
                            let key = childURL.standardizedFileURL.path
                            _ = seen.insert(key)
                        }
                        continue
                    }

                    guard let values = try? childURL.resourceValues(forKeys: Set(keys)),
                          values.isHidden != true,
                          values.isRegularFile == true else {
                        continue
                    }
                    appendIfImportable(childURL)
                }
            } else {
                appendIfImportable(url)
            }
        }

        let sorted = collected.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        return (sorted, seen.count)
    }

    private func isImportableDocumentURL(_ url: URL) -> Bool {
        supportedDocumentImportExtensions.contains(url.pathExtension.lowercased())
    }

    private func makePDFImportBatches(from urls: [URL], batchSize: Int) -> [[URL]] {
        guard !urls.isEmpty else { return [] }
        let safeBatchSize = max(1, batchSize)
        var batches: [[URL]] = []
        batches.reserveCapacity((urls.count + safeBatchSize - 1) / safeBatchSize)

        var start = 0
        while start < urls.count {
            let end = min(start + safeBatchSize, urls.count)
            batches.append(Array(urls[start..<end]))
            start = end
        }
        return batches
    }

    private func mergePDFImportResult(_ incoming: PDFImportResult, into aggregate: inout PDFImportResult) {
        aggregate.importedPaperIDs.append(contentsOf: incoming.importedPaperIDs)
        aggregate.duplicateTitles.append(contentsOf: incoming.duplicateTitles)
        aggregate.failedFiles.append(contentsOf: incoming.failedFiles)
    }

    private func importBibTeX(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let result = store.importBibTeX(from: urls)
        scheduleSortedPapersRecompute()
        alignSelectionWithVisibleResults()

        var messages: [String] = []
        if !result.importedPaperIDs.isEmpty {
            messages.append(
                localized(
                    chinese: "成功导入 \(result.importedPaperIDs.count) 条 BibTeX 文献。",
                    english: "Imported \(result.importedPaperIDs.count) BibTeX item(s) successfully."
                )
            )
        }
        if !result.duplicateTitles.isEmpty {
            let preview = Array(NSOrderedSet(array: result.duplicateTitles)) as? [String] ?? result.duplicateTitles
            let previewText = preview.prefix(6).joined(separator: "\n")
            let suffix = preview.count > 6 ? "\n..." : ""
            messages.append(
                localized(
                    chinese: "已导入，但发现可能重复的文献：\n\(previewText)\(suffix)",
                    english: "Imported, with possible duplicate paper(s):\n\(previewText)\(suffix)"
                )
            )
        }
        if !result.failedFiles.isEmpty {
            let preview = result.failedFiles.prefix(8).joined(separator: "、")
            let suffix = result.failedFiles.count > 8 ? "..." : ""
            messages.append(
                localized(
                    chinese: "以下文件导入失败：\(preview)\(suffix)",
                    english: "Failed to import: \(preview)\(suffix)"
                )
            )
        }
        if !messages.isEmpty {
            alertMessage = messages.joined(separator: "\n\n")
        }
    }

    private func importPaperViaDOI() {
        let doi = doiImportDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doi.isEmpty else { return }
        isDOIImportSheetPresented = false

        Task {
            do {
                let paper = try await fetchPaperMetadataFromDOI(doi)
                await MainActor.run {
                    let isDuplicate = store.hasPotentialDuplicate(paper)
                    let didAdd = store.addMetadataOnlyPaper(paper)
                    scheduleSortedPapersRecompute()
                    alignSelectionWithVisibleResults()
                    if didAdd {
                        alertMessage = isDuplicate
                            ? localized(
                                chinese: "已通过 DOI 添加文献，但发现可能重复：\(normalizedTitle(paper.title))",
                                english: "Added via DOI, with a possible duplicate: \(normalizedTitle(paper.title))"
                            )
                            : localized(
                                chinese: "已通过 DOI 添加文献：\(normalizedTitle(paper.title))",
                                english: "Added paper via DOI: \(normalizedTitle(paper.title))"
                            )
                    } else {
                        alertMessage = localized(
                            chinese: "DOI 文献添加失败。",
                            english: "DOI paper import failed."
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    alertMessage = localized(
                        chinese: "DOI 导入失败：\(error.localizedDescription)",
                        english: "DOI import failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func checkDOIImportAvailability() {
        Task.detached {
            guard let url = URL(string: "https://api.crossref.org/works/10.1038%2Fnphys1170") else {
                await MainActor.run { isDOIImportAvailable = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 6
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    isDOIImportAvailable = (200...399).contains(status)
                }
            } catch {
                await MainActor.run {
                    isDOIImportAvailable = false
                }
            }
        }
    }

    private func fetchPaperMetadataFromDOI(_ doi: String) async throws -> Paper {
        try await DOIMetadataService.fetchPaper(for: doi)
    }

    private func enrichImportedCitationMetadataFromDOI(_ paperIDs: [UUID]) async {
        guard isDOIImportAvailable else { return }
        let ids = Array(paperIDs.prefix(maximumAutomaticDOIEnrichmentCount))
        guard !ids.isEmpty else { return }

        let citationFields: [MetadataField] = [
            .title, .englishTitle, .authors, .authorsEnglish, .year, .source, .doi,
            .abstractText, .chineseAbstract, .volume, .issue, .pages, .paperType
        ]

        for paperID in ids {
            guard !Task.isCancelled,
                  var paper = store.paper(id: paperID),
                  !MetadataValueNormalizer.normalizeDOI(paper.doi).isEmpty else {
                continue
            }

            do {
                let suggestion = try await DOIMetadataService.fetchSuggestion(for: paper.doi)
                applyNonEmptyMetadataSuggestion(suggestion, to: &paper, fields: citationFields, mode: .refreshAll)
                store.updatePaper(paper)
            } catch {
                continue
            }
        }
    }

    private func openQuickLook(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        QuickLookPreviewManager.shared.preview(url: url)
        activeQuickLookURL = url
    }

    private func toggleSpacePreview() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSpacePreviewToggleTime > 0.12 else { return }
        lastSpacePreviewToggleTime = now

        if let activeQuickLookURL, QuickLookPreviewManager.shared.isPreviewing(url: activeQuickLookURL) {
            QuickLookPreviewManager.shared.closePreview()
            self.activeQuickLookURL = nil
            return
        }

        if centerPaneMode == .images, let selectedImagePreviewURL {
            openQuickLook(url: selectedImagePreviewURL)
            return
        }

        if let hoveredPreviewImageURL {
            openQuickLook(url: hoveredPreviewImageURL)
            return
        }

        if let pdfURL = selectedPaperPreviewURL {
            openQuickLook(url: pdfURL)
            return
        }
    }

    private var selectedPaperPreviewURL: URL? {
        guard let selectedPaper else { return nil }
        guard let url = store.defaultOpenPDFURL(for: selectedPaper) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func openImageInSystemApp(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestDeleteImage(paperID: UUID, fileName: String, url: URL) {
        pendingImageDelete = PendingImageDelete(
            paperID: paperID,
            fileName: fileName,
            url: url
        )
    }

    private func deleteImage(_ image: PendingImageDelete) {
        if activeQuickLookURL?.standardizedFileURL == image.url.standardizedFileURL {
            QuickLookPreviewManager.shared.closePreview()
            activeQuickLookURL = nil
        }
        if hoveredPreviewImageURL?.standardizedFileURL == image.url.standardizedFileURL {
            hoveredPreviewImageURL = nil
        }

        let deleted = store.removeImage(from: image.paperID, fileName: image.fileName)
        pendingImageDelete = nil
        guard deleted else { return }

        let deletedItemID = "\(image.paperID.uuidString)|\(image.url.standardizedFileURL.path)"
        if selectedImageItemID == deletedItemID {
            selectedImageItemID = nil
        }
        refreshPapersImmediately([image.paperID], alignSelection: false)
        rebuildImageGalleryCache()
        alignImageSelectionWithVisibleResults()
    }

    private func openSelectedImageInSystemApp() {
        guard let selectedImagePreviewURL else { return }
        openImageInSystemApp(selectedImagePreviewURL)
    }

    private func configureWindow(_ window: NSWindow) {
        applyWindowTitle(to: window)

        let isNewWindow = configuredWindowNumber != window.windowNumber
        if isNewWindow {
            configuredWindowNumber = window.windowNumber
            // Keep native system default window sizing behavior:
            // do not apply custom initial size/min size rules and do not persist size.
            // didApplyInitialWindowSize = false
            // removeWindowSizePersistenceObservers()

            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .white
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            if #available(macOS 11.0, *) {
                window.titlebarSeparatorStyle = .none
            }
            if let toolbar = window.toolbar {
                configureToolbar(toolbar)
            }
            installToolbarGlassBackdrop(in: window)
            // installWindowSizePersistenceObserversIfNeeded(window: window)
        }

        if let toolbar = window.toolbar {
            configureToolbar(toolbar)
        }
        installToolbarGlassBackdrop(in: window)
        reassertWindowTitle(on: window)

        // Native sizing path:
        // guard !didApplyInitialWindowSize else { return }
        // didApplyInitialWindowSize = true
        // window.styleMask.insert(.resizable)
        // let initialSize = settings.resolvedMainWindowSize ?? NSSize(width: 1160, height: 760)
        // window.setContentSize(initialSize)
        // window.minSize = NSSize(width: 900, height: 560)
        // persistWindowSize(window)
    }

    private func configureToolbar(_ toolbar: NSToolbar) {
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        installToolbarDisplayModeObserverIfNeeded(for: toolbar)

        let targetDisplayMode: NSToolbar.DisplayMode = settings.toolbarIconOnly ? .iconOnly : .iconAndLabel
        if toolbar.displayMode != targetDisplayMode {
            toolbar.displayMode = targetDisplayMode
        }
    }

    private func installToolbarDisplayModeObserverIfNeeded(for toolbar: NSToolbar) {
        let identifier = ObjectIdentifier(toolbar)
        guard observedToolbarIdentifier != identifier else { return }

        toolbarDisplayModeObservation = toolbar.observe(\.displayMode, options: [.new]) { toolbar, _ in
            Task { @MainActor in
                let iconOnly = toolbar.displayMode != .iconAndLabel
                if settings.toolbarIconOnly != iconOnly {
                    settings.toolbarIconOnly = iconOnly
                }
            }
        }
        observedToolbarIdentifier = identifier
    }

    private func removeToolbarDisplayModeObserver() {
        toolbarDisplayModeObservation = nil
        observedToolbarIdentifier = nil
    }

    private func installToolbarGlassBackdrop(in window: NSWindow) {
        guard let themeFrame = window.contentView?.superview else { return }
        let identifier = NSUserInterfaceItemIdentifier("litrix.toolbar.glass.backdrop")
        let backdrop: ToolbarGlassBackdropView
        if let existing = themeFrame.subviews.first(where: { $0.identifier == identifier }) as? ToolbarGlassBackdropView {
            backdrop = existing
        } else {
            backdrop = ToolbarGlassBackdropView(frame: .zero)
            backdrop.identifier = identifier
            backdrop.autoresizingMask = [.width, .minYMargin]
            themeFrame.addSubview(backdrop, positioned: .below, relativeTo: window.contentView)
        }

        let toolbarHeight: CGFloat = 74
        backdrop.frame = NSRect(
            x: 0,
            y: max(0, themeFrame.bounds.height - toolbarHeight),
            width: themeFrame.bounds.width,
            height: toolbarHeight
        )
        backdrop.needsLayout = true
    }

    private func installWindowSizePersistenceObserversIfNeeded(window: NSWindow) {
        guard windowSizePersistenceObservers.isEmpty else { return }

        let center = NotificationCenter.default
        let didResizeObserver = center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                persistWindowSize(window)
            }
        }
        windowSizePersistenceObservers.append(didResizeObserver)

        let didEndLiveResizeObserver = center.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                persistWindowSize(window)
            }
        }
        windowSizePersistenceObservers.append(didEndLiveResizeObserver)

        let willCloseObserver = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                persistWindowSize(window)
            }
        }
        windowSizePersistenceObservers.append(willCloseObserver)
    }

    private func persistWindowSize(_ window: NSWindow?) {
        guard let window else { return }
        settings.recordMainWindowSize(window.contentLayoutRect.size)
    }

    private func removeWindowSizePersistenceObservers() {
        guard !windowSizePersistenceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for observer in windowSizePersistenceObservers {
            center.removeObserver(observer)
        }
        windowSizePersistenceObservers.removeAll()
    }

    private func installAppLifecycleObservers() {
        guard appLifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default

        let resignObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak store] _ in
            Task { @MainActor in
                isAppInBackground = true
                // Throttle background saves
                store?.suspendAutoSave()
            }
        }
        appLifecycleObservers.append(resignObserver)

        let becomeObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak store] _ in
            Task { @MainActor in
                isAppInBackground = false
                store?.resumeAutoSave()
                // Refresh UI now that we're foreground again
                scheduleSortedPapersRecompute()
            }
        }
        appLifecycleObservers.append(becomeObserver)
    }

    private func removeAppLifecycleObservers() {
        let center = NotificationCenter.default
        for observer in appLifecycleObservers {
            center.removeObserver(observer)
        }
        appLifecycleObservers.removeAll()
    }

    private var metadataPlanningTitles: [String] {
        metadataPlannedTasks
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.title)
    }

    private var metadataQueuedTitles: [String] {
        let queuedIDs = metadataRefreshQueue.map(\.paperID)
        var seen: Set<UUID> = []
        let uniqueIDs = queuedIDs.filter { seen.insert($0).inserted }
        return uniqueIDs.compactMap { store.paper(id: $0) }
            .map { normalizedTitle($0.title) }
    }

    private var metadataCompletedTitles: [String] {
        metadataCompletedTasks
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map(\.title)
    }

    private var metadataAnalyzingTitles: [String] {
        let ids = Array(updatingPaperIDs)
        return ids.compactMap { store.paper(id: $0) }
            .map { normalizedTitle($0.title) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var metadataTaskTitles: [String] {
        uniqueTaskTitles(metadataAnalyzingTitles + metadataQueuedTitles)
    }

    private var metadataWaitingCount: Int {
        Set(metadataRefreshQueue.map(\.paperID)).count
    }

    private var isMetadataUpdating: Bool {
        metadataRefreshWorkerTask != nil || !updatingPaperIDs.isEmpty
    }

    private var translationTaskEntries: [TranslationStatusDisplayEntry] {
        var seen: Set<UUID> = []
        var entries: [TranslationStatusDisplayEntry] = []

        let runningJobs = activeTranslationJobs.values.sorted { lhs, rhs in
            lhs.enqueuedAt < rhs.enqueuedAt
        }
        for job in runningJobs where seen.insert(job.paperID).inserted {
            entries.append(
                TranslationStatusDisplayEntry(
                    paperID: job.paperID,
                    title: job.title,
                    phase: .running,
                    progress: min(max(translationProgressByPaperID[job.paperID] ?? 0.08, 0.04), 0.96),
                    message: nil
                )
            )
        }

        let queuedEntries = translationQueuedTasks.sorted { $0.timestamp < $1.timestamp }
        for entry in queuedEntries where seen.insert(entry.paperID).inserted {
            entries.append(
                TranslationStatusDisplayEntry(
                    paperID: entry.paperID,
                    title: entry.title,
                    phase: .queued,
                    progress: 0,
                    message: nil
                )
            )
        }

        let failedEntries = translationFailedTasks.sorted { $0.timestamp > $1.timestamp }.prefix(5)
        for entry in failedEntries where seen.insert(entry.paperID).inserted {
            entries.append(
                TranslationStatusDisplayEntry(
                    paperID: entry.paperID,
                    title: entry.title,
                    phase: .failed,
                    progress: 0,
                    message: entry.message
                )
            )
        }

        let completedEntries = translationCompletedTasks.sorted { $0.timestamp > $1.timestamp }.prefix(5)
        for entry in completedEntries where seen.insert(entry.paperID).inserted {
            entries.append(
                TranslationStatusDisplayEntry(
                    paperID: entry.paperID,
                    title: entry.title,
                    phase: .completed,
                    progress: 1,
                    message: nil
                )
            )
        }

        return Array(entries.prefix(8))
    }

    private var translationWaitingCount: Int {
        Set(translationQueuedTasks.map(\.paperID)).union(activeTranslationJobs.keys).count
    }

    private var isTranslationUpdating: Bool {
        !translationQueue.isEmpty || !activeTranslationJobs.isEmpty || !translationJobTasks.isEmpty
    }

    private func uniqueTaskTitles(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        return titles.filter { seen.insert($0).inserted }
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Paper" : trimmed
    }

    private func makeTaskStatusEntries(from papers: [Paper], timestamp: Date = Date()) -> [TaskStatusEntry] {
        var seen: Set<UUID> = []
        return papers.compactMap { paper in
            guard seen.insert(paper.id).inserted else { return nil }
            return TaskStatusEntry(
                paperID: paper.id,
                title: normalizedTitle(paper.title),
                timestamp: timestamp
            )
        }
    }

    private func upsertRecentTaskEntry(
        _ entry: TaskStatusEntry,
        into entries: [TaskStatusEntry],
        limit: Int = 5
    ) -> [TaskStatusEntry] {
        var updated = entries.filter { $0.paperID != entry.paperID }
        updated.insert(entry, at: 0)
        updated.sort { $0.timestamp > $1.timestamp }
        if updated.count > limit {
            updated.removeSubrange(limit...)
        }
        return updated
    }

    private func removeTaskEntry(for paperID: UUID, from entries: [TaskStatusEntry]) -> [TaskStatusEntry] {
        entries.filter { $0.paperID != paperID }
    }

    private var statusBarEntries: [(title: String, type: String)] {
        var result: [(String, String)] = []

        let metaTitles = metadataTaskTitles
        for title in metaTitles.prefix(2) {
            result.append((title, "metadata"))
        }

        let transEntries = translationTaskEntries
        for entry in transEntries where entry.phase == .running {
            result.append((entry.title, "translation"))
        }
        for entry in transEntries where entry.phase == .queued {
            result.append((entry.title, "queued"))
        }

        return Array(result.prefix(6))
    }

    @ViewBuilder
    private var taskStatusBarOverlay: some View {
        if !statusBarEntries.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(statusBarEntries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        Image(systemName: statusBarIcon(entry.type))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(entry.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: -1)
            .padding(8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func statusBarIcon(_ type: String) -> String {
        switch type {
        case "metadata": return "arrow.triangle.2.circlepath"
        case "translation": return "doc.text.magnifyingglass"
        case "queued": return "clock"
        default: return "circle.fill"
        }
    }

    private func checkAPIConnectionFromToolbarTool(
        apiKeyInput: String,
        endpointInput: String,
        modelInput: String
    ) {
        guard !isCheckingAPIConnectionFromTool else { return }
        persistAPIToolDraftsIfNeeded()

        let resolvedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpoint = endpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if !resolvedKey.isEmpty, resolvedKey != settings.metadataAPIKey {
            settings.metadataAPIKey = resolvedKey
        }
        if !resolvedEndpoint.isEmpty, resolvedEndpoint != settings.metadataAPIBaseURL {
            settings.metadataAPIBaseURL = resolvedEndpoint
        }
        if !resolvedModel.isEmpty, resolvedModel != settings.metadataModel {
            settings.metadataModel = resolvedModel
        }

        isCheckingAPIConnectionFromTool = true
        apiToolStatusText = "检测链接中..."
        apiToolConnectionResult = ""

        Task {
            do {
                let reply = try await MetadataEnrichmentService.checkConnection(
                    apiProvider: settings.resolvedAPIProvider,
                    apiEndpoint: settings.resolvedAPIEndpoint,
                    apiKey: resolvedKey.isEmpty ? settings.resolvedAPIKey : resolvedKey,
                    model: resolvedModel.isEmpty ? settings.resolvedModel : resolvedModel,
                    thinkingEnabled: settings.resolvedThinkingEnabled
                )
                await MainActor.run {
                    apiToolStatusText = "检测完成：连接成功"
                    apiToolConnectionResult = "连接成功\n\n\(reply)"
                    isCheckingAPIConnectionFromTool = false
                }
            } catch {
                await MainActor.run {
                    apiToolStatusText = "检测完成：连接失败"
                    apiToolConnectionResult = "连接失败\n\n\(error.localizedDescription)"
                    isCheckingAPIConnectionFromTool = false
                }
            }
        }
    }

    private func persistAPIToolDraftsIfNeeded() {
        let trimmed = apiToolKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = apiToolEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = apiToolModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed != settings.metadataAPIKey {
            settings.metadataAPIKey = trimmed
        }

        if !trimmedEndpoint.isEmpty, trimmedEndpoint != settings.metadataAPIBaseURL {
            settings.metadataAPIBaseURL = trimmedEndpoint
        }

        if !trimmedModel.isEmpty, trimmedModel != settings.metadataModel {
            settings.metadataModel = trimmedModel
        }
    }

    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                if handleQuickCitationFlagsChanged(event) {
                    return nil
                }
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if isQuickCitationOverlayPresented {
                if event.keyCode == 53 {
                    dismissQuickCitationOverlay()
                    return nil
                }
                if event.keyCode == 125 {
                    moveQuickCitationSelection(offset: 1)
                    return nil
                }
                if event.keyCode == 126 {
                    moveQuickCitationSelection(offset: -1)
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    if let selected = quickCitationSelectedPaper {
                        applyQuickCitation(selected)
                    } else {
                        runQuickCitationSearch()
                    }
                    return nil
                }
                return event
            }

            if (event.keyCode == 36 || event.keyCode == 76),
               modifiers == [.command],
               let target = activeCellEditTarget {
                saveCellEdit(target)
                return nil
            }

            if event.keyCode == 3, modifiers == [.command] {
                workspace.focusSearch()
                return nil
            }

            if event.keyCode == 3, modifiers == [.command, .shift] {
                workspace.presentAdvancedSearch()
                return nil
            }

            if event.keyCode == 34, modifiers == [.command] {
                toggleDetailsPaneVisibility()
                return nil
            }

            if event.keyCode == 37, modifiers == [.command, .shift] {
                presentRightPane(.filter)
                return nil
            }

            if isExpandRowShortcut(event, modifiers: modifiers) {
                applyTableRowHeightMode(.expanded)
                return nil
            }

            if isCompactRowShortcut(event, modifiers: modifiers) {
                applyTableRowHeightMode(.compact)
                return nil
            }

            if isTextInputFocused {
                return event
            }

            if event.keyCode == 14, modifiers == [.command] {
                openHoveredTableCellEditor()
                return nil
            }

            if modifiers.isEmpty, let quickNumber = quickNumberForKeyCode(event.keyCode), selectedPaper != nil {
                applyQuickTag(number: quickNumber)
                return nil
            }

            if event.keyCode == 8, modifiers == [.command], selectedPaper != nil {
                copyInTextCitationForSelectedPaper()
                return nil
            }

            if event.keyCode == 8, modifiers == [.command, .shift], selectedPaper != nil {
                copyReferenceCitationForSelectedPaper()
                return nil
            }

            if event.keyCode == 49, modifiers.isEmpty, !event.isARepeat {
                toggleSpacePreview()
                return nil
            }

            if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty {
                if beginInlineRenameFromSidebarSelection() {
                    return nil
                }
                guard let paper = selectedPaper else { return event }
                store.openPDF(for: paper)
                return nil
            }

            if event.keyCode == 126, modifiers.isEmpty {
                selectRelativePaper(offset: -1)
                return nil
            }

            if event.keyCode == 125, modifiers.isEmpty {
                selectRelativePaper(offset: 1)
                return nil
            }

            if event.keyCode == 51, modifiers == [.command] {
                guard selectedPaper != nil else { return event }
                requestDeleteSelectedPaper()
                return nil
            }

            if event.keyCode == 31, modifiers == [.command] {
                if centerPaneMode == .images, selectedImagePreviewURL != nil {
                    openSelectedImageInSystemApp()
                    return nil
                }
                if let paper = selectedPaper {
                    store.openPDF(for: paper)
                    return nil
                }
                return event
            }

            if event.keyCode == 0, modifiers == [.command] {
                selectedPaperIDs = Set(cachedSortedPaperIDs)
                selectedPaperID = primarySelection(from: selectedPaperIDs)
                return nil
            }

            if event.keyCode == 30, modifiers == [.command] || modifiers == [.command, .shift] {
                toggleDetailsPaneVisibility()
                return nil
            }

            if event.keyCode == 33, modifiers == [.command] || modifiers == [.command, .shift] {
                toggleSidebarVisibility()
                return nil
            }

            return event
        }
    }

    private func handleQuickCitationFlagsChanged(_ event: NSEvent) -> Bool {
        guard settings.quickCitationEnabled else {
            lastCommandOnlyKeyCode = nil
            lastCommandOnlyEventTimestamp = 0
            return false
        }

        // Left command = 55, right command = 54.
        guard event.keyCode == 54 || event.keyCode == 55 else {
            return false
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == [.command] else {
            if modifiers.isEmpty {
                lastCommandOnlyKeyCode = nil
                lastCommandOnlyEventTimestamp = 0
            }
            return false
        }

        let now = event.timestamp
        if let lastKey = lastCommandOnlyKeyCode,
           lastKey != event.keyCode,
           now - lastCommandOnlyEventTimestamp <= 0.45 {
            if isQuickCitationOverlayPresented {
                dismissQuickCitationOverlay()
            } else {
                presentQuickCitationOverlay()
            }
            lastCommandOnlyKeyCode = nil
            lastCommandOnlyEventTimestamp = 0
            return true
        }

        lastCommandOnlyKeyCode = event.keyCode
        lastCommandOnlyEventTimestamp = now
        return false
    }

    private func isExpandRowShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return false }
        if event.keyCode == 24 || event.keyCode == 69 {
            return true
        }
        let key = event.charactersIgnoringModifiers ?? ""
        return key == "=" || key == "+"
    }

    private func isCompactRowShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers == [.command] || modifiers == [.command, .shift] else { return false }
        if event.keyCode == 27 || event.keyCode == 78 {
            return true
        }
        let key = event.charactersIgnoringModifiers ?? ""
        return key == "-" || key == "_"
    }

    private var isTextInputFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func removeLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        lastCommandOnlyKeyCode = nil
        lastCommandOnlyEventTimestamp = 0
    }

    private func isUpdatingMetadata(for paper: Paper) -> Bool {
        updatingPaperIDs.contains(paper.id)
    }

    private func runMetadataRefresh(
        source: MetadataRefreshSource,
        forPaperIDs paperIDs: [UUID],
        mode: MetadataRefreshMode,
        customFields: [MetadataField]?,
        showErrorsInAlert: Bool
    ) {
        switch source {
        case .api:
            refreshMetadata(
                forPaperIDs: paperIDs,
                mode: mode,
                customFields: customFields,
                showErrorsInAlert: showErrorsInAlert
            )
        case .local:
            refreshLocalMetadata(
                forPaperIDs: paperIDs,
                mode: mode,
                customFields: customFields,
                showErrorsInAlert: showErrorsInAlert
            )
        case .web:
            refreshWebMetadata(
                forPaperIDs: paperIDs,
                mode: mode,
                customFields: customFields,
                showErrorsInAlert: showErrorsInAlert
            )
        }
    }

    private func refreshMetadata(
        forPaperIDs paperIDs: [UUID],
        mode: MetadataRefreshMode,
        customFields: [MetadataField]?,
        showErrorsInAlert: Bool
    ) {
        let uniqueIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !uniqueIDs.isEmpty else { return }
        let requestTime = Date()
        var plannedPapers: [Paper] = []

        for paperID in uniqueIDs {
            if let index = metadataRefreshQueue.firstIndex(where: { $0.paperID == paperID }) {
                metadataRefreshQueue[index].showErrorsInAlert = metadataRefreshQueue[index].showErrorsInAlert || showErrorsInAlert
                continue
            }

            if updatingPaperIDs.contains(paperID) {
                continue
            }

            guard let paper = store.paper(id: paperID) else { continue }
            let targetFields = resolvedRequestedMetadataFields(
                for: paper,
                mode: mode,
                customFields: customFields
            )
            guard !targetFields.isEmpty else { continue }

            plannedPapers.append(paper)
            metadataRefreshQueue.append(
                MetadataRefreshQueueItem(
                    paperID: paperID,
                    mode: mode,
                    fields: targetFields,
                    showErrorsInAlert: showErrorsInAlert
                )
            )
        }

        if metadataRefreshQueue.isEmpty {
            if mode == .refreshMissing {
                alertMessage = "当前所选文献没有可补全的缺失字段。"
            } else if mode == .customRefresh {
                alertMessage = "请先选择至少一个要刷新的字段。"
            }
            return
        }

        if !plannedPapers.isEmpty {
            metadataPlannedTasks = makeTaskStatusEntries(from: plannedPapers, timestamp: requestTime)
        }
        startMetadataRefreshQueueIfNeeded()
    }

    private func refreshImpactFactorsViaEasyScholar(
        forPaperIDs paperIDs: [UUID],
        showErrorsInAlert: Bool
    ) {
        let key = settings.resolvedEasyScholarAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isImpactFactorColumnSettingsPresented = true
            alertMessage = EasyScholarError.missingAPIKey.localizedDescription
            return
        }

        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }

        let plannedPapers = targetIDs.compactMap { store.paper(id: $0) }
        if !plannedPapers.isEmpty {
            metadataPlannedTasks = makeTaskStatusEntries(from: plannedPapers, timestamp: Date())
        }

        let shouldShowProgress = targetIDs.count > 10
        if shouldShowProgress {
            impactFactorProgressProcessedCount = 0
            impactFactorProgressTotalCount = targetIDs.count
            impactFactorProgressStatusText = localized(
                chinese: "正在更新影响因子…",
                english: "Updating impact factors..."
            )
            withAnimation(.easeInOut(duration: 0.16)) {
                isImpactFactorProgressVisible = true
            }
        }

        Task { @MainActor in
            defer {
                if shouldShowProgress {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isImpactFactorProgressVisible = false
                    }
                }
            }
            for paperID in targetIDs {
                guard !Task.isCancelled else { return }
                guard !updatingPaperIDs.contains(paperID),
                      var paper = store.paper(id: paperID) else {
                    if shouldShowProgress {
                        impactFactorProgressProcessedCount += 1
                    }
                    continue
                }

                updatingPaperIDs.insert(paperID)
                defer {
                    updatingPaperIDs.remove(paperID)
                    if shouldShowProgress {
                        impactFactorProgressProcessedCount += 1
                    }
                }

                do {
                    paper.impactFactor = try await easyScholarImpactFactor(for: paper)
                    store.updatePaper(paper)
                    if let refreshed = store.paper(id: paperID) {
                        refreshEditedPaperImmediately(refreshed)
                    }
                    metadataCompletedTasks = upsertRecentTaskEntry(
                        TaskStatusEntry(
                            paperID: paperID,
                            title: normalizedTitle(paper.title),
                            timestamp: Date()
                        ),
                        into: metadataCompletedTasks
                    )
                } catch {
                    if showErrorsInAlert {
                        alertMessage = error.localizedDescription
                    } else {
                        print("easyScholar 更新影响因子失败(\(paperID)): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func refreshLocalMetadata(
        forPaperIDs paperIDs: [UUID],
        mode: MetadataRefreshMode,
        customFields: [MetadataField]?,
        showErrorsInAlert: Bool
    ) {
        let uniqueIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !uniqueIDs.isEmpty else { return }

        let requestTime = Date()
        var planned: [(paper: Paper, fields: [MetadataField])] = []
        for paperID in uniqueIDs {
            guard !updatingPaperIDs.contains(paperID),
                  let paper = store.paper(id: paperID) else {
                continue
            }
            let fields = resolvedRequestedMetadataFields(
                for: paper,
                mode: mode,
                customFields: customFields
            )
            guard !fields.isEmpty else { continue }
            planned.append((paper, fields))
        }

        guard !planned.isEmpty else {
            if showErrorsInAlert {
                if mode == .refreshMissing {
                    alertMessage = "当前所选文献没有可补全的缺失字段。"
                } else if mode == .customRefresh {
                    alertMessage = "请先选择至少一个要刷新的字段。"
                }
            }
            return
        }

        metadataPlannedTasks = makeTaskStatusEntries(
            from: planned.map { $0.paper },
            timestamp: requestTime
        )

        Task { @MainActor in
            for item in planned {
                await processLocalMetadataRefresh(
                    paperID: item.paper.id,
                    fields: item.fields,
                    mode: mode,
                    showErrorsInAlert: showErrorsInAlert && planned.count == 1
                )
            }
        }
    }

    private func refreshWebMetadata(
        forPaperIDs paperIDs: [UUID],
        mode: MetadataRefreshMode,
        customFields: [MetadataField]?,
        showErrorsInAlert: Bool
    ) {
        let uniqueIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !uniqueIDs.isEmpty else { return }

        let requestTime = Date()
        var planned: [(paper: Paper, fields: [MetadataField])] = []
        for paperID in uniqueIDs {
            guard !updatingPaperIDs.contains(paperID),
                  let paper = store.paper(id: paperID) else {
                continue
            }
            let fields = resolvedRequestedMetadataFields(
                for: paper,
                mode: mode,
                customFields: customFields
            )
            guard !fields.isEmpty else { continue }
            planned.append((paper, fields))
        }

        guard !planned.isEmpty else {
            if showErrorsInAlert {
                if mode == .refreshMissing {
                    alertMessage = "当前所选文献没有可补全的缺失字段。"
                } else if mode == .customRefresh {
                    alertMessage = "请先选择至少一个要刷新的字段。"
                }
            }
            return
        }

        metadataPlannedTasks = makeTaskStatusEntries(
            from: planned.map { $0.paper },
            timestamp: requestTime
        )

        Task { @MainActor in
            for item in planned {
                await processWebMetadataRefresh(
                    paperID: item.paper.id,
                    fields: item.fields,
                    mode: mode,
                    showErrorsInAlert: showErrorsInAlert && planned.count == 1
                )
            }
        }
    }

    private func resolvedRequestedMetadataFields(
        for paper: Paper,
        mode: MetadataRefreshMode,
        customFields: [MetadataField]?
    ) -> [MetadataField] {
        switch mode {
        case .refreshAll:
            return MetadataField.allCases
        case .refreshMissing:
            return MetadataField.allCases.filter { $0.isMissing(in: paper) }
        case .customRefresh:
            return customFields ?? settings.metadataCustomRefreshFields
        }
    }

    private func beginCustomRefreshSelection(
        forPaperIDs paperIDs: [UUID],
        source: MetadataRefreshSource = .api
    ) {
        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }
        runMetadataRefresh(
            source: source,
            forPaperIDs: targetIDs,
            mode: .customRefresh,
            customFields: settings.metadataCustomRefreshFields,
            showErrorsInAlert: targetIDs.count == 1
        )
    }

    private func openCustomRefreshFieldChooser(
        forPaperIDs paperIDs: [UUID],
        source: MetadataRefreshSource = .api
    ) {
        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }
        customRefreshTargetPaperIDs = targetIDs
        customRefreshSource = source
        isCustomRefreshChooserPresented = true
    }

    private func uniqueOrderedPaperIDs(from ids: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private func startMetadataRefreshQueueIfNeeded() {
        guard metadataRefreshWorkerTask == nil else { return }

        metadataRefreshWorkerTask = Task { @MainActor in
            while !metadataRefreshQueue.isEmpty {
                guard !Task.isCancelled else { break }
                let item = metadataRefreshQueue.removeFirst()
                activeMetadataRefreshItem = item
                await processMetadataRefresh(item)
                activeMetadataRefreshItem = nil
            }
            activeMetadataRefreshItem = nil
            metadataRefreshWorkerTask = nil
        }
    }

    private func pauseMetadataUpdates() {
        metadataRefreshWorkerTask?.cancel()
        metadataRefreshWorkerTask = nil
        if let activeMetadataRefreshItem,
           !metadataRefreshQueue.contains(where: { $0.paperID == activeMetadataRefreshItem.paperID }) {
            metadataRefreshQueue.insert(activeMetadataRefreshItem, at: 0)
        }
        activeMetadataRefreshItem = nil
        updatingPaperIDs.removeAll()
    }

    private func terminateMetadataUpdates() {
        metadataRefreshWorkerTask?.cancel()
        metadataRefreshWorkerTask = nil
        activeMetadataRefreshItem = nil
        metadataRefreshQueue.removeAll()
        updatingPaperIDs.removeAll()
        metadataPlannedTasks.removeAll()
        metadataCompletedTasks.removeAll()
    }

    @MainActor
    private func processLocalMetadataRefresh(
        paperID: UUID,
        fields requestedFields: [MetadataField],
        mode refreshMode: MetadataRefreshMode,
        showErrorsInAlert: Bool
    ) async {
        guard !Task.isCancelled else { return }
        guard !updatingPaperIDs.contains(paperID) else { return }
        guard var latest = store.paper(id: paperID) else { return }

        updatingPaperIDs.insert(paperID)
        defer {
            updatingPaperIDs.remove(paperID)
        }

        let before = latest
        guard let suggestion = store.localMetadataSuggestion(for: latest),
              metadataSuggestionHasValue(suggestion, fields: requestedFields) else {
            if showErrorsInAlert {
                alertMessage = "本地识别没有从文件中找到可用元数据，已保留现有内容。"
            }
            return
        }

        applyNonEmptyMetadataSuggestion(
            suggestion,
            to: &latest,
            fields: requestedFields,
            mode: refreshMode
        )

        guard metadataFieldsChanged(from: before, to: latest, fields: requestedFields) else {
            if showErrorsInAlert {
                alertMessage = "本地识别没有找到可更新的非空字段，已保留现有内容。"
            }
            return
        }

        store.updatePaper(latest)
        if let refreshed = store.paper(id: paperID) {
            refreshEditedPaperImmediately(refreshed)
        }
        metadataCompletedTasks = upsertRecentTaskEntry(
            TaskStatusEntry(
                paperID: paperID,
                title: normalizedTitle(latest.title),
                timestamp: Date()
            ),
            into: metadataCompletedTasks
        )
        if settings.autoRenameImportedPDFFiles {
            _ = store.renameStoredPDF(forPaperID: paperID)
        }
    }

    @MainActor
    private func processWebMetadataRefresh(
        paperID: UUID,
        fields requestedFields: [MetadataField],
        mode refreshMode: MetadataRefreshMode,
        showErrorsInAlert: Bool
    ) async {
        guard !Task.isCancelled else { return }
        guard !updatingPaperIDs.contains(paperID) else { return }
        guard var latest = store.paper(id: paperID) else { return }

        updatingPaperIDs.insert(paperID)
        defer {
            updatingPaperIDs.remove(paperID)
        }

        let before = latest
        let sourceURL = resolvedWebPageURL(for: latest)

        do {
            let result = try await LitrixWebMetadataService.fetch(from: sourceURL)
            var attachedPDF = false
            applyNonEmptyMetadataSuggestion(
                result.suggestion,
                to: &latest,
                fields: requestedFields,
                mode: refreshMode
            )
            if latest.webPageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                latest.webPageURL = result.pageURL
            }

            if !store.hasExistingPDFAttachment(for: latest),
               !result.pdfURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let temporaryPDFURL = try? await LitrixWebMetadataService.downloadPDF(from: result.pdfURL) {
                    defer { try? FileManager.default.removeItem(at: temporaryPDFURL) }
                    attachedPDF = store.attachPDF(
                        to: paperID,
                        from: temporaryPDFURL,
                        originalFileName: temporaryPDFURL.lastPathComponent
                    )
                    if attachedPDF, let attachedPaper = store.paper(id: paperID) {
                        latest.storageFolderName = attachedPaper.storageFolderName
                        latest.storedPDFFileName = attachedPaper.storedPDFFileName
                        latest.originalPDFFileName = attachedPaper.originalPDFFileName
                        latest.preferredOpenPDFFileName = attachedPaper.preferredOpenPDFFileName
                    }
                }
            }

            let changed = metadataFieldsChanged(from: before, to: latest, fields: requestedFields)
                || before.webPageURL != latest.webPageURL
                || attachedPDF
            guard changed else {
                if showErrorsInAlert {
                    alertMessage = "网页中没有找到可更新的非空字段，已保留现有内容。"
                }
                return
            }

            store.updatePaper(latest)
            if let refreshed = store.paper(id: paperID) {
                refreshEditedPaperImmediately(refreshed)
            }
            metadataCompletedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: paperID,
                    title: normalizedTitle(latest.title),
                    timestamp: Date()
                ),
                into: metadataCompletedTasks
            )
            if settings.autoRenameImportedPDFFiles {
                _ = store.renameStoredPDF(forPaperID: paperID)
            }
        } catch {
            if showErrorsInAlert {
                alertMessage = error.localizedDescription
            } else {
                print("从网页刷新元数据失败(\(paperID)): \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func processMetadataRefresh(_ item: MetadataRefreshQueueItem) async {
        let paperID = item.paperID
        let showErrorsInAlert = item.showErrorsInAlert
        let requestedFields = item.fields
        let refreshMode = item.mode

        guard !Task.isCancelled else { return }

        guard let paper = store.paper(id: paperID) else { return }

        let documentURL = store.pdfURL(for: paper)
        let fallbackText = metadataRefreshFallbackText(for: paper)
        guard documentURL != nil || !fallbackText.isEmpty else {
            if showErrorsInAlert {
                alertMessage = "这篇文献还没有可读取的附件或条目信息。"
            }
            return
        }

        guard !updatingPaperIDs.contains(paperID) else { return }
        updatingPaperIDs.insert(paperID)
        defer {
            updatingPaperIDs.remove(paperID)
        }

        do {
            let suggestion = try await MetadataEnrichmentService.enrichMetadata(
                apiProvider: settings.resolvedAPIProvider,
                pdfURL: documentURL,
                originalFileName: paper.originalPDFFileName,
                fallbackText: fallbackText,
                apiEndpoint: settings.resolvedAPIEndpoint,
                apiKey: settings.resolvedAPIKey,
                model: settings.resolvedModel,
                thinkingEnabled: settings.resolvedThinkingEnabled,
                promptBlueprint: settings.resolvedMetadataPromptBlueprint,
                requestedFields: requestedFields
            )

            guard !Task.isCancelled else { return }
            guard var latest = store.paper(id: paperID) else { return }
            latest.apply(suggestion, fields: requestedFields, mode: refreshMode)
            applyLocalMetadataFallbackIfAvailable(to: &latest, fields: requestedFields)
            await applyDOICitationMetadataIfAvailable(to: &latest, fields: requestedFields, mode: refreshMode)
            await applyEasyScholarImpactFactorIfAvailable(to: &latest, fields: requestedFields, mode: refreshMode)
            store.updatePaper(latest)
            if let refreshed = store.paper(id: paperID) {
                refreshEditedPaperImmediately(refreshed)
            }
            metadataCompletedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: paperID,
                    title: normalizedTitle(latest.title),
                    timestamp: Date()
                ),
                into: metadataCompletedTasks
            )
            if settings.autoRenameImportedPDFFiles {
                _ = store.renameStoredPDF(forPaperID: paperID)
            }
        } catch {
            if showErrorsInAlert {
                if !presentMetadataReturnedContentPrompt(for: error) {
                    alertMessage = error.localizedDescription
                }
            } else {
                print("自动更新元数据失败(\(paperID)): \(metadataRefreshFailureDescription(for: error))")
            }
        }
    }

    private func metadataSuggestionHasValue(
        _ suggestion: MetadataSuggestion,
        fields: [MetadataField]
    ) -> Bool {
        fields.contains { field in
            !MetadataValueNormalizer.normalize(field.value(in: suggestion), for: field)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    private func metadataFieldsChanged(
        from before: Paper,
        to after: Paper,
        fields: [MetadataField]
    ) -> Bool {
        fields.contains { field in
            MetadataValueNormalizer.normalize(field.value(in: before), for: field)
                != MetadataValueNormalizer.normalize(field.value(in: after), for: field)
        }
    }

    private func applyDOICitationMetadataIfAvailable(
        to paper: inout Paper,
        fields requestedFields: [MetadataField],
        mode: MetadataRefreshMode
    ) async {
        let doi = MetadataValueNormalizer.normalizeDOI(paper.doi)
        guard !doi.isEmpty else { return }

        let citationFields: Set<MetadataField> = [
            .title, .englishTitle, .authors, .authorsEnglish, .year, .source, .doi,
            .abstractText, .chineseAbstract, .volume, .issue, .pages, .paperType
        ]
        let targetFields = requestedFields.filter { citationFields.contains($0) }
        guard !targetFields.isEmpty else { return }

        do {
            let suggestion = try await DOIMetadataService.fetchSuggestion(for: doi)
            applyNonEmptyMetadataSuggestion(suggestion, to: &paper, fields: targetFields, mode: mode)
        } catch {
            return
        }
    }

    private func applyEasyScholarImpactFactorIfAvailable(
        to paper: inout Paper,
        fields requestedFields: [MetadataField],
        mode: MetadataRefreshMode
    ) async {
        guard requestedFields.contains(.impactFactor) else { return }
        if mode == .refreshMissing,
           !paper.impactFactor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }

        do {
            paper.impactFactor = try await easyScholarImpactFactor(for: paper)
        } catch {
            return
        }
    }

    private func easyScholarImpactFactor(for paper: Paper) async throws -> String {
        let source = paper.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw EasyScholarError.missingPublicationName }

        let ranks = try await EasyScholarService.fetchOfficialRank(
            publicationName: source,
            secretKey: settings.resolvedEasyScholarAPIKey
        )
        let formatted = EasyScholarService.formattedImpactFactor(
            from: ranks,
            fields: settings.easyScholarFields,
            abbreviations: settings.easyScholarAbbreviations
        )
        guard !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EasyScholarError.noRankData
        }
        return formatted
    }

    private func applyLocalMetadataFallbackIfAvailable(
        to paper: inout Paper,
        fields requestedFields: [MetadataField]
    ) {
        let fallbackFields = requestedFields.filter { field in
            switch field {
            case .title, .englishTitle, .authors, .authorsEnglish, .year, .source, .doi,
                 .abstractText, .chineseAbstract, .volume, .issue, .pages, .paperType:
                return true
            case .rqs, .conclusion, .results, .category, .impactFactor, .samples, .participantType,
                 .variables, .dataCollection, .dataAnalysis, .methodology, .theoreticalFoundation,
                 .educationalLevel, .country, .keywords, .limitations:
                return false
            }
        }
        guard !fallbackFields.isEmpty,
              let suggestion = store.localMetadataSuggestion(for: paper) else {
            return
        }
        applyNonEmptyMetadataSuggestion(
            suggestion,
            to: &paper,
            fields: fallbackFields,
            mode: .refreshMissing
        )
    }

    private func applyNonEmptyMetadataSuggestion(
        _ suggestion: MetadataSuggestion,
        to paper: inout Paper,
        fields: [MetadataField],
        mode: MetadataRefreshMode
    ) {
        for field in fields {
            let incoming = MetadataValueNormalizer.normalize(field.value(in: suggestion), for: field)
            guard !incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            switch mode {
            case .refreshAll, .customRefresh:
                field.assign(incoming, to: &paper)
            case .refreshMissing:
                guard field.isMissing(in: paper) else { continue }
                field.assign(incoming, to: &paper)
            }
        }
    }

    private func presentMetadataReturnedContentPrompt(for error: Error) -> Bool {
        guard let metadataError = error as? MetadataEnrichmentError,
              let content = metadataError.rawReturnedContent else {
            return false
        }

        metadataReturnedContentPrompt = MetadataReturnedContentPromptState(content: content)
        return true
    }

    private func metadataRefreshFailureDescription(for error: Error) -> String {
        guard let metadataError = error as? MetadataEnrichmentError,
              let content = metadataError.rawReturnedContent else {
            return error.localizedDescription
        }

        return "\(metadataError.localizedDescription)\n\(content)"
    }

    private func metadataRefreshFallbackText(for paper: Paper) -> String {
        let fields: [(String, String)] = [
            ("标题", paper.title),
            ("中文标题", paper.chineseTitle),
            ("英文标题", paper.englishTitle),
            ("作者", paper.authors),
            ("英文作者", paper.authorsEnglish),
            ("年份", paper.year),
            ("来源", paper.source),
            ("DOI", paper.doi),
            ("摘要", paper.abstractText),
            ("中文摘要", paper.chineseAbstract),
            ("卷", paper.volume),
            ("期", paper.issue),
            ("页码", paper.pages),
            ("文献类型", paper.paperType),
            ("网页链接", paper.webPageURL),
            ("关键词", paper.keywords),
            ("笔记", paper.notes)
        ]

        return fields
            .map { label, value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return "\(label)：\(trimmed)"
            }
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func resolvedWebPageURL(for paper: Paper) -> String {
        let direct = paper.webPageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty {
            return direct
        }

        let patterns = [
            #"(?im)^\s*Web Source:\s*(https?://\S+)"#,
            #"(?im)^\s*Imported from\s*(https?://\S+)"#,
            #"(https?://[^\s<>"']+)"#
        ]
        for pattern in patterns {
            if let range = paper.notes.range(of: pattern, options: .regularExpression) {
                let matched = String(paper.notes[range])
                if let urlRange = matched.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) {
                    return String(matched[urlRange]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.,;"))
                }
            }
        }
        return ""
    }

    private func exportBibTeX(for paper: Paper) {
        let text = BibTeXExporter.exportText(for: paper, fields: settings.exportBibTeXFields)
        let fileStem = paper.title.isEmpty ? "paper" : paper.title
        let suggested = "\(fileStem).bib"
        BibTeXExporter.save(text, suggestedFileName: suggested)
    }

    private func exportBibTeX(for papers: [Paper]) {
        guard !papers.isEmpty else { return }
        if papers.count == 1, let first = papers.first {
            exportBibTeX(for: first)
            return
        }

        let text = papers
            .map { BibTeXExporter.exportText(for: $0, fields: settings.exportBibTeXFields) }
            .joined(separator: "\n\n")
        BibTeXExporter.save(text, suggestedFileName: "Litrix-Export.bib")
    }

    private func exportDetailed(for papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let markdown = papers.map(detailedMarkdown(for:)).joined(separator: "\n\n---\n\n")
        savePlainText(markdown, suggestedFileName: "Litrix-Detailed.md")
    }

    private func detailedMarkdown(for paper: Paper) -> String {
        """
        # \(paper.title.isEmpty ? "Untitled Paper" : paper.title)
        - Authors: \(paper.authors.isEmpty ? "Unknown" : paper.authors)
        - Year: \(paper.year.isEmpty ? "—" : paper.year)
        - Source: \(paper.source.isEmpty ? "—" : paper.source)
        - Added Time: \(formattedAddedTime(from: paper.addedAtMilliseconds))
        - Web Link: \(paper.webPageURL.isEmpty ? "—" : paper.webPageURL)
        - DOI: \(paper.doi.isEmpty ? "—" : paper.doi)
        - Type: \(paper.paperType.isEmpty ? "—" : paper.paperType)
        - Rating: \(clampedRating(paper.rating))/\(PaperRatingScale.maximum)

        ## Abstract
        \(paper.abstractText.isEmpty ? "—" : paper.abstractText)

        ## Chinese Abstract
        \(paper.chineseAbstract.isEmpty ? "—" : paper.chineseAbstract)

        ## Notes
        \(paper.notes.isEmpty ? "—" : paper.notes)

        ## Metadata
        - RQs: \(paper.rqs.isEmpty ? "—" : paper.rqs)
        - Conclusion: \(paper.conclusion.isEmpty ? "—" : paper.conclusion)
        - Results: \(paper.results.isEmpty ? "—" : paper.results)
        - Category: \(paper.category.isEmpty ? "—" : paper.category)
        - IF: \(paper.impactFactor.isEmpty ? "—" : paper.impactFactor)
        - Samples: \(paper.samples.isEmpty ? "—" : paper.samples)
        - Participant Type: \(paper.participantType.isEmpty ? "—" : paper.participantType)
        - Variables: \(paper.variables.isEmpty ? "—" : paper.variables)
        - Data Collection: \(paper.dataCollection.isEmpty ? "—" : paper.dataCollection)
        - Data Analysis: \(paper.dataAnalysis.isEmpty ? "—" : paper.dataAnalysis)
        - Methodology: \(paper.methodology.isEmpty ? "—" : paper.methodology)
        - Theoretical Foundation: \(paper.theoreticalFoundation.isEmpty ? "—" : paper.theoreticalFoundation)
        - Educational Level: \(paper.educationalLevel.isEmpty ? "—" : paper.educationalLevel)
        - Country: \(paper.country.isEmpty ? "—" : paper.country)
        - Keywords: \(paper.keywords.isEmpty ? "—" : paper.keywords)
        - Limitations: \(paper.limitations.isEmpty ? "—" : paper.limitations)
        """
    }

    private func exportAttachments(for papers: [Paper]) {
        let urls = papers.compactMap { store.pdfURL(for: $0) }
        guard !urls.isEmpty else {
            alertMessage = "No PDF attachments to export."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let targetDirectory = panel.url else { return }

        for sourceURL in urls {
            let destinationURL = uniqueDestinationURL(
                baseDirectory: targetDirectory,
                suggestedName: sourceURL.lastPathComponent
            )
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func exportLitrixArchive() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Papers.litrix"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = litrixImportContentTypes
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        let resolvedDestination = destinationURL.pathExtension.lowercased() == "litrix"
            ? destinationURL
            : destinationURL.appendingPathExtension("litrix")

        do {
            let manifest = LitrixArchiveManifest(
                library: store.currentLibrarySnapshot(),
                settings: settings.exportSnapshotForArchive(),
                metadataPromptDocument: settings.readMetadataPromptDocument()
            )
            try LitrixArchiveService.exportArchive(
                to: resolvedDestination,
                manifest: manifest,
                papersRootURL: store.papersStorageRootURL
            )
            alertMessage = "已导出：\(resolvedDestination.lastPathComponent)"
        } catch {
            alertMessage = "导出 Litrix 失败：\(error.localizedDescription)"
        }
    }

    private func importLitrixArchive(from url: URL) {
        guard let selection = promptLitrixImportSelection() else { return }

        let rollbackLibrary = store.currentLibrarySnapshot()
        let rollbackSettings = settings.exportCurrentSnapshot(includeSecrets: true)
        let rollbackPrompt = settings.readMetadataPromptDocument()

        _ = store.writeImportCheckpoint()
        _ = settings.writeImportCheckpoint()

        do {
            let unpacked = try LitrixArchiveService.unpackArchive(from: url)
            defer {
                LitrixArchiveService.cleanupUnpackedRoot(unpacked.unpackedRoot)
            }

            var resolvedForRemaining: LitrixDuplicateResolution?
            let report = store.importLitrixLibrary(
                unpacked.manifest.library,
                archivePapersDirectory: LitrixArchiveService.papersDirectory(in: unpacked.unpackedRoot),
                selection: selection
            ) { candidate in
                if let resolvedForRemaining {
                    return resolvedForRemaining
                }
                let decision = promptDuplicateResolution(for: candidate)
                if decision.applyToRemaining {
                    resolvedForRemaining = decision.resolution
                }
                return decision.resolution
            }

            if selection.includeSettings, let importedSettings = unpacked.manifest.settings {
                settings.applyImportedSettings(importedSettings, preserveAPIKey: true)
                if let promptText = unpacked.manifest.metadataPromptDocument,
                   !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settings.writeMetadataPromptDocument(promptText)
                }
            }

            var summary = report.summaryText
            if selection.includeSettings, unpacked.manifest.settings != nil {
                summary.append("\n设置：已合并（保留本机 API Key）")
            }
            alertMessage = summary
        } catch {
            store.restoreLibrarySnapshot(rollbackLibrary)
            settings.applyImportedSettings(rollbackSettings, preserveAPIKey: false)
            settings.writeMetadataPromptDocument(rollbackPrompt)
            alertMessage = "导入 Litrix 失败，已回滚：\(error.localizedDescription)"
        }
    }

    private struct DuplicateResolutionDecision {
        var resolution: LitrixDuplicateResolution
        var applyToRemaining: Bool
    }

    private func promptDuplicateResolution(for candidate: LitrixDuplicateCandidate) -> DuplicateResolutionDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "检测到重复文献"
        alert.informativeText = """
        原因：\(candidate.reason.descriptionText)
        现有：\(normalizedTitle(candidate.existingPaper.title))
        导入：\(normalizedTitle(candidate.incomingPaper.title))
        """
        alert.addButton(withTitle: "覆盖")
        alert.addButton(withTitle: "跳过")
        alert.addButton(withTitle: "重命名（2）")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "应用到剩余全部重复项"

        let response = alert.runModal()
        let applyToRemaining = alert.suppressionButton?.state == .on

        let resolution: LitrixDuplicateResolution
        switch response {
        case .alertFirstButtonReturn:
            resolution = .overwrite
        case .alertSecondButtonReturn:
            resolution = .skip
        default:
            resolution = .rename
        }
        return DuplicateResolutionDecision(resolution: resolution, applyToRemaining: applyToRemaining)
    }

    private func promptLitrixImportSelection() -> LitrixImportSelection? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "选择要导入的内容"
        alert.informativeText = "默认全部勾选，可多选。"
        alert.addButton(withTitle: "开始导入")
        alert.addButton(withTitle: "取消")

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let settingsCheckbox = NSButton(checkboxWithTitle: LitrixImportSelectionItem.settings.title, target: nil, action: nil)
        settingsCheckbox.state = .on
        let papersCheckbox = NSButton(checkboxWithTitle: LitrixImportSelectionItem.papers.title, target: nil, action: nil)
        papersCheckbox.state = .on
        let notesCheckbox = NSButton(checkboxWithTitle: LitrixImportSelectionItem.notes.title, target: nil, action: nil)
        notesCheckbox.state = .on
        let attachmentsCheckbox = NSButton(checkboxWithTitle: LitrixImportSelectionItem.attachments.title, target: nil, action: nil)
        attachmentsCheckbox.state = .on

        [settingsCheckbox, papersCheckbox, notesCheckbox, attachmentsCheckbox].forEach(stack.addArrangedSubview)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let selection = LitrixImportSelection(
            includeSettings: settingsCheckbox.state == .on,
            includePapers: papersCheckbox.state == .on,
            includeNotes: notesCheckbox.state == .on,
            includeAttachments: attachmentsCheckbox.state == .on
        )

        let hasAnyEnabled = selection.includeSettings
            || selection.includePapers
            || selection.includeNotes
            || selection.includeAttachments
        guard hasAnyEnabled else {
            alertMessage = "请至少选择一项导入内容。"
            return nil
        }
        return selection
    }

    private func uniqueDestinationURL(baseDirectory: URL, suggestedName: String) -> URL {
        let fileManager = FileManager.default
        var candidate = baseDirectory.appendingPathComponent(suggestedName, isDirectory: false)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let fileName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            candidate = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            index += 1
        }
        return candidate
    }

    private func savePlainText(_ text: String, suggestedFileName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func requestDeleteSelectedPaper() {
        if selectedPaperIDs.count > 1 {
            guard let first = selectedPapers.first else { return }
            if first.isDeleted {
                pendingPermanentDeletePaper = first
                return
            }
            pendingDeletePaper = first
            return
        }
        guard let paper = selectedPaper else { return }
        if paper.isDeleted {
            pendingPermanentDeletePaper = paper
        } else {
            pendingDeletePaper = paper
        }
    }

    private func requestDelete(_ paper: Paper) {
        if paper.isDeleted {
            pendingPermanentDeletePaper = paper
        } else {
            pendingDeletePaper = paper
        }
    }

    private func requestPermanentDelete(_ paper: Paper) {
        pendingPermanentDeletePaper = paper
    }

    private func deletePaper(_ paper: Paper) {
        let idsToDelete: [UUID]
        if selectedPaperIDs.contains(paper.id), selectedPaperIDs.count > 1 {
            idsToDelete = Array(selectedPaperIDs)
        } else {
            idsToDelete = [paper.id]
        }

        for id in idsToDelete {
            store.movePaperToRecentlyDeleted(id: id)
        }

        if let lastInspectedPaperID, idsToDelete.contains(lastInspectedPaperID) {
            self.lastInspectedPaperID = store.scopedPapers(for: .library(.all)).first?.id
        }
        selectSinglePaper(nil)
        alignSelectionWithVisibleResults()
        pendingDeletePaper = nil
    }

    private func restoreDeletedPapers(for paper: Paper) {
        let idsToRestore = targetPaperIDs(for: paper).filter { id in
            store.paper(id: id)?.isDeleted == true
        }
        guard !idsToRestore.isEmpty else { return }

        for id in idsToRestore {
            store.restorePaper(id: id)
        }

        selectSinglePaper(nil)
        alignSelectionWithVisibleResults()
    }

    private func permanentlyDeletePaper(_ paper: Paper) {
        let idsToDelete = targetPaperIDs(for: paper).filter { id in
            store.paper(id: id)?.isDeleted == true
        }
        guard !idsToDelete.isEmpty else {
            pendingPermanentDeletePaper = nil
            return
        }

        store.permanentlyDeletePapers(ids: idsToDelete)

        if let lastInspectedPaperID, idsToDelete.contains(lastInspectedPaperID) {
            self.lastInspectedPaperID = store.scopedPapers(for: .library(.all)).first?.id
        }
        selectSinglePaper(nil)
        alignSelectionWithVisibleResults()
        pendingPermanentDeletePaper = nil
    }

    private func deleteConfirmationMessage(for paper: Paper) -> String {
        let count = pendingDeleteCount(for: paper)
        if count > 1 {
            return localized(
                chinese: "\(count) 篇文献将移入“最近删除”，并保留 \(settings.recentlyDeletedRetentionDays) 天。",
                english: "\(count) papers will move to Recently Deleted and stay there for \(settings.recentlyDeletedRetentionDays) days."
            )
        }

        let title = paper.title.isEmpty ? localized(chinese: "未命名文献", english: "Untitled Paper") : paper.title
        return localized(
            chinese: "“\(title)”将移入“最近删除”，并保留 \(settings.recentlyDeletedRetentionDays) 天。",
            english: "“\(title)” will move to Recently Deleted and stay there for \(settings.recentlyDeletedRetentionDays) days."
        )
    }

    private func permanentDeleteConfirmationMessage(for paper: Paper) -> String {
        let count = pendingPermanentDeleteCount(for: paper)
        if count > 1 {
            return localized(
                chinese: "将彻底删除 \(count) 篇文献及其附件、笔记、图片等所有相关文件。此操作无法撤销。",
                english: "\(count) papers and all related attachments, notes, images, and files will be permanently deleted. This cannot be undone."
            )
        }

        let title = paper.title.isEmpty ? localized(chinese: "未命名文献", english: "Untitled Paper") : paper.title
        return localized(
            chinese: "将彻底删除“\(title)”及其附件、笔记、图片等所有相关文件。此操作无法撤销。",
            english: "“\(title)” and all related attachments, notes, images, and files will be permanently deleted. This cannot be undone."
        )
    }

    private func pendingDeleteCount(for paper: Paper) -> Int {
        if selectedPaperIDs.contains(paper.id), selectedPaperIDs.count > 1 {
            return selectedPaperIDs.count
        }
        return 1
    }

    private func pendingPermanentDeleteCount(for paper: Paper) -> Int {
        targetPaperIDs(for: paper)
            .filter { store.paper(id: $0)?.isDeleted == true }
            .count
    }

    private func presentRightPane(_ mode: RightPaneMode) {
        if isInspectorPanelOnscreen, rightPaneMode == mode {
            hideRightPane()
            return
        }
        showRightPane(mode)
    }

    private func showRightPane(_ mode: RightPaneMode) {
        rightPaneMode = mode
        showRightPane()
    }

    private func toggleDetailsPaneVisibility() {
        presentRightPane(.details)
    }

    private func showRightPane() {
        guard !isInspectorPanelOnscreen else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            isInspectorPanelOnscreen = true
        }
        reassertWindowTitle()
    }

    private func hideRightPane() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isInspectorPanelOnscreen = false
        }
        reassertWindowTitle()
    }

    private func toggleSidebarVisibility() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        reassertWindowTitle()
    }

    private func applyWindowTitle(to window: NSWindow) {
        let title = currentNavigationTitle
        if window.title != title {
            window.title = title
        }
    }

    private func reassertWindowTitle() {
        guard let window = NSApp.keyWindow else { return }
        reassertWindowTitle(on: window)
    }

    private func reassertWindowTitle(on window: NSWindow) {
        let title = currentNavigationTitle
        DispatchQueue.main.async {
            if window.title != title {
                window.title = title
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if window.title != title {
                window.title = title
            }
        }
    }

    private func revealSearchFieldAndFocus() {
        toolbarSearchFocusRequest = UUID()
    }

    private func openNoteEditorWindow() {
        guard let selectedPaperID else {
            alertMessage = localized(chinese: "请先选中文献。", english: "Please select a paper first.")
            return
        }
        NoteEditorWindowManager.shared.present(for: selectedPaperID, store: store, settings: settings)
    }

    private func copyInTextCitationForSelectedPaper() {
        guard let paper = selectedPaper else { return }
        let citation = renderedCitation(from: settings.inTextCitationTemplate, for: paper)
        copyTextToPasteboard(citation)
    }

    private func copyReferenceCitationForSelectedPaper() {
        guard let paper = selectedPaper else { return }
        let citation = renderedCitation(from: settings.referenceCitationTemplate, for: paper)
        copyTextToPasteboard(citation)
    }

    private var quickCitationResults: [Paper] {
        quickCitationResultIDs.compactMap { store.paper(id: $0) }
    }

    private var quickCitationSelectedPaper: Paper? {
        if let quickCitationHighlightedPaperID,
           let paper = store.paper(id: quickCitationHighlightedPaperID) {
            return paper
        }
        return quickCitationResults.first
    }

    private func presentQuickCitationOverlay() {
        quickCitationQuery = ""
        quickCitationResultIDs = []
        quickCitationHighlightedPaperID = nil
        quickCitationStatusText = localized(
            chinese: "输入关键词后按回车搜索，方向键选择，回车插入引用。",
            english: "Type query and press Enter, use arrow keys to choose, Enter again to insert."
        )
        withAnimation(.easeInOut(duration: 0.18)) {
            isQuickCitationOverlayPresented = true
        }
        DispatchQueue.main.async {
            isQuickCitationFieldFocused = true
        }
    }

    private func dismissQuickCitationOverlay() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isQuickCitationOverlayPresented = false
        }
        isQuickCitationFieldFocused = false
    }

    private func runQuickCitationSearch() {
        let query = quickCitationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.scopedPapers(for: .library(.all))
        let searched = Self.applySearchQuery(
            to: base,
            searchText: query,
            searchField: nil
        )

        let sorted = searched.sorted {
            $0.addedAtMilliseconds > $1.addedAtMilliseconds
        }
        let resultIDs = Array(sorted.prefix(36)).map(\.id)
        quickCitationResultIDs = resultIDs
        if resultIDs.contains(where: { $0 == quickCitationHighlightedPaperID }) {
            // Keep current selection when still visible.
        } else {
            quickCitationHighlightedPaperID = resultIDs.first
        }

        if resultIDs.isEmpty {
            quickCitationStatusText = localized(
                chinese: "未找到匹配文献。",
                english: "No matching papers found."
            )
        } else {
            quickCitationStatusText = localized(
                chinese: "已匹配 \(resultIDs.count) 条文献。",
                english: "\(resultIDs.count) papers matched."
            )
        }
    }

    private func moveQuickCitationSelection(offset: Int) {
        let ids = quickCitationResultIDs
        guard !ids.isEmpty else { return }
        guard offset != 0 else { return }

        let currentIndex: Int
        if let quickCitationHighlightedPaperID,
           let index = ids.firstIndex(of: quickCitationHighlightedPaperID) {
            currentIndex = index
        } else {
            currentIndex = 0
        }

        let nextIndex = max(0, min(ids.count - 1, currentIndex + offset))
        quickCitationHighlightedPaperID = ids[nextIndex]
    }

    private func applyQuickCitation(_ paper: Paper) {
        let referenceTemplate = settings.referenceCitationTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = referenceTemplate.isEmpty ? settings.inTextCitationTemplate : settings.referenceCitationTemplate
        let citation = renderedCitation(from: template, for: paper)
        copyTextToPasteboard(citation)
        selectSinglePaper(paper.id)
        alertMessage = localized(
            chinese: "快速引用已复制到剪贴板。安装 Word/WPS 插件后可直接插入脚注。",
            english: "Quick citation copied to clipboard. Install the Word/WPS plugin to insert footnotes directly."
        )
        dismissQuickCitationOverlay()
    }

    private func renderedCitation(from template: String, for paper: Paper) -> String {
        let author = paper.authors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : paper.authors
        let year = paper.year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "n.d." : paper.year
        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Paper" : paper.title
        let journal = paper.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Source" : paper.source
        let volume = paper.volume.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = paper.issue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pages = paper.pages.trimmingCharacters(in: .whitespacesAndNewlines)
        let doi = paper.doi.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAuthors = parseAuthorList(from: author)
        let apaInTextAuthors = formatAPAInTextAuthors(parsedAuthors)
        let apaReferenceAuthors = formatAPAReferenceAuthors(parsedAuthors)
        let gbt7714Authors = formatGBT7714Authors(parsedAuthors, fallback: author)
        let renderedAuthor = settings.citationPreset == .gbt7714 ? gbt7714Authors : author

        var result = template
        let replacements: [(String, String)] = [
            ("author", renderedAuthor),
            ("apaInTextAuthors", apaInTextAuthors),
            ("apaReferenceAuthors", apaReferenceAuthors),
            ("gbt7714Authors", gbt7714Authors),
            ("year", year),
            ("title", title),
            ("journal", journal),
            ("volume", volume),
            ("number", number),
            ("pages", pages),
            ("doi", doi),
            ("page", pages)
        ]

        for (token, value) in replacements {
            result = result.replacingOccurrences(of: "{{\(token)}}", with: value)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseAuthorList(from raw: String) -> [String] {
        AuthorNameParser.parse(raw: raw)
    }

    private func formatAPAInTextAuthors(_ authors: [String]) -> String {
        guard !authors.isEmpty else { return "Unknown" }
        let surnames = authors.map(apaSurname(from:))
        if surnames.count == 1 {
            return surnames[0]
        }
        if surnames.count == 2 {
            return "\(surnames[0]) & \(surnames[1])"
        }
        return "\(surnames[0]) et al."
    }

    private func formatAPAReferenceAuthors(_ authors: [String]) -> String {
        guard !authors.isEmpty else { return "Unknown" }
        let formatted = authors.map(apaReferenceAuthor(from:))
        if formatted.count == 1 {
            return formatted[0]
        }
        if formatted.count == 2 {
            return "\(formatted[0]), & \(formatted[1])"
        }
        let head = formatted.dropLast().joined(separator: ", ")
        return "\(head), & \(formatted.last ?? "")"
    }

    private func formatGBT7714Authors(_ authors: [String], fallback: String) -> String {
        let cleaned = authors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return fallback.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cleaned.count > 3 else { return cleaned.joined(separator: ", ") }

        let prefix = cleaned.prefix(3).joined(separator: ", ")
        let suffix = cleaned.contains(where: containsCJK) ? "等." : "et al."
        return "\(prefix), \(suffix)"
    }

    private func apaSurname(from author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }
        if trimmed.contains(",") {
            return trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? trimmed
        }
        if containsCJK(trimmed) {
            return trimmed
        }
        let tokens = trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        return tokens.last ?? trimmed
    }

    private func apaReferenceAuthor(from author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            let surname = parts.first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed
            guard parts.count > 1 else { return surname }
            let givenRaw = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let initials = normalizedInitials(from: givenRaw)
            return initials.isEmpty ? surname : "\(surname), \(initials)"
        }

        if containsCJK(trimmed) {
            return trimmed
        }

        let parts = trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard parts.count > 1 else { return trimmed }
        let surname = parts.last ?? trimmed
        let givenNames = parts.dropLast().joined(separator: " ")
        let initials = normalizedInitials(from: givenNames)
        return initials.isEmpty ? surname : "\(surname), \(initials)"
    }

    private func normalizedInitials(from text: String) -> String {
        let clean = text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else { return "" }

        let words = clean.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let initials = words.compactMap { word -> String? in
            guard let first = word.unicodeScalars.first else { return nil }
            if CharacterSet.letters.contains(first) {
                return "\(String(first).uppercased())."
            }
            return nil
        }
        return initials.joined(separator: " ")
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyPaperAddress(for contextPaper: Paper) {
        let addresses = targetPapers(for: contextPaper)
            .map(paperAddressString(for:))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !addresses.isEmpty else { return }
        copyTextToPasteboard(addresses.joined(separator: "\n"))
    }

    private func revealPaperInFinder(for contextPaper: Paper) {
        let urls = targetPapers(for: contextPaper).compactMap { paper -> URL? in
            if let url = store.defaultOpenPDFURL(for: paper),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            return store.ensurePaperDirectory(for: paper.id)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func paperAddressString(for paper: Paper) -> String {
        if let url = store.pdfURL(for: paper), FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return "litrix://paper/\(paper.id.uuidString)"
    }

    private func quickNumberForKeyCode(_ keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }

    private func applyQuickTag(number: Int) {
        if !selectedPaperIDs.isEmpty {
            applyQuickTag(number: number, to: Array(selectedPaperIDs))
            return
        }
        guard let paper = selectedPaper else { return }
        applyQuickTag(number: number, to: targetPaperIDs(for: paper))
    }

    private func applyQuickTag(number: Int, for paper: Paper) {
        applyQuickTag(number: number, to: targetPaperIDs(for: paper))
    }

    private func applyQuickTag(number: Int, to paperIDs: [UUID]) {
        guard let tag = settings.tagQuickNumberMap.first(where: { $0.value == number })?.key else { return }
        setTag(tag, assigned: shouldAssignTag(tag, forPaperIDs: paperIDs), forPaperIDs: paperIDs)
    }

    private func tagMenuLabel(for tag: String) -> String {
        if let number = settings.quickNumber(forTag: tag) {
            return "\(number). \(tag)"
        }
        return tag
    }

    private func quickNumberMenuTitle(number: Int) -> String {
        if let tag = settings.tagQuickNumberMap.first(where: { $0.value == number })?.key {
            return "\(number). \(tag)"
        }
        return "\(number). Unassigned"
    }

    private func selectRelativePaper(offset: Int) {
        guard !sortedPapers.isEmpty else { return }

        guard let selectedPaperID,
              let currentIndex = sortedPapers.firstIndex(where: { $0.id == selectedPaperID }) else {
            selectSinglePaper(sortedPapers.first?.id)
            return
        }

        let nextIndex = max(0, min(sortedPapers.count - 1, currentIndex + offset))
        selectSinglePaper(sortedPapers[nextIndex].id)
    }

    private func beginTaxonomyCreation(
        kind: TaxonomyKind,
        relation: TaxonomyCreationRelation,
        referencePath: String?
    ) {
        taxonomyDraftName = ""
        taxonomyCreationContext = TaxonomyCreationContext(
            kind: kind,
            relation: relation,
            referencePath: referencePath
        )
    }

    private func saveTaxonomy(context: TaxonomyCreationContext) {
        let name = taxonomyDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            taxonomyDraftName = ""
            taxonomyCreationContext = nil
            return
        }

        switch context.relation {
        case .root:
            store.createTaxonomyItem(kind: context.kind, named: name)
        case .parent:
            if let referencePath = context.referencePath {
                store.createTaxonomyParent(kind: context.kind, named: name, above: referencePath)
            }
        case .sibling:
            if let referencePath = context.referencePath {
                store.createTaxonomySibling(kind: context.kind, named: name, relativeTo: referencePath)
            }
        case .child:
            if let referencePath = context.referencePath {
                store.createTaxonomyChild(kind: context.kind, named: name, under: referencePath)
            }
        }

        taxonomyDraftName = ""
        taxonomyCreationContext = nil
    }

    private func beginInlineCollectionCreation() {
        cancelInlineRename()
        taxonomyDraftName = ""
        isCreatingCollectionInline = true
        DispatchQueue.main.async {
            isNewCollectionFieldFocused = true
        }
    }

    private func saveInlineCollection() {
        let trimmed = taxonomyDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelInlineCollectionCreation()
            return
        }

        store.createCollection(named: trimmed)
        taxonomyDraftName = ""
        isCreatingCollectionInline = false
        isNewCollectionFieldFocused = false
    }

    private func cancelInlineCollectionCreation() {
        taxonomyDraftName = ""
        isCreatingCollectionInline = false
        isNewCollectionFieldFocused = false
    }

    private func beginInlineCollectionRename(_ collection: String) {
        editingTagName = nil
        editingCollectionName = collection
        inlineRenameDraft = TaxonomyHierarchy.leafName(of: collection)
        DispatchQueue.main.async {
            isInlineRenameFocused = true
        }
    }

    private func beginInlineTagRename(_ tag: String) {
        editingCollectionName = nil
        editingTagName = tag
        inlineRenameDraft = TaxonomyHierarchy.leafName(of: tag)
        DispatchQueue.main.async {
            isInlineRenameFocused = true
        }
    }

    private func saveInlineCollectionRename(original: String) {
        let destination = TaxonomyHierarchy.path(parent: TaxonomyHierarchy.parentPath(of: original), name: inlineRenameDraft)
        defer { cancelInlineRename() }
        guard !destination.isEmpty else { return }
        guard destination != original else { return }
        store.renameCollection(oldName: original, newName: destination)
        if case .collection(let selectedCollection) = sidebarSelection, selectedCollection == original {
            sidebarSelection = .collection(destination)
        }
    }

    private func saveInlineTagRename(original: String) {
        let destination = TaxonomyHierarchy.path(parent: TaxonomyHierarchy.parentPath(of: original), name: inlineRenameDraft)
        defer { cancelInlineRename() }
        guard !destination.isEmpty else { return }
        guard destination != original else { return }
        store.renameTag(oldName: original, newName: destination)
        settings.remapTagQuickNumber(from: original, to: destination)
        if case .tag(let selectedTag) = sidebarSelection, selectedTag == original {
            sidebarSelection = .tag(destination)
        }
    }

    private func cancelInlineRename() {
        editingCollectionName = nil
        editingTagName = nil
        inlineRenameDraft = ""
        isInlineRenameFocused = false
    }

    private func beginTaxonomyEdit(kind: TaxonomyKind, path: String) {
        cancelInlineRename()
        let metadata = store.taxonomyMetadata(for: path, kind: kind)
        taxonomyEditTitle = TaxonomyHierarchy.leafName(of: path)
        taxonomyEditDescription = metadata.itemDescription
        taxonomyEditIconSystemName = normalizedTaxonomyIcon(metadata.iconSystemName, kind: kind)
        taxonomyEditColor = Color(hexString: metadata.colorHex)
            ?? (kind == .tag ? tagColor(for: path) : .secondary)
        taxonomyEditTarget = TaxonomyEditTarget(kind: kind, path: path)
    }

    private func saveTaxonomyEdit(_ target: TaxonomyEditTarget) {
        let colorHex = taxonomyEditColor.hexRGB ?? ""
        let metadata = TaxonomyItemMetadata(
            itemDescription: taxonomyEditDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            iconSystemName: normalizedTaxonomyIcon(taxonomyEditIconSystemName, kind: target.kind),
            colorHex: colorHex
        )
        guard let destination = store.updateTaxonomyItem(
            kind: target.kind,
            path: target.path,
            title: taxonomyEditTitle,
            metadata: metadata
        ) else {
            NSSound.beep()
            return
        }

        if target.kind == .tag, target.path != destination {
            settings.remapTagQuickNumber(from: target.path, to: destination)
        }
        switch target.kind {
        case .collection:
            if case .collection(let selectedCollection) = sidebarSelection, selectedCollection == target.path {
                sidebarSelection = .collection(destination)
            }
        case .tag:
            if case .tag(let selectedTag) = sidebarSelection, selectedTag == target.path {
                sidebarSelection = .tag(destination)
            }
        }
        taxonomyEditTarget = nil
    }

    private func normalizedTaxonomyIcon(_ icon: String, kind: TaxonomyKind) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return kind == .collection ? "folder" : "circle.fill"
    }

    private func taxonomyIcon(for path: String, kind: TaxonomyKind, hasChildren: Bool) -> String? {
        let metadata = store.taxonomyMetadata(for: path, kind: kind)
        let icon = normalizedTaxonomyIcon(metadata.iconSystemName, kind: kind)
        if kind == .collection, icon == "folder", hasChildren {
            return "folder.fill"
        }
        if kind == .tag, icon == "circle.fill" {
            return nil
        }
        return icon
    }

    private func taxonomyIconTint(for path: String, kind: TaxonomyKind) -> Color? {
        let metadata = store.taxonomyMetadata(for: path, kind: kind)
        return Color(hexString: metadata.colorHex)
    }

    private func taxonomyDragItemProvider(kind: TaxonomyKind, path: String) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = "\(kind.rawValue)\n\(path)"
        provider.registerDataRepresentation(
            forTypeIdentifier: litrixTaxonomyItemUTType.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        provider.registerObject(NSString(string: path), visibility: .ownProcess)
        return provider
    }

    private func beginInlineRenameFromSidebarSelection() -> Bool {
        switch sidebarSelection {
        case .collection(let name):
            beginInlineCollectionRename(name)
            return true
        case .tag(let name):
            beginInlineTagRename(name)
            return true
        case .library:
            return false
        }
    }

    private func targetPaperIDs(for contextPaper: Paper) -> [UUID] {
        if selectedPaperIDs.contains(contextPaper.id) {
            let orderedVisibleIDs = sortedVisiblePaperIDs(from: selectedPaperIDs)
            if !orderedVisibleIDs.isEmpty {
                return orderedVisibleIDs
            }
        }
        return [contextPaper.id]
    }

    private func targetPapers(for contextPaper: Paper) -> [Paper] {
        targetPaperIDs(for: contextPaper).compactMap { store.paper(id: $0) }
    }

    private func resolvedPaper(_ paper: Paper) -> Paper {
        store.paper(id: paper.id) ?? paper
    }

    private func openColumnSettings(for column: PaperTableColumn) {
        switch column {
        case .abstractText:
            isAbstractColumnSettingsPresented = true
        case .title:
            isTitleColumnSettingsPresented = true
        case .impactFactor:
            isImpactFactorColumnSettingsPresented = true
        case .addedTime, .editedTime:
            isTimeColumnSettingsPresented = true
        case .tags:
            isTagColumnSettingsPresented = true
        default:
            return
        }
    }

    private func markAbstractDisplayNeedsRefresh() {
        abstractDisplayRevision &+= 1
        paperTableRefreshNonce = UUID()
    }

    private func markTitleDisplayNeedsRefresh() {
        paperTableRefreshNonce = UUID()
    }

    private func markPaperDisplayNeedsRefresh() {
        paperTableRefreshNonce = UUID()
    }

    private func containsHanCharacters(_ value: String) -> Bool {
        value.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private func normalizedTitleValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func titlePlaceholder(for language: AbstractDisplayLanguage) -> String {
        switch language {
        case .original:
            return localized(chinese: "无标题", english: "Untitled Paper")
        case .chinese:
            return localized(chinese: "正在生成中文标题…", english: "Generating Chinese title…")
        case .english:
            return localized(chinese: "正在生成英文标题…", english: "Generating English title…")
        }
    }

    private func titleTranslationSource(for paper: Paper, targetLanguage: AbstractDisplayLanguage) -> String? {
        let original = normalizedTitleValue(paper.title)
        let chinese = normalizedTitleValue(paper.chineseTitle)
        let english = normalizedTitleValue(paper.englishTitle)

        switch targetLanguage {
        case .original:
            return nil
        case .chinese:
            if !original.isEmpty, !containsHanCharacters(original) {
                return original
            }
            return english.isEmpty ? nil : english
        case .english:
            if !original.isEmpty, containsHanCharacters(original) {
                return original
            }
            return chinese.isEmpty ? nil : chinese
        }
    }

    private func displayedTitlePresentation(for paper: Paper) -> TitleColumnPresentation {
        let currentPaper = resolvedPaper(paper)
        let original = normalizedTitleValue(currentPaper.title)
        let chinese = normalizedTitleValue(currentPaper.chineseTitle)
        let english = normalizedTitleValue(currentPaper.englishTitle)
        let originalIsChinese = containsHanCharacters(original)

        switch settings.titleDisplayLanguage {
        case .original:
            return TitleColumnPresentation(
                text: original.isEmpty ? titlePlaceholder(for: .original) : original,
                isPlaceholder: original.isEmpty,
                translationRequest: nil
            )
        case .chinese:
            if originalIsChinese, !original.isEmpty {
                return TitleColumnPresentation(text: original, isPlaceholder: false, translationRequest: nil)
            }
            if !chinese.isEmpty {
                return TitleColumnPresentation(text: chinese, isPlaceholder: false, translationRequest: nil)
            }
        case .english:
            if !originalIsChinese, !original.isEmpty {
                return TitleColumnPresentation(text: original, isPlaceholder: false, translationRequest: nil)
            }
            if !english.isEmpty {
                return TitleColumnPresentation(text: english, isPlaceholder: false, translationRequest: nil)
            }
        }

        let request = TitleTranslationRequest(
            paperID: currentPaper.id,
            language: settings.titleDisplayLanguage
        )
        if titleTranslationFailedRequests.contains(request) {
            return TitleColumnPresentation(text: "—", isPlaceholder: true, translationRequest: nil)
        }

        guard titleTranslationSource(for: currentPaper, targetLanguage: settings.titleDisplayLanguage) != nil else {
            return TitleColumnPresentation(text: "—", isPlaceholder: true, translationRequest: nil)
        }

        return TitleColumnPresentation(
            text: titlePlaceholder(for: settings.titleDisplayLanguage),
            isPlaceholder: true,
            translationRequest: request
        )
    }

    private func ensureTitleTranslationIfNeeded(_ request: TitleTranslationRequest) {
        guard request.language != .original else { return }
        guard !titleTranslationRequestsInFlight.contains(request) else { return }
        guard !titleTranslationFailedRequests.contains(request) else { return }
        guard let paper = store.paper(id: request.paperID) else { return }
        guard let sourceText = titleTranslationSource(for: paper, targetLanguage: request.language) else { return }

        titleTranslationRequestsInFlight.insert(request)
        markTitleDisplayNeedsRefresh()

        Task {
            do {
                let translation = try await MetadataEnrichmentService.translateTitle(
                    apiProvider: settings.resolvedAPIProvider,
                    apiEndpoint: settings.resolvedAPIEndpoint,
                    apiKey: settings.resolvedAPIKey,
                    model: settings.resolvedModel,
                    thinkingEnabled: settings.resolvedThinkingEnabled,
                    text: sourceText,
                    targetLanguage: request.language
                )

                await MainActor.run {
                    titleTranslationRequestsInFlight.remove(request)
                    titleTranslationFailedRequests.remove(request)
                    guard var updatedPaper = store.paper(id: request.paperID) else {
                        markTitleDisplayNeedsRefresh()
                        return
                    }

                    switch request.language {
                    case .chinese:
                        if normalizedTitleValue(updatedPaper.chineseTitle).isEmpty {
                            updatedPaper.chineseTitle = translation
                            store.updatePaper(updatedPaper)
                            refreshPapersImmediately([request.paperID], alignSelection: false)
                        }
                    case .english:
                        if normalizedTitleValue(updatedPaper.englishTitle).isEmpty {
                            updatedPaper.englishTitle = translation
                            store.updatePaper(updatedPaper)
                            refreshPapersImmediately([request.paperID], alignSelection: false)
                        }
                    case .original:
                        break
                    }

                    markTitleDisplayNeedsRefresh()
                }
            } catch {
                await MainActor.run {
                    titleTranslationRequestsInFlight.remove(request)
                    titleTranslationFailedRequests.insert(request)
                    markTitleDisplayNeedsRefresh()
                }
            }
        }
    }

    private func normalizedAbstractValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOriginalAbstractChinese(_ paper: Paper) -> Bool {
        containsHanCharacters(normalizedAbstractValue(paper.abstractText))
    }

    private func abstractTranslationSource(for paper: Paper, targetLanguage: AbstractDisplayLanguage) -> String? {
        let original = normalizedAbstractValue(paper.abstractText)
        let chinese = normalizedAbstractValue(paper.chineseAbstract)
        let english = normalizedAbstractValue(paper.englishAbstract)

        switch targetLanguage {
        case .original:
            return nil
        case .chinese:
            if !original.isEmpty, !containsHanCharacters(original) {
                return original
            }
            return english.isEmpty ? nil : english
        case .english:
            if !original.isEmpty, containsHanCharacters(original) {
                return original
            }
            return chinese.isEmpty ? nil : chinese
        }
    }

    private func abstractPlaceholder(for language: AbstractDisplayLanguage) -> String {
        switch language {
        case .original:
            return "—"
        case .chinese:
            return localized(chinese: "正在生成中文摘要…", english: "Generating Chinese abstract…")
        case .english:
            return localized(chinese: "正在生成英文摘要…", english: "Generating English abstract…")
        }
    }

    private func displayedAbstractPresentation(for paper: Paper) -> AbstractColumnPresentation {
        let currentPaper = resolvedPaper(paper)
        let original = normalizedAbstractValue(currentPaper.abstractText)
        let chinese = normalizedAbstractValue(currentPaper.chineseAbstract)
        let english = normalizedAbstractValue(currentPaper.englishAbstract)
        let originalIsChinese = containsHanCharacters(original)

        switch settings.abstractDisplayLanguage {
        case .original:
            return AbstractColumnPresentation(
                text: original.isEmpty ? "—" : original,
                translationRequest: nil
            )
        case .chinese:
            if originalIsChinese, !original.isEmpty {
                return AbstractColumnPresentation(text: original, translationRequest: nil)
            }
            if !chinese.isEmpty {
                return AbstractColumnPresentation(text: chinese, translationRequest: nil)
            }
        case .english:
            if !originalIsChinese, !original.isEmpty {
                return AbstractColumnPresentation(text: original, translationRequest: nil)
            }
            if !english.isEmpty {
                return AbstractColumnPresentation(text: english, translationRequest: nil)
            }
        }

        let request = AbstractTranslationRequest(
            paperID: currentPaper.id,
            language: settings.abstractDisplayLanguage
        )
        if abstractTranslationFailedRequests.contains(request) {
            return AbstractColumnPresentation(
                text: "—",
                translationRequest: nil
            )
        }

        if abstractTranslationSource(for: currentPaper, targetLanguage: settings.abstractDisplayLanguage) != nil {
            return AbstractColumnPresentation(
                text: abstractPlaceholder(for: settings.abstractDisplayLanguage),
                translationRequest: request
            )
        }

        return AbstractColumnPresentation(
            text: "—",
            translationRequest: nil
        )
    }

    private func ensureAbstractTranslationIfNeeded(_ request: AbstractTranslationRequest) {
        guard request.language != .original else { return }
        guard !abstractTranslationRequestsInFlight.contains(request) else { return }
        guard !abstractTranslationFailedRequests.contains(request) else { return }
        guard let paper = store.paper(id: request.paperID) else { return }
        guard let sourceText = abstractTranslationSource(for: paper, targetLanguage: request.language) else { return }

        abstractTranslationRequestsInFlight.insert(request)
        markAbstractDisplayNeedsRefresh()

        Task {
            do {
                let translation = try await MetadataEnrichmentService.translateAbstract(
                    apiProvider: settings.resolvedAPIProvider,
                    apiEndpoint: settings.resolvedAPIEndpoint,
                    apiKey: settings.resolvedAPIKey,
                    model: settings.resolvedModel,
                    thinkingEnabled: settings.resolvedThinkingEnabled,
                    text: sourceText,
                    targetLanguage: request.language
                )

                await MainActor.run {
                    abstractTranslationRequestsInFlight.remove(request)
                    abstractTranslationFailedRequests.remove(request)
                    guard var updatedPaper = store.paper(id: request.paperID) else {
                        markAbstractDisplayNeedsRefresh()
                        return
                    }

                    switch request.language {
                    case .chinese:
                        if normalizedAbstractValue(updatedPaper.chineseAbstract).isEmpty {
                            updatedPaper.chineseAbstract = translation
                            store.updatePaper(updatedPaper)
                            refreshPapersImmediately([request.paperID], alignSelection: false)
                        }
                    case .english:
                        if normalizedAbstractValue(updatedPaper.englishAbstract).isEmpty {
                            updatedPaper.englishAbstract = translation
                            store.updatePaper(updatedPaper)
                            refreshPapersImmediately([request.paperID], alignSelection: false)
                        }
                    case .original:
                        break
                    }

                    markAbstractDisplayNeedsRefresh()
                }
            } catch {
                await MainActor.run {
                    abstractTranslationRequestsInFlight.remove(request)
                    abstractTranslationFailedRequests.insert(request)
                    markAbstractDisplayNeedsRefresh()
                    print("摘要翻译失败(\(request.paperID), \(request.language.rawValue)): \(error.localizedDescription)")
                }
            }
        }
    }

    @ViewBuilder
    private func defaultOpenPDFMenu(for paper: Paper) -> some View {
        Menu(localized(chinese: "修改默认打开文献", english: "Change Default Open Paper")) {
            let availablePDFFileNames = store.availablePDFFileNames(for: paper)
            if availablePDFFileNames.isEmpty {
                Text(localized(chinese: "当前文件夹没有可选文献文件", english: "No Files Available"))
            } else {
                ForEach(availablePDFFileNames, id: \.self) { fileName in
                    Button {
                        _ = store.setPreferredOpenPDFFileName(fileName, forPaperID: paper.id)
                    } label: {
                        if store.defaultOpenPDFURL(for: paper)?.lastPathComponent == fileName {
                            Label(fileName, systemImage: "checkmark")
                        } else {
                            Text(fileName)
                        }
                    }
                }
            }
        }
    }

    private func translateViaPDF2ZH(for contextPaper: Paper) {
        let tasks = targetPapers(for: contextPaper).compactMap { paper -> (Paper, URL)? in
            guard let url = store.defaultOpenPDFURL(for: paper),
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return (paper, url)
        }

        guard !tasks.isEmpty else {
            alertMessage = localized(chinese: "所选文献没有可翻译的 PDF。", english: "No translatable PDF was found for the selected paper.")
            return
        }

        let apiKey = settings.resolvedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            alertMessage = localized(chinese: "请先在设置里填写 API Key。", english: "Configure the API key in Settings first.")
            return
        }

        let model = settings.resolvedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            alertMessage = localized(chinese: "请先在设置里填写模型名称。", english: "Configure the model name in Settings first.")
            return
        }

        guard let activationLines = settings.pdf2zhActivationShellLines() else {
            alertMessage = localized(chinese: "请先在 Settings 的 PDF2ZH 页完成环境配置。", english: "Configure the PDF2ZH environment in Settings first.")
            return
        }

        let baseURL = settings.resolvedPDF2ZHBaseURL
        guard !baseURL.isEmpty else {
            alertMessage = localized(chinese: "当前 API Endpoint 无法转换为 pdf2zh 所需的 Base URL。", english: "The current API endpoint cannot be converted to a pdf2zh base URL.")
            return
        }

        let taskPapers = tasks.map(\.0)
        let requestTime = Date()
        translationPlannedTasks = makeTaskStatusEntries(from: taskPapers, timestamp: requestTime)
        let jobs = tasks.map { task in
            makePDF2ZHTranslationJob(
                paper: task.0,
                sourceURL: task.1,
                activationLines: activationLines,
                baseURL: baseURL,
                model: model,
                enableThinking: settings.resolvedThinkingEnabled,
                enqueuedAt: requestTime
            )
        }
        enqueuePDF2ZHTranslationJobs(jobs)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func makePDF2ZHTranslationJob(
        paper: Paper,
        sourceURL: URL,
        activationLines: [String],
        baseURL: String,
        model: String,
        enableThinking: Bool,
        enqueuedAt: Date
    ) -> PDF2ZHTranslationJob {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return PDF2ZHTranslationJob(
            paperID: paper.id,
            title: normalizedTitle(paper.title),
            sourceURL: sourceURL,
            translatedURL: directory.appendingPathComponent("\(stem)-zh.pdf", isDirectory: false),
            outputURL: directory.appendingPathComponent("\(stem)-dual.pdf", isDirectory: false),
            activationLines: activationLines,
            baseURL: baseURL,
            model: model,
            enableThinking: enableThinking,
            enqueuedAt: enqueuedAt
        )
    }

    private func enqueuePDF2ZHTranslationJobs(_ jobs: [PDF2ZHTranslationJob]) {
        var added = false
        for job in jobs {
            guard activeTranslationJobs[job.paperID] == nil,
                  !translationQueue.contains(where: { $0.paperID == job.paperID }) else {
                continue
            }
            translationQueue.append(job)
            translationQueuedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: job.paperID,
                    title: job.title,
                    timestamp: job.enqueuedAt,
                    progress: 0
                ),
                into: translationQueuedTasks,
                limit: 200
            )
            translationFailedTasks = removeTaskEntry(for: job.paperID, from: translationFailedTasks)
            added = true
        }

        guard added else {
            alertMessage = localized(chinese: "所选文献已在翻译队列中。", english: "The selected paper is already in the translation queue.")
            return
        }

        isTranslationQueuePaused = false
        paperTableRefreshNonce = UUID()
        pumpPDF2ZHTranslationQueue()
    }

    private func pumpPDF2ZHTranslationQueue() {
        guard !isTranslationQueuePaused else { return }
        let limit = max(1, settings.pdf2zhMaxConcurrentTasks)
        while activeTranslationJobs.count < limit, !translationQueue.isEmpty {
            let job = translationQueue.removeFirst()
            startPDF2ZHTranslationJob(job)
        }
    }

    private func startPDF2ZHTranslationJob(_ job: PDF2ZHTranslationJob) {
        activeTranslationJobs[job.paperID] = job
        translationQueuedTasks = removeTaskEntry(for: job.paperID, from: translationQueuedTasks)
        translationProgressByPaperID[job.paperID] = 0.06
        paperTableRefreshNonce = UUID()

        translationJobTasks[job.paperID]?.cancel()
        translationJobTasks[job.paperID] = Task { @MainActor in
            let result = await runPDF2ZHTranslation(job)
            finishPDF2ZHTranslationJob(job, result: result)
        }
    }

    private func runPDF2ZHTranslation(_ job: PDF2ZHTranslationJob) async -> PDF2ZHRunResult {
        let apiKey = settings.resolvedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return PDF2ZHRunResult(succeeded: false, message: localized(chinese: "API Key 为空。", english: "API key is empty."))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh", isDirectory: false)
        process.arguments = ["-lc", makePDF2ZHBackgroundCommand(for: job)]

        var environment = ProcessInfo.processInfo.environment
        environment["OPENAI_BASE_URL"] = job.baseURL
        environment["OPENAI_API_KEY"] = apiKey
        environment["PDF2ZH_OPENAI_ENABLE_THINKING"] = job.enableThinking ? "true" : "false"
        environment["OPENAI_TIMEOUT"] = "120"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let logURL = pdf2zhLogURL(for: job.sourceURL)
        let logHandle = makePDF2ZHLogHandle(at: logURL)
        let monitor = PDF2ZHRunMonitor()
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            try? logHandle.write(contentsOf: data)

            guard let text = String(data: data, encoding: .utf8) else {
                monitor.recordActivity(progress: nil)
                return
            }
            let parsedProgress = Self.parsePDF2ZHProgress(from: text)
            monitor.recordActivity(progress: parsedProgress)
            guard let parsedProgress else { return }
            Task { @MainActor in
                updatePDF2ZHProgress(for: job, parsedProgress: parsedProgress)
            }
        }

        activeTranslationProcesses[job.paperID] = process
        let progressTask = startPDF2ZHProgressSimulation(for: job)
        let watchdogTask = startPDF2ZHWatchdog(for: job, process: process, monitor: monitor)
        let startedAt = Date()

        var launchError: Error?
        let exitCode = await withCheckedContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                continuation.resume(returning: terminatedProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                launchError = error
                continuation.resume(returning: Int32(-1))
            }
        }

        progressTask.cancel()
        watchdogTask.cancel()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        activeTranslationProcesses.removeValue(forKey: job.paperID)
        try? logHandle.synchronize()
        try? logHandle.close()

        if let launchError {
            return PDF2ZHRunResult(
                succeeded: false,
                message: localized(
                    chinese: "启动后台翻译进程失败：\(launchError.localizedDescription)",
                    english: "Failed to start the background translation process: \(launchError.localizedDescription)"
                )
            )
        }

        if let timeoutReason = monitor.currentTimeoutReason() {
            return PDF2ZHRunResult(
                succeeded: false,
                message: pdf2zhTimeoutMessage(reason: timeoutReason, logURL: logURL)
            )
        }

        guard exitCode == 0 else {
            return PDF2ZHRunResult(
                succeeded: false,
                message: pdf2zhFailureMessage(exitCode: exitCode, logURL: logURL)
            )
        }

        guard FileManager.default.fileExists(atPath: job.outputURL.path) else {
            return PDF2ZHRunResult(
                succeeded: false,
                message: localized(
                    chinese: "pdf2zh 已结束，但没有生成双页译文 PDF。日志：\(logURL.path)",
                    english: "pdf2zh finished, but no side-by-side PDF was generated. Log: \(logURL.path)"
                )
            )
        }

        if let values = try? job.outputURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modifiedAt = values.contentModificationDate,
           modifiedAt < startedAt.addingTimeInterval(-2) {
            return PDF2ZHRunResult(
                succeeded: false,
                message: localized(
                    chinese: "未检测到本次新生成的双页译文 PDF。日志：\(logURL.path)",
                    english: "No newly generated side-by-side PDF was detected for this run. Log: \(logURL.path)"
                )
            )
        }

        return PDF2ZHRunResult(succeeded: true, message: nil)
    }

    private func updatePDF2ZHProgress(for job: PDF2ZHTranslationJob, parsedProgress: Double) {
        guard activeTranslationJobs[job.paperID]?.id == job.id else { return }
        let current = translationProgressByPaperID[job.paperID] ?? 0.06
        let normalized = min(max(parsedProgress, 0.01), 0.99)
        translationProgressByPaperID[job.paperID] = max(current, normalized)
    }

    private func finishPDF2ZHTranslationJob(_ job: PDF2ZHTranslationJob, result: PDF2ZHRunResult) {
        guard activeTranslationJobs[job.paperID]?.id == job.id else { return }

        activeTranslationJobs.removeValue(forKey: job.paperID)
        translationJobTasks.removeValue(forKey: job.paperID)
        translationProgressByPaperID.removeValue(forKey: job.paperID)
        paperTableRefreshNonce = UUID()

        if result.succeeded {
            translationCompletedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: job.paperID,
                    title: job.title,
                    timestamp: Date(),
                    progress: 1
                ),
                into: translationCompletedTasks
            )
            translationFailedTasks = removeTaskEntry(for: job.paperID, from: translationFailedTasks)
        } else {
            translationFailedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: job.paperID,
                    title: job.title,
                    timestamp: Date(),
                    progress: 0,
                    message: result.message
                ),
                into: translationFailedTasks
            )
            print("pdf2zh 翻译失败(\(job.title)): \(result.message ?? "Unknown error")")
            alertMessage = result.message ?? localized(
                chinese: "pdf2zh 翻译失败：\(job.title)",
                english: "pdf2zh translation failed: \(job.title)"
            )
        }

        pumpPDF2ZHTranslationQueue()
    }

    private func startPDF2ZHProgressSimulation(for job: PDF2ZHTranslationJob) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled,
                  activeTranslationJobs[job.paperID]?.id == job.id {
                let current = translationProgressByPaperID[job.paperID] ?? 0.06
                translationProgressByPaperID[job.paperID] = min(0.94, current + max(0.006, (0.94 - current) * 0.035))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startPDF2ZHWatchdog(
        for job: PDF2ZHTranslationJob,
        process: Process,
        monitor: PDF2ZHRunMonitor
    ) -> Task<Void, Never> {
        let noOutputTimeout: TimeInterval = 20 * 60
        let highProgressTimeout: TimeInterval = 10 * 60
        let hardTimeout: TimeInterval = 3 * 60 * 60

        return Task { @MainActor in
            while !Task.isCancelled,
                  activeTranslationJobs[job.paperID]?.id == job.id {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                guard monitor.stalledReason(
                    now: Date(),
                    noOutputTimeout: noOutputTimeout,
                    highProgressTimeout: highProgressTimeout,
                    hardTimeout: hardTimeout
                ) != nil else {
                    continue
                }
                guard process.isRunning else { break }
                process.terminate()
                let pid = process.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
                break
            }
        }
    }

    private func makePDF2ZHBackgroundCommand(for job: PDF2ZHTranslationJob) -> String {
        let serviceArgument = "openai:\(job.model)"
        var lines = [
            "set -euo pipefail"
        ]
        lines.append(contentsOf: job.activationLines)
        lines.append("cd \(shellQuote(job.sourceURL.deletingLastPathComponent().path))")
        lines.append("pdf2zh \(shellQuote(job.sourceURL.path)) -li en -lo zh -s \(shellQuote(serviceArgument))")
        lines.append("python - \(shellQuote(job.sourceURL.path)) <<'PY'")
        lines.append(pdf2zhSideBySideScript)
        lines.append("PY")
        return lines.joined(separator: "\n")
    }

    private var pdf2zhSideBySideScript: String {
        """
import sys
from pathlib import Path
import fitz

source_path = Path(sys.argv[1])
translated_path = source_path.with_name(f"{source_path.stem}-zh.pdf")
output_path = source_path.with_name(f"{source_path.stem}-dual.pdf")
temporary_path = source_path.with_name(f"{source_path.stem}-dual.tmp.pdf")

if not translated_path.exists():
    raise SystemExit(f"Translated PDF not found: {translated_path}")

source_doc = fitz.open(source_path)
translated_doc = fitz.open(translated_path)
output_doc = fitz.open()

page_count = min(source_doc.page_count, translated_doc.page_count)
for index in range(page_count):
    left_page = source_doc[index]
    right_page = translated_doc[index]
    output_page = output_doc.new_page(
        width=left_page.rect.width + right_page.rect.width,
        height=max(left_page.rect.height, right_page.rect.height),
    )
    output_page.show_pdf_page(
        fitz.Rect(0, 0, left_page.rect.width, left_page.rect.height),
        source_doc,
        index,
    )
    output_page.show_pdf_page(
        fitz.Rect(left_page.rect.width, 0, left_page.rect.width + right_page.rect.width, right_page.rect.height),
        translated_doc,
        index,
    )

if temporary_path.exists():
    temporary_path.unlink()

output_doc.save(temporary_path)
output_doc.close()
translated_doc.close()
source_doc.close()
temporary_path.replace(output_path)
print(f"Saved side-by-side bilingual PDF: {output_path}")
"""
    }

    private func pdf2zhLogURL(for sourceURL: URL) -> URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(
            "\(sourceURL.deletingPathExtension().lastPathComponent)-pdf2zh.log",
            isDirectory: false
        )
    }

    private func makePDF2ZHLogHandle(at logURL: URL) -> FileHandle {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            try? handle.truncate(atOffset: 0)
            return handle
        }
        return FileHandle.nullDevice
    }

    private func pdf2zhFailureMessage(exitCode: Int32, logURL: URL) -> String {
        let logPreview: String = {
            guard let data = try? Data(contentsOf: logURL),
                  let text = String(data: Data(data.suffix(8_000)), encoding: .utf8) else {
                return ""
            }
            return text
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n")
                .suffix(8)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        if logPreview.isEmpty {
            return localized(
                chinese: "pdf2zh 退出码 \(exitCode)。日志：\(logURL.path)",
                english: "pdf2zh exited with code \(exitCode). Log: \(logURL.path)"
            )
        }

        return localized(
            chinese: "pdf2zh 退出码 \(exitCode)。日志：\(logURL.path)\n\(logPreview)",
            english: "pdf2zh exited with code \(exitCode). Log: \(logURL.path)\n\(logPreview)"
        )
    }

    private func pdf2zhTimeoutMessage(reason: PDF2ZHTimeoutReason, logURL: URL) -> String {
        let reasonText: String = {
            switch reason {
            case .noOutput:
                return localized(
                    chinese: "长时间没有新的输出，外部翻译进程可能已经卡住。",
                    english: "No new output was produced for a long time, so the external translation process may be stuck."
                )
            case .highProgressStall:
                return localized(
                    chinese: "进度长时间停留在高位（常见表现是 94%），已判定为卡住。",
                    english: "Progress stayed near completion for too long, so the job was treated as stalled."
                )
            case .hardLimit:
                return localized(
                    chinese: "翻译超过最长运行时限。",
                    english: "The translation exceeded the maximum runtime."
                )
            }
        }()

        return localized(
            chinese: "pdf2zh 翻译失败：\(reasonText)\n日志：\(logURL.path)",
            english: "pdf2zh translation failed: \(reasonText)\nLog: \(logURL.path)"
        )
    }

    nonisolated private static func parsePDF2ZHProgress(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<!\d)(100|[1-9]?\d)%"#) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        let percentages = matches.compactMap { match -> Double? in
            guard match.numberOfRanges > 1 else { return nil }
            let value = nsText.substring(with: match.range(at: 1))
            return Double(value)
        }
        guard let maximum = percentages.max() else { return nil }
        return maximum / 100.0
    }

    private func pauseTranslationTasks() {
        isTranslationQueuePaused.toggle()
        if !isTranslationQueuePaused {
            pumpPDF2ZHTranslationQueue()
        }
    }

    private func terminateTranslationTasks() {
        let pendingJobs = Array(activeTranslationJobs.values) + translationQueue

        for process in activeTranslationProcesses.values {
            if process.isRunning {
                process.terminate()
            }
        }
        activeTranslationProcesses.removeAll()
        translationJobTasks.values.forEach { $0.cancel() }
        translationJobTasks.removeAll()

        for job in pendingJobs {
            deleteTranslationOutputFiles(sourcePDFURL: job.sourceURL)
        }

        activeTranslationJobs.removeAll()
        translationQueue.removeAll()
        translationProgressByPaperID.removeAll()
        isTranslationQueuePaused = false
        translationPlannedTasks.removeAll()
        translationQueuedTasks.removeAll()
        paperTableRefreshNonce = UUID()
    }

    private func deleteTranslationOutputFiles(outputURL: URL) {
        let directory = outputURL.deletingLastPathComponent()
        let stem = outputURL.deletingPathExtension().lastPathComponent
        var candidates = [outputURL]
        if stem.hasSuffix("-dual") {
            let sourceStem = String(stem.dropLast("-dual".count))
            candidates.append(directory.appendingPathComponent("\(sourceStem)-zh.pdf", isDirectory: false))
        }
        deleteExistingFiles(candidates)
    }

    private func deleteTranslationOutputFiles(sourcePDFURL: URL) {
        let directory = sourcePDFURL.deletingLastPathComponent()
        let stem = sourcePDFURL.deletingPathExtension().lastPathComponent
        deleteExistingFiles([
            directory.appendingPathComponent("\(stem)-zh.pdf", isDirectory: false),
            directory.appendingPathComponent("\(stem)-dual.pdf", isDirectory: false)
        ])
    }

    private func deleteExistingFiles(_ urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }

    private func metadataField(for column: PaperTableColumn) -> MetadataField? {
        MetadataField.allCases.first { $0.tableColumn == column }
    }

    private func paperDragItemProvider(for paper: Paper) -> NSItemProvider {
        let draggedIDs = paperDragIDs(for: paper)
        let payload = draggedIDs.map(\.uuidString).joined(separator: "\n")
        let provider = store.defaultOpenPDFURL(for: paper)
            .flatMap { url -> NSItemProvider? in
                let provider = NSItemProvider(contentsOf: url)
                provider?.suggestedName = url.lastPathComponent
                return provider
            }
            ?? NSItemProvider(object: NSString(string: payload))
        provider.registerDataRepresentation(
            forTypeIdentifier: litrixPaperIDsUTType.identifier,
            visibility: .all
        ) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    private func paperDragIDs(for paper: Paper) -> [UUID] {
        guard selectedPaperIDs.contains(paper.id), selectedPaperIDs.count > 1 else {
            return [paper.id]
        }
        let ordered = sortedVisiblePaperIDs(from: selectedPaperIDs)
        return ordered.isEmpty ? [paper.id] : ordered
    }

    private struct AttachmentIconDescriptor: Identifiable {
        let id: String
        let systemName: String
        let color: Color
        let help: String
    }

    private var paperIdentifierIconColor: Color {
        Color(red: 76.0 / 255.0, green: 76.0 / 255.0, blue: 76.0 / 255.0)
    }

    @ViewBuilder
    private func paperTitleIcon(for paper: Paper) -> some View {
        let hasAttachment = likelyAttachmentStatus(for: paper)
        Image(systemName: hasAttachment ? "doc.fill" : "doc")
            .font(.system(size: 13.5, weight: .regular))
            .foregroundStyle(paperIdentifierIconColor)
            .help(hasAttachment
                ? localized(chinese: "有附件的条目", english: "Item with attachments")
                : localized(chinese: "无附件的条目", english: "Item without attachments")
            )
    }

    @ViewBuilder
    private func attachmentStatusCell(for paper: Paper) -> some View {
        let icons = attachmentIconDescriptors(for: store.attachmentURLs(for: paper))
        HStack(spacing: 5) {
            if icons.isEmpty {
                Image(systemName: "paperclip.slash")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(Color.secondary)
                    .help(localized(chinese: "无附件", english: "No attachment"))
            } else {
                ForEach(icons) { icon in
                    Image(systemName: icon.systemName)
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundStyle(icon.color)
                        .help(icon.help)
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachmentIconDescriptors(for urls: [URL]) -> [AttachmentIconDescriptor] {
        var descriptors: [AttachmentIconDescriptor] = []
        var seenKinds: Set<String> = []

        for url in urls {
            let kind = attachmentIconKind(for: url)
            guard seenKinds.insert(kind).inserted else { continue }
            let icon = documentIcon(for: url)
            descriptors.append(
                AttachmentIconDescriptor(
                    id: kind,
                    systemName: icon.systemName,
                    color: icon.color,
                    help: icon.help
                )
            )
        }

        return descriptors
    }

    private func attachmentIconKind(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "pdf"
        case "doc", "docx", "rtf", "txt", "md": return "document"
        case "xls", "xlsx", "csv": return "spreadsheet"
        case "ppt", "pptx": return "presentation"
        case "epub": return "epub"
        case "mobi": return "mobi"
        case "html", "htm": return "web"
        case "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "webp": return "image"
        default: return "file"
        }
    }

    private func documentIcon(for url: URL) -> (systemName: String, color: Color, help: String) {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return ("doc.richtext", Color.red.opacity(0.78), localized(chinese: "拖拽 PDF 到其他 App", english: "Drag PDF to another app"))
        case "doc", "docx", "rtf", "txt", "md":
            return ("doc.text", Color.blue.opacity(0.78), localized(chinese: "文档附件", english: "Document attachment"))
        case "xls", "xlsx", "csv":
            return ("tablecells", Color.green.opacity(0.78), localized(chinese: "表格附件", english: "Spreadsheet attachment"))
        case "ppt", "pptx":
            return ("rectangle.on.rectangle", Color.orange.opacity(0.82), localized(chinese: "演示文稿附件", english: "Presentation attachment"))
        case "epub":
            return ("book.closed", Color.purple.opacity(0.78), localized(chinese: "EPUB 附件", english: "EPUB attachment"))
        case "mobi":
            return ("book.closed.fill", Color.purple.opacity(0.78), localized(chinese: "MOBI 附件", english: "MOBI attachment"))
        case "html", "htm":
            return ("globe", Color.cyan.opacity(0.78), localized(chinese: "网页附件", english: "Web attachment"))
        case "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "webp":
            return ("photo", Color.mint.opacity(0.82), localized(chinese: "图片附件", english: "Image attachment"))
        default:
            return ("doc", Color.secondary, localized(chinese: "文件附件", english: "File attachment"))
        }
    }

    private func toggleCollection(_ collection: String, for paper: Paper) {
        let currentPaper = resolvedPaper(paper)
        let targetIDs = targetPaperIDs(for: currentPaper)
        setCollection(collection, assigned: shouldAssignCollection(collection, forPaperIDs: targetIDs), forPaperIDs: targetIDs)
    }

    private func toggleTag(_ tag: String, for paper: Paper) {
        let currentPaper = resolvedPaper(paper)
        let targetIDs = targetPaperIDs(for: currentPaper)
        setTag(tag, assigned: shouldAssignTag(tag, forPaperIDs: targetIDs), forPaperIDs: targetIDs)
    }

    private func allTargetPapersHaveTaxonomyItem(
        _ item: String,
        forPaperIDs paperIDs: [UUID],
        itemsInPaper: (Paper) -> [String]
    ) -> Bool {
        let papers = paperIDs.compactMap { store.paper(id: $0) }
        guard !papers.isEmpty else { return false }
        return papers.allSatisfy { itemsInPaper($0).contains(item) }
    }

    private func shouldAssignCollection(_ collection: String, forPaperIDs paperIDs: [UUID]) -> Bool {
        !allTargetPapersHaveTaxonomyItem(collection, forPaperIDs: paperIDs, itemsInPaper: \.collections)
    }

    private func shouldAssignTag(_ tag: String, forPaperIDs paperIDs: [UUID]) -> Bool {
        !allTargetPapersHaveTaxonomyItem(tag, forPaperIDs: paperIDs, itemsInPaper: \.tags)
    }

    private func setCollection(_ collection: String, assigned: Bool, forPaperIDs paperIDs: [UUID]) {
        store.setCollection(collection, assigned: assigned, forPaperIDs: paperIDs)
        refreshPapersImmediately(paperIDs)
    }

    private func setTag(_ tag: String, assigned: Bool, forPaperIDs paperIDs: [UUID]) {
        store.setTag(tag, assigned: assigned, forPaperIDs: paperIDs)
        refreshPapersImmediately(paperIDs)
    }

    private func tagColor(for tag: String) -> Color {
        guard let hex = store.tagColorHex(forTag: tag) else {
            return .secondary
        }
        return colorFromHex(hex)
    }

    private func presentTagColorPanel(for tag: String) {
        TagColorPanelCoordinator.shared.present(
            tag: tag,
            initialHex: store.tagColorHex(forTag: tag),
            onChange: { selectedTag, hex in
                store.setTagColor(hex: hex, forTag: selectedTag)
            }
        )
    }

    private func colorFromHex(_ hex: String) -> Color {
        let value = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard value.count == 6,
              let intValue = Int(value, radix: 16) else {
            return .secondary
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    @ViewBuilder
    private func metadataRefreshMenus(for paper: Paper, column: PaperTableColumn) -> some View {
        let targetIDs = targetPaperIDs(for: paper)
        if column == .impactFactor {
            Button(localized(chinese: "通过 easyScholar 更新影响因子", english: "Update IF via easyScholar")) {
                refreshImpactFactorsViaEasyScholar(
                    forPaperIDs: targetIDs,
                    showErrorsInAlert: targetIDs.count == 1
                )
            }

            Divider()
        }

        metadataRefreshMenu(
            title: localized(chinese: "通过API刷新元数据", english: "Refresh Metadata via API"),
            source: .api,
            targetIDs: targetIDs,
            field: metadataField(for: column)
        )
        metadataRefreshMenu(
            title: localized(chinese: "通过本地识别刷新元数据", english: "Refresh Metadata Locally"),
            source: .local,
            targetIDs: targetIDs,
            field: metadataField(for: column)
        )
        metadataRefreshMenu(
            title: localized(chinese: "从网页刷新元数据", english: "Refresh Metadata from Web Page"),
            source: .web,
            targetIDs: targetIDs,
            field: metadataField(for: column)
        )
    }

    @ViewBuilder
    private func metadataRefreshMenu(
        title: String,
        source: MetadataRefreshSource,
        targetIDs: [UUID],
        field: MetadataField?
    ) -> some View {
        Menu(title) {
            if let field {
                Button(
                    localized(
                        chinese: "刷新\(field.displayName(for: settings.appLanguage))",
                        english: "Refresh \(field.displayName(for: settings.appLanguage))"
                    )
                ) {
                    runMetadataRefresh(
                        source: source,
                        forPaperIDs: targetIDs,
                        mode: .customRefresh,
                        customFields: [field],
                        showErrorsInAlert: targetIDs.count == 1
                    )
                }

                Divider()
            }

            Button(localized(chinese: "刷新全部", english: "Refresh All")) {
                runMetadataRefresh(
                    source: source,
                    forPaperIDs: targetIDs,
                    mode: .refreshAll,
                    customFields: nil,
                    showErrorsInAlert: targetIDs.count == 1
                )
            }

            Button(localized(chinese: "刷新缺失", english: "Refresh Missing")) {
                runMetadataRefresh(
                    source: source,
                    forPaperIDs: targetIDs,
                    mode: .refreshMissing,
                    customFields: nil,
                    showErrorsInAlert: targetIDs.count == 1
                )
            }

            Button(localized(chinese: "自定义刷新...", english: "Custom Refresh...")) {
                openCustomRefreshFieldChooser(forPaperIDs: targetIDs, source: source)
            }
        }
    }

    @ViewBuilder
    private func paperCell<Content: View>(
        for paper: Paper,
        column: PaperTableColumn,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(
                maxWidth: .infinity,
                minHeight: supportsWrappedCellContent
                    ? settings.resolvedMaximumTableRowHeight
                    : settings.resolvedTableRowHeight,
                alignment: .leading
            )
            .frame(
                maxHeight: supportsWrappedCellContent
                    ? settings.resolvedMaximumTableRowHeight
                    : settings.resolvedTableRowHeight,
                alignment: .leading
            )
            .background(tableRowBackground(for: paper))
            .contentShape(Rectangle())
            .contextMenu {
                let currentPaper = resolvedPaper(paper)
                if paper.isDeleted {
                    recentlyDeletedPaperContextMenu(for: paper)
                } else {
                    if column == .image {
                        Button(localized(chinese: "粘贴图片", english: "Paste Image")) {
                            pasteImageFromClipboard(for: currentPaper)
                        }
                    } else if column.isEditableFromPaperTable {
                        Button(localized(chinese: "编辑", english: "Edit")) {
                            beginCellEdit(for: currentPaper, column: column)
                        }
                    } else {
                        Text(localized(chinese: "只读", english: "Read-only"))
                    }

                    Divider()

                    metadataRefreshMenus(for: currentPaper, column: column)

                Button(localized(chinese: "在 Finder 中显示", english: "Reveal in Finder")) {
                    revealPaperInFinder(for: currentPaper)
                }

                Button(localized(chinese: "打开文献", english: "Open Paper")) {
                    for item in targetPapers(for: currentPaper) {
                        store.openPDF(for: item)
                    }
                }

                Button(localized(chinese: "添加附件", english: "Add Attachment")) {
                    presentAttachmentOpenPanel(for: currentPaper)
                }

                Button(localized(chinese: "替换附件", english: "Replace Attachment")) {
                    presentAttachmentReplacementPanel(for: currentPaper)
                }

                Button(localized(chinese: "重命名附件", english: "Rename Attachment")) {
                    for item in targetPapers(for: currentPaper) {
                        _ = store.renameStoredPDF(forPaperID: item.id)
                    }
                }

                Button(localized(chinese: "通过 pdf2zh 翻译", english: "Translate via pdf2zh")) {
                    translateViaPDF2ZH(for: currentPaper)
                }

                defaultOpenPDFMenu(for: currentPaper)

                Button(localized(chinese: "复制文献地址", english: "Copy Paper Address")) {
                    copyPaperAddress(for: currentPaper)
                }

                Divider()

                Menu(localized(chinese: "分类", english: "Collections")) {
                    if store.collections.isEmpty {
                        Text(localized(chinese: "暂无分类", english: "No Collections"))
                    } else {
                        ForEach(collectionTree) { node in
                            taxonomyAssignmentMenuNode(
                                node,
                                kind: .collection,
                                currentPaper: currentPaper
                            )
                        }
                    }

                    Divider()

                    Button(localized(chinese: "新建分类", english: "New Collection")) {
                        beginInlineCollectionCreation()
                    }
                }

                Menu(localized(chinese: "标签", english: "Tags")) {
                    Menu(localized(chinese: "快捷数字", english: "Quick Number")) {
                        ForEach(1...9, id: \.self) { number in
                            Button(quickNumberMenuTitle(number: number)) {
                                applyQuickTag(number: number, for: paper)
                            }
                            .disabled(settings.tagQuickNumberMap.first(where: { $0.value == number }) == nil)
                        }
                    }

                    Divider()

                    if store.tags.isEmpty {
                        Text(localized(chinese: "暂无标签", english: "No Tags"))
                    } else {
                        ForEach(tagTree) { node in
                            taxonomyAssignmentMenuNode(
                                node,
                                kind: .tag,
                                currentPaper: currentPaper
                            )
                        }
                    }

                    Divider()

                    Button(localized(chinese: "新建标签", english: "New Tag")) {
                        beginTaxonomyCreation(kind: .tag, relation: .root, referencePath: nil)
                    }
                }

                Divider()

                Button(localized(chinese: "导出 BibTeX", english: "Export BibTeX")) {
                    exportBibTeX(for: targetPapers(for: currentPaper))
                }

                Button(localized(chinese: "删除", english: "Delete"), role: .destructive) {
                    if selectedPaperIDs.contains(currentPaper.id), selectedPaperIDs.count > 1 {
                        requestDeleteSelectedPaper()
                    } else {
                        requestDelete(currentPaper)
                    }
                }
            }
            }
    }

    @ViewBuilder
    private func recentlyDeletedPaperContextMenu(for paper: Paper) -> some View {
        Button(localized(chinese: "还原", english: "Restore")) {
            restoreDeletedPapers(for: paper)
        }

        Divider()

        Button(localized(chinese: "彻底删除", english: "Delete Permanently"), role: .destructive) {
            requestPermanentDelete(paper)
        }
    }

    private func taxonomyAssignmentMenuNode(
        _ node: TaxonomyNode,
        kind: TaxonomyKind,
        currentPaper: Paper
    ) -> AnyView {
        if node.children.isEmpty {
            return taxonomyAssignmentButton(node, kind: kind, currentPaper: currentPaper)
        } else {
            return AnyView(Menu(node.name) {
                taxonomyAssignmentButton(node, kind: kind, currentPaper: currentPaper)
                Divider()
                ForEach(node.children) { child in
                    taxonomyAssignmentMenuNode(child, kind: kind, currentPaper: currentPaper)
                }
            })
        }
    }

    private func taxonomyAssignmentButton(
        _ node: TaxonomyNode,
        kind: TaxonomyKind,
        currentPaper: Paper
    ) -> AnyView {
        let isAssigned = kind == .collection
            ? currentPaper.collections.contains(node.path)
            : currentPaper.tags.contains(node.path)
        return AnyView(Button {
            if kind == .collection {
                toggleCollection(node.path, for: currentPaper)
            } else {
                toggleTag(node.path, for: currentPaper)
            }
        } label: {
            Label {
                Text(node.name)
            } icon: {
                Image(systemName: isAssigned ? "checkmark" : (kind == .collection ? "folder" : "tag"))
            }
        })
    }

    @ViewBuilder
    private func tableRowBackground(for paper: Paper) -> some View {
        if isPDF2ZHTranslationActive(for: paper) {
            Color.clear
        } else {
        let rowIndex = cachedSortedPaperIndexByID[paper.id] ?? 0
        let fillColor: Color = {
            // Let AppKit draw selected-row highlights. Keeping this view independent
            // from selection avoids rebuilding visible cells on every row click.
            // Odd rows: apply user-configured alternating color if set
            if !rowIndex.isMultiple(of: 2) {
                let hex = settings.alternatingRowColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
                let opacity = settings.alternatingRowOpacity
                if !hex.isEmpty, let color = Color(hexString: hex) {
                    return color.opacity(opacity)
                }
                // Empty hex = no alternating color
                return Color.clear
            }
            return Color.clear
        }()

        Rectangle()
            .fill(fillColor)
        }
    }

    private func isPDF2ZHTranslationActive(for paper: Paper) -> Bool {
        activeTranslationJobs[paper.id] != nil
    }

    private func cachedAttachmentStatus(for paper: Paper) -> Bool {
        cachedAttachmentStatusByID[paper.id] ?? store.hasExistingPDFAttachment(for: paper)
    }

    private func likelyAttachmentStatus(for paper: Paper) -> Bool {
        if let cached = cachedAttachmentStatusByID[paper.id] {
            return cached
        }
        return hasLikelyPDFDragSource(for: paper) || !paper.imageFileNames.isEmpty
    }

    private func hasLikelyPDFDragSource(for paper: Paper) -> Bool {
        !normalizedFileName(paper.preferredOpenPDFFileName).isEmpty
            || !normalizedFileName(paper.storedPDFFileName).isEmpty
            || !normalizedFileName(paper.originalPDFFileName).isEmpty
    }

    private func normalizedFileName(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func cachedImageURLs(for paper: Paper) -> [URL] {
        cachedImageURLsByID[paper.id] ?? store.imageURLs(for: paper)
    }

    private var supportsWrappedCellContent: Bool {
        settings.resolvedTableRowHeightMultiplier > 1.01
    }

    private var effectiveDeterministicTableRowHeight: CGFloat {
        if supportsWrappedCellContent {
            return settings.resolvedMaximumTableRowHeight
        }
        return settings.resolvedTableRowHeight
    }

    private var tableTextLineLimit: Int? {
        supportsWrappedCellContent ? settings.resolvedExpandedTableLineLimit : 1
    }

    private func selectedTableTextColor(for paper: Paper) -> Color? {
        let hex = settings.tableSelectionTextColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedPaperIDs.contains(paper.id),
              !hex.isEmpty,
              let color = Color(hexString: hex) else {
            return nil
        }
        return color
    }

    private func tableCellTextColor(for paper: Paper, isPlaceholder: Bool = false) -> Color {
        if let selectedColor = selectedTableTextColor(for: paper) {
            return isPlaceholder ? selectedColor.opacity(0.72) : selectedColor
        }
        return isPlaceholder ? .secondary : .primary
    }

    @ViewBuilder
    private func metadataTextCell(for value: String, isVisible: Bool) -> some View {
        if isVisible {
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(tableTextLineLimit)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func metadataTextCell(for paper: Paper, value: String, isVisible: Bool) -> some View {
        if isVisible {
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: value.isEmpty))
                .lineLimit(tableTextLineLimit)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func metadataTextCell(
        for paper: Paper,
        value: String,
        isVisible: Bool,
        column: PaperTableColumn
    ) -> some View {
        paperCell(for: paper, column: column) {
            metadataTextCell(for: paper, value: value, isVisible: isVisible)
        }
    }

    @ViewBuilder
    private func impactFactorTextCell(for paper: Paper, value: String, isVisible: Bool) -> some View {
        if isVisible {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedTableTextColor(for: paper) == nil,
               let attributed = attributedImpactFactorText(for: trimmed) {
                Text(attributed)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .lineLimit(tableTextLineLimit)
            } else {
                Text(trimmed.isEmpty ? "—" : trimmed)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: trimmed.isEmpty))
                    .lineLimit(tableTextLineLimit)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func impactFactorDisplayCell(for paper: Paper) -> some View {
        paperCell(for: paper, column: .impactFactor) {
            impactFactorTextCell(for: paper, value: paper.impactFactor, isVisible: true)
        }
    }

    private func attributedImpactFactorText(for value: String) -> AttributedString? {
        guard !value.isEmpty else { return nil }
        let colors = easyScholarImpactFactorTextColors()
        guard !colors.isEmpty else { return nil }

        let parts = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.isEmpty else { return nil }

        var attributed = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                attributed.append(AttributedString(", "))
            }
            var segment = AttributedString(part)
            if index < colors.count {
                segment.foregroundColor = colors[index]
            }
            attributed.append(segment)
        }
        return attributed
    }

    private func easyScholarImpactFactorTextColors() -> [Color] {
        settings.easyScholarColorHexes
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" || $0 == ";" })
            .compactMap { colorFromOptionalHex(String($0)) }
    }

    private func colorFromOptionalHex(_ hex: String) -> Color? {
        let value = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard value.count == 6,
              let intValue = Int(value, radix: 16) else {
            return nil
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    @ViewBuilder
    private func titleDisplayCell(for paper: Paper) -> some View {
        let presentation = displayedTitlePresentation(for: paper)
        paperCell(for: paper, column: .title) {
            HStack(spacing: 8) {
                paperTitleIcon(for: paper)
                Text(presentation.text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: presentation.isPlaceholder))
                    .lineLimit(tableTextLineLimit)
            }
            .contentShape(Rectangle())
        }
        .task(id: presentation.translationRequest) {
            guard let request = presentation.translationRequest else { return }
            ensureTitleTranslationIfNeeded(request)
        }
    }

    @ViewBuilder
    private func abstractDisplayCell(for paper: Paper) -> some View {
        let presentation = displayedAbstractPresentation(for: paper)
        paperCell(for: paper, column: .abstractText) {
            metadataTextCell(for: paper, value: presentation.text, isVisible: true)
        }
        .task(id: presentation.translationRequest) {
            guard let request = presentation.translationRequest else { return }
            ensureAbstractTranslationIfNeeded(request)
        }
    }

    @ViewBuilder
    private func paperImageStrip(for paper: Paper) -> some View {
        let items = cachedImageURLs(for: paper)
            .prefix(supportsWrappedCellContent ? 4 : 3)
            .map { paperImageMetadataItem(for: paper, url: $0) }

        if items.isEmpty {
            Text("—")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(tableCellTextColor(for: paper, isPlaceholder: true))
        } else {
            let idealSize = effectiveDeterministicTableRowHeight * (7.0 / 8.0)
            let userCappedSize = settings.resolvedMaximumTableRowHeight * settings.resolvedImageThumbnailMaxSizeMultiplier
            let size = max(14, min(userCappedSize, idealSize))
            let maxPixel = max(48, size * (NSScreen.main?.backingScaleFactor ?? 2))
            let isInteractive = selectedPaperIDs.contains(paper.id)
            HStack(spacing: 6) {
                ForEach(items) { item in
                    PaperImageThumbnailView(
                        item: item,
                        size: size,
                        maxPixel: maxPixel,
                        language: settings.appLanguage,
                        isInteractive: isInteractive,
                        onOpen: {
                            openImageInSystemApp(item.imageURL)
                        },
                        onDelete: {
                            requestDeleteImage(
                                paperID: paper.id,
                                fileName: item.imageURL.lastPathComponent,
                                url: item.imageURL
                            )
                        },
                        onHoverChanged: { hovering in
                            if hovering {
                                hoveredPreviewImageURL = item.imageURL
                            } else if hoveredPreviewImageURL?.standardizedFileURL == item.imageURL.standardizedFileURL {
                                hoveredPreviewImageURL = nil
                            }
                        }
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tagsDotCell(for paper: Paper) -> some View {
        if paper.tags.isEmpty {
            Text("—")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            switch settings.tagColumnDisplayMode {
            case .color:
                HStack(spacing: 6) {
                    ForEach(Array(paper.tags.prefix(8)), id: \.self) { tag in
                        Circle()
                            .fill(tagColor(for: tag))
                            .frame(width: 9, height: 9)
                    }
                    if paper.tags.count > 8 {
                        Circle()
                            .fill(Color.secondary.opacity(0.38))
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .text:
                tagsTextCell(for: paper)
            }
        }
    }

    @ViewBuilder
    private func tagsTextCell(for paper: Paper) -> some View {
        if supportsWrappedCellContent {
            TagFlowLayout(horizontalSpacing: 5, verticalSpacing: 4) {
                ForEach(paper.tags, id: \.self) { tag in
                    let color = tagColor(for: tag)
                    tagChip(
                        title: tag,
                        color: color,
                        textColor: selectedTableTextColor(for: paper) ?? color
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        } else {
            let visibleTags = Array(paper.tags.prefix(4))
            HStack(spacing: 4) {
                ForEach(visibleTags, id: \.self) { tag in
                    let color = tagColor(for: tag)
                    tagChip(
                        title: tag,
                        color: color,
                        textColor: selectedTableTextColor(for: paper) ?? color
                    )
                }
                if paper.tags.count > 4 {
                    Text("+\(paper.tags.count - 4)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTableTextColor(for: paper) ?? .secondary)
                        .lineLimit(1)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }

    private func tagChip(title: String, color: Color, textColor: Color) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.20))
            )
            .help(title)
    }

    private func openHoveredTableCellEditor() {
        guard let target = hoveredTableCellTarget,
              let paper = store.paper(id: target.paperID),
              !paper.isDeleted else {
            NSSound.beep()
            return
        }

        if target.column == .image {
            pasteImageFromClipboard(for: paper)
            return
        }

        guard target.column.isEditableFromPaperTable else {
            NSSound.beep()
            return
        }

        beginCellEdit(for: paper, column: target.column)
    }

    private func beginCellEdit(for paper: Paper, column: PaperTableColumn) {
        selectSinglePaper(paper.id)

        if column == .image {
            pasteImageFromClipboard(for: paper)
            return
        }

        if !column.isEditableFromPaperTable {
            NSSound.beep()
            return
        }

        cellEditDraft = editableCellValue(for: paper, column: column)
        activeCellEditTarget = TableCellEditTarget(paperID: paper.id, column: column)
    }

    private func saveCellEdit(_ target: TableCellEditTarget) {
        guard var paper = store.paper(id: target.paperID) else {
            activeCellEditTarget = nil
            return
        }

        if !applyEditableCellValue(cellEditDraft, to: &paper, column: target.column) {
            return
        }

        store.updatePaper(paper)
        if let updated = store.paper(id: target.paperID) {
            refreshEditedPaperImmediately(updated)
        }
        activeCellEditTarget = nil
    }

    private func refreshEditedPaperImmediately(_ paper: Paper) {
        refreshPapersImmediately([paper.id])
    }

    private func refreshPapersImmediately(_ paperIDs: [UUID], alignSelection: Bool = true) {
        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }

        var refreshedCache = cachedSortedPapers
        var didUpdateVisibleCache = false
        for paperID in targetIDs {
            guard let updatedPaper = store.paper(id: paperID),
                  let index = cachedSortedPaperIndexByID[paperID],
                  refreshedCache.indices.contains(index) else {
                continue
            }
            refreshedCache[index] = updatedPaper
            didUpdateVisibleCache = true
        }

        if didUpdateVisibleCache {
            applySortedPaperCache(refreshedCache)
            paperTableRefreshNonce = UUID()
        }
        refreshSortedPapersImmediately(alignSelection: alignSelection)
    }

    private func refreshSortedPapersImmediately(alignSelection: Bool = true) {
        pendingSortedPapersRecomputeTask?.cancel()
        pendingSortedPapersRecomputeTask = Task { @MainActor in
            clearSortedResultIDCache()
            await recomputeSortedPapers()
            if alignSelection {
                alignSelectionWithVisibleResults()
            }
            paperTableRefreshNonce = UUID()
            pendingSortedPapersRecomputeTask = nil
        }
    }

    private func pasteImageFromClipboard(for paper: Paper) {
        Task { @MainActor in
            let pasted = await store.addImageFromPasteboard(to: paper.id)
            if !pasted {
                alertMessage = "Clipboard does not contain an image."
            } else {
                refreshPapersImmediately([paper.id], alignSelection: false)
                rebuildImageGalleryCache()
            }
        }
    }

    private func editableCellValue(for paper: Paper, column: PaperTableColumn) -> String {
        switch column {
        case .title:
            switch settings.titleDisplayLanguage {
            case .original: return paper.title
            case .chinese: return paper.chineseTitle
            case .english: return paper.englishTitle
            }
        case .englishTitle: return paper.englishTitle
        case .authors: return paper.authors
        case .authorsEnglish: return paper.authorsEnglish
        case .year: return paper.year
        case .source: return paper.source
        case .addedTime: return formattedAddedTime(from: paper.addedAtMilliseconds)
        case .editedTime: return formattedEditedTime(from: paper.lastEditedAtMilliseconds)
        case .tags: return paper.tags.joined(separator: ", ")
        case .rating: return String(clampedRating(paper.rating))
        case .image: return ""
        case .attachmentStatus:
            return store.hasExistingPDFAttachment(for: paper) ? "Attached" : "Missing"
        case .note: return paper.notes
        case .abstractText: return paper.abstractText
        case .chineseAbstract: return paper.chineseAbstract
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
        case .webPageURL: return paper.webPageURL
        }
    }

    private func applyEditableCellValue(_ value: String, to paper: inout Paper, column: PaperTableColumn) -> Bool {
        switch column {
        case .title:
            switch settings.titleDisplayLanguage {
            case .original: paper.title = value
            case .chinese: paper.chineseTitle = value
            case .english: paper.englishTitle = value
            }
        case .englishTitle: paper.englishTitle = value
        case .authors: paper.authors = value
        case .authorsEnglish: paper.authorsEnglish = value
        case .year: paper.year = value
        case .source: paper.source = value
        case .addedTime:
            alertMessage = "Added Time is read-only."
            return false
        case .editedTime:
            alertMessage = "Edited Time is read-only."
            return false
        case .tags:
            alertMessage = "Tags are managed from the Tags menu."
            return false
        case .rating:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty || Int(trimmed) != nil else {
                alertMessage = "Rating must be an integer between 0 and \(PaperRatingScale.maximum)."
                return false
            }
            paper.rating = PaperRatingScale.clamped(Int(trimmed) ?? 0)
        case .image:
            return true
        case .attachmentStatus:
            alertMessage = "Attachment Status is read-only."
            return false
        case .note: paper.notes = value
        case .abstractText:
            paper.abstractText = value
            paper.englishAbstract = ""
            if !containsHanCharacters(value) {
                paper.chineseAbstract = ""
            }
        case .chineseAbstract: paper.chineseAbstract = value
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
        case .webPageURL: paper.webPageURL = value
        }
        return true
    }

    private func clampedRating(_ rating: Int) -> Int {
        PaperRatingScale.clamped(rating)
    }

    private func formattedAddedTime(from milliseconds: Int64) -> String {
        Self.formattedAddedTimeStatic(
            from: milliseconds,
            dateFormat: settings.resolvedPaperTimestampDateFormat
        )
    }

    private func formattedEditedTime(from milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        return formattedAddedTime(from: milliseconds)
    }

    private func noteCellText(for paper: Paper) -> String {
        let trimmed = paper.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        if supportsWrappedCellContent {
            return trimmed
        }
        return String(trimmed.prefix(24))
    }

    private func assignDroppedPaperIDs(_ ids: [UUID], toCollection collection: String) {
        targetedDropCollection = nil
        guard !ids.isEmpty else { return }
        setCollection(collection, assigned: true, forPaperIDs: ids)
        refreshSortedPapersImmediately()
    }

    private func assignDroppedPaperIDs(_ ids: [UUID], toTag tag: String) {
        targetedDropTag = nil
        guard !ids.isEmpty else { return }
        setTag(tag, assigned: true, forPaperIDs: ids)
        refreshSortedPapersImmediately()
    }

    private func assignDroppedPapers(_ providers: [NSItemProvider], toCollection collection: String) -> Bool {
        let paperIDProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(litrixPaperIDsUTType.identifier)
        }
        guard !paperIDProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = DroppedPaperIDCollector()

        for provider in paperIDProviders {
            group.enter()
            loadDroppedPaperIDs(from: provider, collector: collector, group: group)
        }

        group.notify(queue: .main) {
            let ids = collector.snapshot()
            targetedDropCollection = nil
            guard !ids.isEmpty else { return }
            setCollection(collection, assigned: true, forPaperIDs: ids)
            refreshSortedPapersImmediately()
        }
        return true
    }

    private func assignDroppedPapers(_ providers: [NSItemProvider], toTag tag: String) -> Bool {
        let paperIDProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(litrixPaperIDsUTType.identifier)
        }
        guard !paperIDProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = DroppedPaperIDCollector()

        for provider in paperIDProviders {
            group.enter()
            loadDroppedPaperIDs(from: provider, collector: collector, group: group)
        }

        group.notify(queue: .main) {
            let ids = collector.snapshot()
            targetedDropTag = nil
            guard !ids.isEmpty else { return }
            setTag(tag, assigned: true, forPaperIDs: ids)
            refreshSortedPapersImmediately()
        }
        return true
    }

    private func loadDroppedPaperIDs(
        from provider: NSItemProvider,
        collector: DroppedPaperIDCollector,
        group: DispatchGroup
    ) {
        let finish: @Sendable ([UUID]) -> Void = { ids in
            collector.append(contentsOf: ids)
            group.leave()
        }
        let preferredType = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : litrixPaperIDsUTType.identifier
        provider.loadItem(forTypeIdentifier: preferredType, options: nil) { item, _ in
            finish(parseDroppedPaperIDsFromItem(item))
        }
    }
}

private func parseDroppedPaperIDsFromItem(_ item: NSSecureCoding?) -> [UUID] {
    let rawValue: String?
    switch item {
    case let data as Data:
        rawValue = String(data: data, encoding: .utf8)
    case let string as String:
        rawValue = string
    case let string as NSString:
        rawValue = string as String
    case let attributed as NSAttributedString:
        rawValue = attributed.string
    default:
        rawValue = nil
    }

    guard let rawValue else { return [] }
    return parseDroppedPaperIDsFromString(rawValue)
}

private func parseDroppedPaperIDsFromString(_ rawValue: String?) -> [UUID] {
    guard let rawValue else { return [] }
    return rawValue
        .split(whereSeparator: \.isNewline)
        .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
}

private struct CenterPaneDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    @Binding var promptKind: CenterDropPromptKind
    let onImportExternalFiles: ([URL]) -> Void
    var onDropInternalPaperIDs: (([UUID]) -> Void)?

    func makeNSView(context: Context) -> CenterPaneDropTargetView {
        let view = CenterPaneDropTargetView()
        view.onDropStateChange = { isTargeted, promptKind in
            self.isTargeted = isTargeted
            self.promptKind = promptKind
        }
        view.onImportExternalFiles = onImportExternalFiles
        view.onDropInternalPaperIDs = onDropInternalPaperIDs
        return view
    }

    func updateNSView(_ nsView: CenterPaneDropTargetView, context: Context) {
        nsView.onDropStateChange = { isTargeted, promptKind in
            self.isTargeted = isTargeted
            self.promptKind = promptKind
        }
        nsView.onImportExternalFiles = onImportExternalFiles
        nsView.onDropInternalPaperIDs = onDropInternalPaperIDs
    }
}

private final class CenterPaneDropTargetView: NSView {
    var onDropStateChange: ((Bool, CenterDropPromptKind) -> Void)?
    var onImportExternalFiles: (([URL]) -> Void)?
    var onDropInternalPaperIDs: (([UUID]) -> Void)?
    private var isTrackingInternalPaperDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType(litrixPaperIDsUTType.identifier)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropState(with: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDropState(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if !isTrackingInternalPaperDrag {
            onDropStateChange?(false, .externalImport)
        }
        isTrackingInternalPaperDrag = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            if !isTrackingInternalPaperDrag {
                onDropStateChange?(false, .externalImport)
            }
            isTrackingInternalPaperDrag = false
        }

        switch dragContext(for: sender) {
        case .internalPaper(let ids):
            onDropInternalPaperIDs?(ids)
            return true
        case .externalFiles(let urls):
            guard !urls.isEmpty else { return false }
            onImportExternalFiles?(urls)
            return true
        case .none:
            return false
        }
    }

    private func updateDropState(with sender: NSDraggingInfo) -> NSDragOperation {
        switch dragContext(for: sender) {
        case .internalPaper:
            isTrackingInternalPaperDrag = true
            onDropStateChange?(true, .externalImport)
            return .copy
        case .externalFiles(let urls):
            isTrackingInternalPaperDrag = false
            guard !urls.isEmpty else {
                onDropStateChange?(false, .externalImport)
                return []
            }
            onDropStateChange?(true, .externalImport)
            return .copy
        case .none:
            isTrackingInternalPaperDrag = false
            onDropStateChange?(false, .externalImport)
            return []
        }
    }

    private func dragContext(for sender: NSDraggingInfo) -> DragContext {
        let pasteboard = sender.draggingPasteboard
        let types = Set(pasteboard.types ?? [])
        let internalType = NSPasteboard.PasteboardType(litrixPaperIDsUTType.identifier)
        if types.contains(internalType) {
            let ids = paperIDs(from: pasteboard)
            return .internalPaper(ids)
        }

        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        if !urls.isEmpty {
            return .externalFiles(urls)
        }

        return .none
    }

    private func paperIDs(from pasteboard: NSPasteboard) -> [UUID] {
        let customType = NSPasteboard.PasteboardType(litrixPaperIDsUTType.identifier)
        return parseDroppedPaperIDsFromString(
            pasteboard.string(forType: customType)
                ?? pasteboard.string(forType: .string)
        )
    }

    private enum DragContext {
        case none
        case internalPaper([UUID])
        case externalFiles([URL])
    }
}

private struct SidebarPaperDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDropPaperIDs: ([UUID]) -> Void

    func makeNSView(context: Context) -> SidebarPaperDropTargetView {
        let view = SidebarPaperDropTargetView()
        view.onTargetChanged = { isTargeted in
            self.isTargeted = isTargeted
        }
        view.onDropPaperIDs = onDropPaperIDs
        return view
    }

    func updateNSView(_ nsView: SidebarPaperDropTargetView, context: Context) {
        nsView.onTargetChanged = { isTargeted in
            self.isTargeted = isTargeted
        }
        nsView.onDropPaperIDs = onDropPaperIDs
    }
}

private final class SidebarPaperDropTargetView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onDropPaperIDs: (([UUID]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(litrixPaperIDsUTType.identifier),
            .string
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTargetState(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTargetState(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetChanged?(false) }
        let ids = paperIDs(from: sender.draggingPasteboard)
        guard !ids.isEmpty else { return false }
        onDropPaperIDs?(ids)
        return true
    }

    private func updateTargetState(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ids = paperIDs(from: sender.draggingPasteboard)
        let acceptsDrop = !ids.isEmpty
        onTargetChanged?(acceptsDrop)
        return acceptsDrop ? .copy : []
    }

    private func paperIDs(from pasteboard: NSPasteboard) -> [UUID] {
        let customType = NSPasteboard.PasteboardType(litrixPaperIDsUTType.identifier)
        return parseDroppedPaperIDsFromString(
            pasteboard.string(forType: customType)
                ?? pasteboard.string(forType: .string)
        )
    }
}

private final class DroppedPaperIDCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []

    func append(contentsOf newIDs: [UUID]) {
        lock.lock()
        ids.append(contentsOf: newIDs)
        lock.unlock()
    }

    func snapshot() -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        var seen: Set<UUID> = []
        return ids.filter { seen.insert($0).inserted }
    }
}

private struct TableCellEditTarget: Identifiable {
    let paperID: UUID
    let column: PaperTableColumn

    var id: String {
        "\(paperID.uuidString)-\(column.rawValue)"
    }
}

private struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = measuredRows(for: subviews, proposalWidth: proposal.width)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = measuredRows(for: subviews, proposalWidth: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func measuredRows(for subviews: Subviews, proposalWidth: CGFloat?) -> [TagFlowRow] {
        let maxWidth = max(0, proposalWidth ?? .greatestFiniteMagnitude)
        var rows: [TagFlowRow] = []
        var currentItems: [TagFlowItem] = []
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0

        func finishRow() {
            guard !currentItems.isEmpty else { return }
            rows.append(TagFlowRow(items: currentItems, width: x, height: rowHeight, y: y))
            y += rowHeight + verticalSpacing
            currentItems = []
            x = 0
            rowHeight = 0
        }

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = currentItems.isEmpty ? CGFloat(0) : horizontalSpacing
            if !currentItems.isEmpty, x + spacing + size.width > maxWidth {
                finishRow()
            }

            let itemX = currentItems.isEmpty ? CGFloat(0) : x + horizontalSpacing
            currentItems.append(TagFlowItem(index: index, x: itemX, size: size))
            x = itemX + size.width
            rowHeight = max(rowHeight, size.height)
        }

        finishRow()
        return rows
    }

    private struct TagFlowRow {
        var items: [TagFlowItem]
        var width: CGFloat
        var height: CGFloat
        var y: CGFloat
    }

    private struct TagFlowItem {
        var index: Int
        var x: CGFloat
        var size: CGSize
    }
}

private extension PaperTableColumn {
    var isEditableFromPaperTable: Bool {
        switch self {
        case .addedTime, .editedTime, .tags, .attachmentStatus:
            return false
        default:
            return true
        }
    }

    var prefersMultilineEditor: Bool {
        switch self {
        case .title, .englishTitle, .authors, .authorsEnglish, .source, .note, .abstractText, .chineseAbstract, .rqs, .conclusion, .results, .participantType,
             .variables, .dataCollection, .dataAnalysis, .methodology, .theoreticalFoundation,
             .keywords, .limitations:
            return true
        default:
            return false
        }
    }
}

private struct TableCellEditSheet: View {
    let title: String
    @Binding var value: String
    let isMultiline: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            if isMultiline {
                TextEditor(text: $value)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .frame(minHeight: 240, maxHeight: 320)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
                    )
            } else {
                TextField("Value", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 560, maxWidth: 720)
    }
}

private struct AbstractColumnSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var selection: AbstractDisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(chinese: "摘要列设置", english: "Abstract Column Settings"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localized(chinese: "完成", english: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized(chinese: "摘要语言", english: "Abstract Language"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selection) {
                    ForEach(AbstractDisplayLanguage.allCases) { option in
                        Text(option.title(for: language)).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Text(
                localized(
                    chinese: "“原文”显示文献原始摘要；切换到中文或英文时，会优先显示已有缓存，缺失时再通过当前 API 设置补齐翻译。",
                    english: "Original shows the source abstract. Chinese and English prefer cached text first, then fill missing translations with the current API settings."
                )
            )
            .font(.system(size: 12.5, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct TitleColumnSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var selection: AbstractDisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(chinese: "标题列设置", english: "Title Column Settings"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localized(chinese: "完成", english: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized(chinese: "默认显示语言", english: "Default Language"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selection) {
                    ForEach(AbstractDisplayLanguage.allCases) { option in
                        Text(option.title(for: language)).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Text(
                localized(
                    chinese: "中文和英文标题会分别缓存；缺少对应语言时，使用当前 API 设置补齐翻译。",
                    english: "Chinese and English titles are cached separately. Missing text is translated with the current API settings."
                )
            )
            .font(.system(size: 12.5, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct ImpactFactorColumnSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var apiKey: String
    @Binding var fields: String
    @Binding var abbreviations: String
    @Binding var colorHexes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(chinese: "影响因子列设置", english: "Impact Factor Column Settings"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localized(chinese: "完成", english: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel(localized(chinese: "easyScholar 密钥", english: "easyScholar Key"))
                SecureField("", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                settingsFieldLabel(localized(chinese: "需要显示的领域", english: "Displayed Fields"))
                TextEditor(text: $fields)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))

                settingsFieldLabel(localized(chinese: "简写方式", english: "Abbreviations"))
                TextEditor(text: $abbreviations)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22)))

                settingsFieldLabel(localized(chinese: "等级颜色", english: "Rank Colors"))
                TextField("#ffe2dd, #e8deee, #dbeddb, #fadec9, #e9e8e7", text: $colorHexes)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func settingsFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct TimeColumnSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var dateFormat: String

    private var sampleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = resolvedFormat
        return formatter.string(from: Date(timeIntervalSince1970: 1_776_888_123.456))
    }

    private var resolvedFormat: String {
        let trimmed = dateFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SettingsStore.defaultPaperTimestampDateFormat : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(chinese: "时间列设置", english: "Time Column Settings"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localized(chinese: "完成", english: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsFieldLabel(localized(chinese: "时间格式", english: "Date Format"))
                TextField(SettingsStore.defaultPaperTimestampDateFormat, text: $dateFormat)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localized(chinese: "预览：\(sampleText)", english: "Preview: \(sampleText)"))
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(localized(
                    chinese: "自定义规则：yyyy=四位年份，MM=月份，dd=日期，HH=24小时，mm=分钟，ss=秒，SSS=毫秒。常用示例：yyyy-MM-dd HH:mm、yyyy/MM/dd、MM-dd HH:mm:ss。留空会恢复默认格式。",
                    english: "Custom tokens: yyyy=four-digit year, MM=month, dd=day, HH=24-hour, mm=minute, ss=second, SSS=milliseconds. Examples: yyyy-MM-dd HH:mm, yyyy/MM/dd, MM-dd HH:mm:ss. Empty uses the default format."
                ))
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(localized(chinese: "恢复默认", english: "Restore Default")) {
                    dateFormat = SettingsStore.defaultPaperTimestampDateFormat
                }
                Spacer()
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520)
    }

    private func settingsFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct TagColumnSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    @Binding var displayMode: TagColumnDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localized(chinese: "标签列设置", english: "Tag Column Settings"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(localized(chinese: "完成", english: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsFieldLabel(localized(chinese: "标签显示方式", english: "Tag Display Mode"))

                Picker("", selection: $displayMode) {
                    ForEach(TagColumnDisplayMode.allCases) { mode in
                        Text(mode.title(for: language)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Text(localized(
                chinese: "色彩模式只显示标签颜色圆点；文字模式显示标签文字，文字使用标签色，并用同色浅底高亮。",
                english: "Color mode shows only colored dots. Text mode shows tag names in their tag color with a light matching highlight."
            ))
            .font(.system(size: 12.5, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func settingsFieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct APILinkPopover: View {
    @Binding var endpoint: String
    @Binding var model: String
    @Binding var apiKey: String
    @Binding var isChecking: Bool
    @Binding var statusText: String
    @Binding var resultText: String
    let onCheckConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("API Link Check")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Endpoint")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("https://api.example.com/v1/chat/completions", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("Qwen/Qwen3.5-27B", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                SecureField("输入 API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
            }

            HStack(spacing: 10) {
                Button("Check Connection") {
                    onCheckConnection()
                }
                .disabled(isChecking)

                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(endpoint, forType: .string)
                }

                Spacer()
            }

            if !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(resultText)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("检测状态")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "等待检测" : statusText)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}

private struct FlowingTranslationRowBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let time = timeline.date.timeIntervalSinceReferenceDate
                let drift = CGFloat((sin(time * 0.72) + 1) / 2)
                let verticalDrift = CGFloat((cos(time * 0.53) + 1) / 2)

                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.82).opacity(0.42),
                            Color(red: 1.00, green: 0.92, blue: 0.62).opacity(0.38),
                            Color(red: 0.72, green: 0.92, blue: 0.78).opacity(0.40),
                            Color(red: 0.66, green: 0.86, blue: 1.00).opacity(0.38),
                            Color(red: 0.84, green: 0.75, blue: 1.00).opacity(0.40),
                            Color(red: 1.00, green: 0.78, blue: 0.90).opacity(0.36)
                        ],
                        startPoint: UnitPoint(x: 0, y: verticalDrift),
                        endPoint: UnitPoint(x: 1, y: 1 - verticalDrift)
                    )
                    .frame(width: width * 2.4, height: height)
                    .offset(x: -width * 1.2 + drift * width, y: 0)
                    .overlay(Color.white.opacity(0.28))
                }
                .frame(width: width, height: height)
                .clipped()
            }
        }
    }
}

private struct TranslationProgressRing: View {
    let phase: TranslationTaskPhase
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: trimValue)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if phase == .failed {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(ringColor)
            }
        }
        .frame(width: 16, height: 16)
    }

    private var trimValue: Double {
        switch phase {
        case .queued:
            return 0.08
        case .running:
            return min(max(progress, 0.16), 0.96)
        case .completed:
            return 1
        case .failed:
            return 1
        }
    }

    private var ringColor: Color {
        switch phase {
        case .queued:
            return .secondary.opacity(0.75)
        case .running:
            return Color(red: 0.08, green: 0.48, blue: 0.92)
        case .completed:
            return Color(red: 0.18, green: 0.62, blue: 0.32)
        case .failed:
            return Color(red: 0.86, green: 0.20, blue: 0.18)
        }
    }
}

private struct ImportActionsPopover: View {
    let language: AppLanguage
    let canImportDOI: Bool
    let onImportPDF: () -> Void
    let onImportBibTeX: () -> Void
    let onImportLitrix: () -> Void
    let onImportDOI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized(chinese: "导入", english: "Import"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Divider()

            Button(localized(chinese: "导入 PDF…", english: "Import PDF…"), action: onImportPDF)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized(chinese: "导入 BibTeX…", english: "Import BibTeX…"), action: onImportBibTeX)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized(chinese: "导入 Litrix…", english: "Import Litrix…"), action: onImportLitrix)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(localized(chinese: "通过 DOI 添加…", english: "Add via DOI…"), action: onImportDOI)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 260)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct ExportActionsPopover: View {
    let language: AppLanguage
    let isPaperExportDisabled: Bool
    let onExportBibTeX: () -> Void
    let onExportDetailed: () -> Void
    let onExportAttachments: () -> Void
    let onExportLitrix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized(chinese: "导出", english: "Export"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Divider()

            Button(localized(chinese: "导出 BibTeX…", english: "Export BibTeX…"), action: onExportBibTeX)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized(chinese: "导出详细信息…", english: "Export Detailed…"), action: onExportDetailed)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized(chinese: "导出附件…", english: "Export Attachments…"), action: onExportAttachments)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized(chinese: "导出 Litrix…", english: "Export Litrix…"), action: onExportLitrix)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 280)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct CustomRefreshFieldChooserPopover: View {
    @Binding var selectedFields: [MetadataField]
    let language: AppLanguage
    let onRun: () -> Void

    private func binding(for field: MetadataField) -> Binding<Bool> {
        Binding(
            get: { selectedFields.contains(field) },
            set: { isSelected in
                var updated = selectedFields
                if isSelected {
                    if !updated.contains(field) {
                        updated.append(field)
                    }
                } else {
                    updated.removeAll { $0 == field }
                }
                selectedFields = MetadataField.allCases.filter { updated.contains($0) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(chinese: "自定义刷新", english: "Custom Refresh"))
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MetadataField.allCases) { field in
                        Toggle(field.displayName(for: language), isOn: binding(for: field))
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)

            Divider()

            Button(localized(chinese: "执行自定义刷新", english: "Run Custom Refresh"), action: onRun)
                .disabled(selectedFields.isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

// macOS-style rounded-rect card shown briefly while the paper table re-attaches
// after switching back from the image gallery view.
private struct CenterPaneLoadingOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .frame(width: 76, height: 76)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 6)
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
        }
    }
}

private struct ToolbarGlassOrb: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ToolbarGlassOrbView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ToolbarGlassOrbView: NSView {
    private var nativeGlassView: NSView?
    private let fallbackView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        nativeGlassView?.frame = bounds
        fallbackView.frame = bounds
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            addSubview(glass)
            nativeGlassView = glass
        } else {
            fallbackView.frame = bounds
            fallbackView.autoresizingMask = [.width, .height]
            fallbackView.material = .headerView
            fallbackView.blendingMode = .behindWindow
            fallbackView.state = .active
            addSubview(fallbackView)
        }
    }
}

private final class ToolbarGlassBackdropView: NSView {
    private var nativeGlassView: NSView?
    private let effectView = NSVisualEffectView()
    private let gradientView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let highlightLayer = CAGradientLayer()
    private let dividerView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        nativeGlassView?.frame = bounds
        effectView.frame = bounds
        gradientView.frame = bounds
        gradientLayer.frame = gradientView.bounds
        highlightLayer.frame = gradientView.bounds
        dividerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            addSubview(glass)
            nativeGlassView = glass
        } else {
            effectView.frame = bounds
            effectView.autoresizingMask = [.width, .height]
            effectView.material = .headerView
            effectView.blendingMode = .withinWindow
            effectView.state = .active
            addSubview(effectView)
        }

        gradientView.frame = bounds
        gradientView.autoresizingMask = [.width, .height]
        gradientView.wantsLayer = true
        gradientView.layer?.masksToBounds = true
        addSubview(gradientView)

        gradientLayer.colors = [
            NSColor.white.withAlphaComponent(0.40).cgColor,
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.white.withAlphaComponent(0.30).cgColor
        ]
        gradientLayer.locations = [0, 0.58, 1]
        gradientLayer.startPoint = CGPoint(x: 0.08, y: 1)
        gradientLayer.endPoint = CGPoint(x: 0.92, y: 0)
        gradientView.layer?.addSublayer(gradientLayer)

        highlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.48).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor
        ]
        highlightLayer.locations = [0, 1]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 1)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientView.layer?.addSublayer(highlightLayer)

        dividerView.wantsLayer = true
        dividerView.autoresizingMask = [.width, .maxYMargin]
        dividerView.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(0.18)
            .cgColor
        addSubview(dividerView)
    }
}

private struct SidebarLiquidGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SidebarLiquidGlassBackgroundView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SidebarLiquidGlassBackgroundView: NSView {
    private var nativeGlassView: NSView?
    private let fallbackView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        nativeGlassView?.frame = bounds
        fallbackView.frame = bounds
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            // NavigationSplitView on macOS 26 provides liquid glass natively.
            // Adding a custom glass layer here conflicts with and obscures it.
        } else {
            fallbackView.frame = bounds
            fallbackView.autoresizingMask = [.width, .height]
            fallbackView.material = .sidebar
            fallbackView.blendingMode = .behindWindow
            fallbackView.state = .active
            addSubview(fallbackView)
        }
    }
}

private struct InspectorNativeGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        InspectorNativeGlassBackgroundView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class InspectorNativeGlassBackgroundView: NSView {
    private var nativeGlassView: NSView?
    private let fallbackView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        nativeGlassView?.frame = bounds
        fallbackView.frame = bounds
    }

    private func setupBackground() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.tintColor = .clear
            addSubview(glass)
            nativeGlassView = glass
        } else {
            fallbackView.frame = bounds
            fallbackView.autoresizingMask = [.width, .height]
            fallbackView.material = .underWindowBackground
            fallbackView.blendingMode = .withinWindow
            fallbackView.state = .active
            addSubview(fallbackView)
        }
    }
}

private struct ScrollElasticityConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(from: nsView)
        }
    }

    private func configure(from view: NSView) {
        if let scrollView = view.enclosingScrollView {
            apply(to: scrollView)
            return
        }

        var current: NSView? = view
        while let node = current {
            if let scrollView = node as? NSScrollView {
                apply(to: scrollView)
                return
            }
            current = node.superview
        }
    }

    private func apply(to scrollView: NSScrollView) {
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct SidebarItemRow: View {
    let title: String
    let count: Int
    let systemImage: String
    let isHovered: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SidebarLayoutMetrics.itemSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(rowForeground)
                .frame(width: SidebarLayoutMetrics.iconWidth, alignment: .center)
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(rowForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: SidebarLayoutMetrics.itemSpacing)
            SidebarCountText(count: count, isSelected: isSelected)
        }
        .padding(.leading, SidebarLayoutMetrics.contentLeading)
        .padding(.trailing, SidebarLayoutMetrics.contentTrailing)
        .frame(height: 30)
        .background(
            sidebarCursorBackground(isHovered: isHovered, isSelected: isSelected)
                .padding(.horizontal, -SidebarLayoutMetrics.cursorHorizontalOutset)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(SidebarLayoutMetrics.rowInsets)
    }

    private var rowForeground: Color {
        .secondary
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textCase(nil)
        .padding(.top, 8)
        .padding(.leading, SidebarLayoutMetrics.contentLeading)
        .padding(.trailing, SidebarLayoutMetrics.contentTrailing)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(SidebarLayoutMetrics.rowInsets)
    }
}

private struct SidebarCollapsibleHeader: View {
    let title: String
    let isCollapsed: Bool
    let isHovered: Bool
    let onAdd: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: SidebarLayoutMetrics.itemSpacing) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)

            Button(action: onToggle) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 1 : 0)
        }
        .contentShape(Rectangle())
        .textCase(nil)
        .padding(.leading, SidebarLayoutMetrics.contentLeading)
        .padding(.trailing, SidebarLayoutMetrics.contentTrailing)
        .frame(height: 30)
        .background(
            sidebarCursorBackground(isHovered: isHovered, isSelected: false)
                .padding(.horizontal, -SidebarLayoutMetrics.cursorHorizontalOutset)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }
}

private struct SidebarTaxonomyRow: View {
    let title: String
    let count: Int
    let systemImage: String?
    let color: Color?
    let iconTint: Color?
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isHovered: Bool
    let isSelected: Bool
    let dropPlacement: TaxonomyDropPlacement?
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if dropPlacement == .sibling {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(height: 2)
                    .padding(.leading, CGFloat(depth) * 12 + 26)
                    .padding(.trailing, 42)
            }

            HStack(spacing: SidebarLayoutMetrics.itemSpacing) {
                leadingGlyph
                    .frame(width: SidebarLayoutMetrics.iconWidth, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(rowForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SidebarCountText(count: count, isSelected: isSelected)
            }
            .padding(.leading, SidebarLayoutMetrics.contentLeading + CGFloat(depth) * SidebarLayoutMetrics.taxonomyIndent)
            .padding(.trailing, SidebarLayoutMetrics.contentTrailing)
            .frame(height: 30)
            .background(
                sidebarCursorBackground(
                    isHovered: isHovered,
                    isSelected: isSelected,
                    accentOverride: dropPlacement == .child ? Color.primary.opacity(0.12) : nil
                )
                .padding(.horizontal, -SidebarLayoutMetrics.cursorHorizontalOutset)
            )
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(SidebarLayoutMetrics.rowInsets)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(iconTint ?? color ?? rowForeground)
        } else if let color {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay {
                    if depth == 0 && hasChildren {
                        Circle()
                            .stroke(Color.black.opacity(0.82), lineWidth: 1.2)
                            .frame(width: 14, height: 14)
                    }
                }
        }
    }

    private var rowForeground: Color {
        isSelected ? .primary : .primary.opacity(0.72)
    }
}

private struct SidebarCountText: View {
    let count: Int
    var isSelected = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(isSelected ? Color.primary.opacity(0.55) : .secondary.opacity(0.68))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: SidebarLayoutMetrics.countWidth, alignment: .trailing)
    }
}

private enum SidebarLayoutMetrics {
    static let contentLeading: CGFloat = 0   // 左侧图标/文字整体往右或往左
    static let contentTrailing: CGFloat = 0  // 右侧计数数字整体往左或往右
    static let iconWidth: CGFloat = 18        // 图标占位宽度
    static let itemSpacing: CGFloat = 7       // 图标和文字间距
    static let taxonomyIndent: CGFloat = 10   // 分类/标签每级缩进
    static let countWidth: CGFloat = 42       // 计数数字列宽
    static let cursorHorizontalOutset: CGFloat = 8 // 灰色光标左右延长量；调大更长，调小更短
    static let rowInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

private func sidebarCursorBackground(
    isHovered: Bool,
    isSelected: Bool,
    accentOverride: Color? = nil
) -> some View {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(
            accentOverride
                ?? (isSelected ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.045) : Color.clear))
        )
}

private struct SidebarPlaceholderRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }
}

private struct InlineRenameSidebarRow: View {
    let systemImage: String?
    var leadingDotColor: Color? = nil
    var indentationLevel = 0
    @Binding var name: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let leadingDotColor {
                Circle()
                    .fill(leadingDotColor)
                    .frame(width: 12, height: 12)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .frame(width: 16, alignment: .leading)
            }

            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                .onSubmit(onSubmit)
                .onExitCommand(perform: onCancel)

            Spacer(minLength: 8)
        }
        .padding(.leading, CGFloat(indentationLevel) * 12)
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}

private struct TaxonomyRowDropDelegate: DropDelegate {
    let kind: TaxonomyKind
    let target: TaxonomyNode
    @Binding var draggingPath: String?
    @Binding var draggingKind: TaxonomyKind?
    @Binding var dropTarget: TaxonomyDropTarget?
    let onMove: (String, String, TaxonomyDropPlacement) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard draggingKind == kind,
              let draggingPath,
              draggingPath != target.path else { return false }
        return !TaxonomyHierarchy.isDescendant(target.path, of: draggingPath)
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropTarget = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingPath = nil
            draggingKind = nil
            dropTarget = nil
        }
        guard validateDrop(info: info),
              let source = draggingPath else {
            return false
        }
        let placement = dropTarget?.placement ?? placement(for: info)
        onMove(source, target.path, placement)
        return true
    }

    private func updateDropTarget(info: DropInfo) {
        guard validateDrop(info: info) else {
            dropTarget = nil
            return
        }
        dropTarget = TaxonomyDropTarget(kind: kind, path: target.path, placement: placement(for: info))
    }

    private func placement(for info: DropInfo) -> TaxonomyDropPlacement {
        let topSiblingZone: CGFloat = 4
        if info.location.y <= topSiblingZone {
            return .sibling
        }
        if target.depth + 1 < TaxonomyHierarchy.maximumDepth {
            return .child
        }
        return .sibling
    }
}

private struct InlineCollectionCreator: View {
    @Binding var name: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        TextField("New Collection", text: $name)
            .textFieldStyle(.plain)
            .focused(isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isFocused.wrappedValue ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
            .onSubmit(onSubmit)
            .onExitCommand(perform: onCancel)
            .onAppear {
                DispatchQueue.main.async {
                    isFocused.wrappedValue = true
                }
            }
            .listRowBackground(Color.clear)
    }
}

private struct TaxonomyCreationSheet: View {
    let kind: TaxonomyKind
    @Binding var name: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建\(kind.title)")
                .font(.title2.weight(.semibold))

            TextField("请输入\(kind.title)名称", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct TaxonomyEditSheet: View {
    let kind: TaxonomyKind
    @Binding var title: String
    @Binding var itemDescription: String
    @Binding var iconSystemName: String
    @Binding var color: Color
    let onCancel: () -> Void
    let onSave: () -> Void

    private let icons = [
        "folder", "folder.fill", "tray", "archivebox",
        "tag", "circle.fill", "bookmark", "doc.text",
        "books.vertical", "graduationcap", "briefcase", "star"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("主标题")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("描述")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                TextField("", text: $itemDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack {
                Text("图标")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Picker("", selection: $iconSystemName) {
                    ForEach(icons, id: \.self) { icon in
                        Image(systemName: icon).tag(icon)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 74)
            }

            HStack {
                Text("颜色")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 74)
            }

            Button("更新", action: onSave)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if iconSystemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                iconSystemName = kind == .collection ? "folder" : "circle.fill"
            }
        }
    }
}

private struct DOIImportSheet: View {
    @Binding var doi: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add via DOI")
                .font(.title2.weight(.semibold))

            Text("Fetch metadata from Crossref and add a metadata-only paper entry.")
                .foregroundStyle(.secondary)

            TextField("10.1080/2159676X.2019.1628806", text: $doi)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Import", action: onImport)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

private struct PaperInspectorModern: View {
    @Binding var paper: Paper
    @Binding var metadataOrder: [InspectorMetadataField]
    let language: AppLanguage
    let allCollections: [String]
    let allTags: [String]
    let tagColorHexes: [String: String]
    let imageURLs: [URL]
    let isUpdatingMetadata: Bool
    let onRefreshAllMetadata: () -> Void
    let onRefreshMissingMetadata: () -> Void
    let onCustomRefreshMetadata: () -> Void
    let onExportBibTeX: () -> Void
    let onPasteImage: () -> Void
    let onRevealImage: (String) -> Void
    let onDeleteImage: (String) -> Void
    let onHoverImagePreview: (URL?) -> Void
    let onAssignCollection: (String, Bool) -> Void
    let onAssignTag: (String, Bool) -> Void
    @State private var draggingMetadataField: InspectorMetadataField?

    var body: some View {
        VStack(spacing: 0) {
            // Spacer to push content below the window toolbar area
            Color.clear
                .frame(height: 0)
                .padding(.top, 18)

            inspectorTopCard
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.clear)

            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inspectorSection(localized(chinese: "文库", english: "LIBRARY")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized(chinese: "评分", english: "Rating"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        StarRatingView(rating: $paper.rating, starSize: 14, showsLabel: false)
                    }

                    TaxonomyChipEditor(
                        language: language,
                        title: localized(chinese: "分类", english: "Collections"),
                        items: paper.collections,
                        availableItems: allCollections,
                        emptyText: localized(chinese: "暂无分类", english: "No Collections"),
                        newItemLabel: localized(chinese: "新建分类", english: "New Collection"),
                        colorForItem: { _ in nil },
                        onAdd: addCollection,
                        onRemove: removeCollection
                    )

                    TaxonomyChipEditor(
                        language: language,
                        title: localized(chinese: "标签", english: "Tags"),
                        items: paper.tags,
                        availableItems: allTags,
                        emptyText: localized(chinese: "暂无标签", english: "No Tags"),
                        newItemLabel: localized(chinese: "新建标签", english: "New Tag"),
                        colorForItem: tagColor(for:),
                        onAdd: addTag,
                        onRemove: removeTag
                    )
                }

                if hasInspectorContent {
                    inspectorSection(localized(chinese: "内容", english: "CONTENT")) {
                        if hasAbstractText {
                            modernEditorBlock(
                                localized(chinese: "摘要", english: "Abstract"),
                                text: $paper.abstractText,
                                minHeight: 120
                            )
                        }
                        if hasChineseAbstractText {
                            modernEditorBlock(
                                localized(chinese: "中文摘要", english: "Chinese Abstract"),
                                text: $paper.chineseAbstract,
                                minHeight: 120
                            )
                        }
                        if hasNotesText {
                            modernEditorBlock(
                                localized(chinese: "笔记", english: "Note"),
                                text: $paper.notes,
                                minHeight: 140
                            )
                        }
                    }
                }

                inspectorSection(localized(chinese: "元数据", english: "METADATA")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized(chinese: "拖动字段名可调整元数据顺序。", english: "Drag rows to reorder metadata fields."))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(metadataOrder, id: \.self) { field in
                            MetadataRowEditor(
                                title: field.displayName(for: language),
                                text: binding(for: field),
                                placeholder: field.placeholder(for: language),
                                multiline: field.prefersMultiline,
                                onTitleDrag: {
                                    draggingMetadataField = field
                                    return NSItemProvider(object: NSString(string: field.rawValue))
                                }
                            )
                            .onDrop(
                                of: [UTType.text],
                                delegate: MetadataFieldDropDelegate(
                                    target: field,
                                    order: $metadataOrder,
                                    dragging: $draggingMetadataField
                                )
                            )
                        }
                    }
                }

                inspectorSection(localized(chinese: "图片", english: "IMAGE")) {
                    HStack {
                        Button(localized(chinese: "粘贴图片", english: "Paste Image"), action: onPasteImage)
                        Text(localized(chinese: "\(imageURLs.count) 张", english: "\(imageURLs.count) image(s)"))
                            .foregroundStyle(.secondary)
                    }

                    if imageURLs.isEmpty {
                        Text("暂无图片")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(imageURLs, id: \.self) { url in
                            StoredImageRow(
                                url: url,
                                onReveal: { onRevealImage(url.lastPathComponent) },
                                onDelete: { onDeleteImage(url.lastPathComponent) },
                                onHoverChanged: { hovering in
                                    onHoverImagePreview(hovering ? url : nil)
                                }
                            )
                        }
                    }
                }

                inspectorSection(localized(chinese: "操作", english: "ACTIONS")) {
                    HStack(spacing: 10) {
                        Button(localized(chinese: "刷新全部", english: "Refresh All"), action: onRefreshAllMetadata)
                        Button(localized(chinese: "刷新缺失", english: "Refresh Missing"), action: onRefreshMissingMetadata)
                        Button(localized(chinese: "自定义刷新...", english: "Custom Refresh..."), action: onCustomRefreshMetadata)
                        Button(localized(chinese: "导出 BibTeX", english: "Export BibTeX"), action: onExportBibTeX)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
            .scrollContentBackground(.hidden)
            .background(ScrollElasticityConfigurator())
        }
        .onAppear {
            normalizeMetadataOrder()
        }
        .onDisappear {
            onHoverImagePreview(nil)
        }
    }

    private var inspectorTopCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !paper.paperType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(paper.paperType.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }

            TextField(localized(chinese: "标题", english: "Title"), text: $paper.title, axis: .vertical)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                TextField(localized(chinese: "来源", english: "Source"), text: $paper.source, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField(localized(chinese: "年份", english: "Year"), text: $paper.year)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
            }

            TextField(localized(chinese: "作者", english: "Authors"), text: $paper.authors)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if isUpdatingMetadata {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var hasAbstractText: Bool {
        !paper.abstractText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChineseAbstractText: Bool {
        !paper.chineseAbstract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasNotesText: Bool {
        !paper.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasInspectorContent: Bool {
        hasAbstractText || hasChineseAbstractText || hasNotesText
    }

    private func normalizeMetadataOrder() {
        var normalized: [InspectorMetadataField] = []
        for field in metadataOrder where !normalized.contains(field) {
            normalized.append(field)
        }
        for field in InspectorMetadataField.defaultOrder where !normalized.contains(field) {
            normalized.append(field)
        }
        metadataOrder = normalized
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }

    private func tagColor(for tag: String) -> Color? {
        guard let hex = tagColorHexes[tag] else { return nil }
        let value = hex.replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let intValue = Int(value, radix: 16) else { return nil }
        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    private func addCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssignCollection(trimmed, true)
        if !paper.collections.contains(trimmed) {
            paper.collections.append(trimmed)
            paper.collections.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    private func removeCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssignCollection(trimmed, false)
        paper.collections.removeAll { $0 == trimmed }
    }

    private func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssignTag(trimmed, true)
        if !paper.tags.contains(trimmed) {
            paper.tags.append(trimmed)
            paper.tags.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }

    private func removeTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAssignTag(trimmed, false)
        paper.tags.removeAll { $0 == trimmed }
    }

    private func binding(for field: InspectorMetadataField) -> Binding<String> {
        switch field {
        case .year:
            return $paper.year
        case .source:
            return $paper.source
        case .doi:
            return $paper.doi
        case .volume:
            return $paper.volume
        case .issue:
            return $paper.issue
        case .pages:
            return $paper.pages
        case .paperType:
            return $paper.paperType
        case .rqs:
            return $paper.rqs
        case .conclusion:
            return $paper.conclusion
        case .results:
            return $paper.results
        case .category:
            return $paper.category
        case .impactFactor:
            return $paper.impactFactor
        case .samples:
            return $paper.samples
        case .participantType:
            return $paper.participantType
        case .variables:
            return $paper.variables
        case .dataCollection:
            return $paper.dataCollection
        case .dataAnalysis:
            return $paper.dataAnalysis
        case .methodology:
            return $paper.methodology
        case .theoreticalFoundation:
            return $paper.theoreticalFoundation
        case .educationalLevel:
            return $paper.educationalLevel
        case .country:
            return $paper.country
        case .keywords:
            return $paper.keywords
        case .limitations:
            return $paper.limitations
        }
    }

    @ViewBuilder
    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func modernEditorBlock(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TaxonomyChipEditor: View {
    let language: AppLanguage
    let title: String
    let items: [String]
    let availableItems: [String]
    let emptyText: String
    let newItemLabel: String
    let colorForItem: (String) -> Color?
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    @State private var isAddingCustomItem = false
    @State private var customItemDraft = ""

    private var sortedItems: [String] {
        items.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableToAdd: [String] {
        availableItems
            .filter { !items.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if sortedItems.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedItems, id: \.self) { item in
                            taxonomyChip(item: item)
                        }
                    }

                    Menu {
                        if availableToAdd.isEmpty {
                            Text(localized(chinese: "没有可添加的\(title)", english: "No Existing \(title)"))
                        } else {
                            ForEach(availableToAdd, id: \.self) { available in
                                Button(available) {
                                    onAdd(available)
                                }
                            }
                        }

                        Divider()

                        Button(newItemLabel) {
                            customItemDraft = ""
                            isAddingCustomItem = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .popover(isPresented: $isAddingCustomItem, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(newItemLabel)
                                .font(.headline)
                            TextField("Name", text: $customItemDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCustomItem)
                            HStack {
                                Button("Cancel") {
                                    isAddingCustomItem = false
                                }
                                Spacer()
                                Button("Add") {
                                    addCustomItem()
                                }
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                        .padding(14)
                        .frame(width: 260)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func taxonomyChip(item: String) -> some View {
        HStack(spacing: 6) {
            if let color = colorForItem(item) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }

            Text(item)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .lineLimit(1)

            Button {
                onRemove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func addCustomItem() {
        let trimmed = customItemDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isAddingCustomItem = false
            return
        }
        onAdd(trimmed)
        isAddingCustomItem = false
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct MetadataRowEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let multiline: Bool
    let onTitleDrag: (() -> NSItemProvider)?

    init(
        title: String,
        text: Binding<String>,
        placeholder: String,
        multiline: Bool,
        onTitleDrag: (() -> NSItemProvider)? = nil
    ) {
        self.title = title
        _text = text
        self.placeholder = placeholder
        self.multiline = multiline
        self.onTitleDrag = onTitleDrag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onDrag {
                    onTitleDrag?() ?? NSItemProvider()
                }

            if multiline {
                ZStack(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                    }

                    TextEditor(text: $text)
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .frame(minHeight: 72)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct MetadataFieldDropDelegate: DropDelegate {
    let target: InspectorMetadataField
    @Binding var order: [InspectorMetadataField]
    @Binding var dragging: InspectorMetadataField?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else {
            return
        }

        if order[to] != dragging {
            withAnimation(.easeInOut(duration: 0.15)) {
                order.move(
                    fromOffsets: IndexSet(integer: from),
                    toOffset: to > from ? to + 1 : to
                )
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct StoredImageRow: View {
    let url: URL
    let onReveal: () -> Void
    let onDelete: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImageView(url: url, maxPixel: 120, placeholderOpacity: 0.15)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .scaleEffect(isHovered ? 1.05 : 1)
                .shadow(color: Color.black.opacity(isHovered ? 0.16 : 0), radius: isHovered ? 10 : 0, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(isHovered ? 0.30 : 0.18), lineWidth: isHovered ? 1.0 : 0.7)
                )
                .animation(.easeInOut(duration: 0.14), value: isHovered)

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text(url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("显示", action: onReveal)
            Button("删除", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

private struct ImageMetadataPopoverCard: View {
    let item: ContentView.ImageGalleryItem
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)

            metadataLine(
                label: language == .english ? "Author" : "作者",
                value: item.authors
            )
            metadataLine(
                label: language == .english ? "Year" : "年份",
                value: item.year
            )
            metadataLine(
                label: language == .english ? "Journal" : "期刊",
                value: item.source
            )
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 8)
    }

    @ViewBuilder
    private func metadataLine(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MetadataReturnedContentPrompt: View {
    let content: String
    let onDismiss: () -> Void

    private var displayContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（返回内容为空）" : content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("元数据返回内容无法解析")
                    .font(.headline)
            }

            Text("下面是元数据服务返回的原始内容。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView([.vertical, .horizontal]) {
                Text(displayContent)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            HStack {
                Spacer()
                Button("好") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 400)
    }
}

private struct QuickCitationOverlay: View {
    @Binding var query: String
    @Binding var highlightedPaperID: UUID?
    var isSearchFocused: FocusState<Bool>.Binding
    let statusText: String
    let results: [Paper]
    let onCancel: () -> Void
    let onSubmitQuery: () -> Void
    let onSelectPaper: (Paper) -> Void
    let onMoveSelection: (Int) -> Void

    private var highlightedPaper: Paper? {
        if let highlightedPaperID {
            return results.first(where: { $0.id == highlightedPaperID })
        }
        return results.first
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Search papers, then press Return", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .focused(isSearchFocused)
                        .onSubmit {
                            if let highlightedPaper {
                                onSelectPaper(highlightedPaper)
                            } else {
                                onSubmitQuery()
                            }
                        }

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Text(statusText)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if results.isEmpty {
                    Text("No papers")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    List(results, id: \.id) { paper in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paper.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Paper" : paper.title)
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Text("\(paper.authors.isEmpty ? "Unknown" : paper.authors) · \(paper.year.isEmpty ? "n.d." : paper.year)")
                                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .listRowBackground(
                            (highlightedPaperID == paper.id
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear)
                        )
                        .onTapGesture {
                            highlightedPaperID = paper.id
                        }
                        .onTapGesture(count: 2) {
                            highlightedPaperID = paper.id
                            onSelectPaper(paper)
                        }
                        .onHover { hovering in
                            if hovering {
                                highlightedPaperID = paper.id
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(height: 280)
                }

                HStack(spacing: 10) {
                    Text("Up/Down")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Move selection")
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("⏎")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Insert citation")
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Up") {
                        onMoveSelection(-1)
                    }
                    .buttonStyle(.borderless)

                    Button("Down") {
                        onMoveSelection(1)
                    }
                    .buttonStyle(.borderless)

                    if let highlightedPaper {
                        Button("Insert") {
                            onSelectPaper(highlightedPaper)
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(14)
            .frame(width: 560, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 10)
        }
    }
}

private struct PDFImportProgressOverlay: View {
    let processedCount: Int
    let totalCount: Int
    let statusText: String

    private var progressValue: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(processedCount) / Double(totalCount))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在导入文献")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }

                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)

                Text("\(processedCount)/\(totalCount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
        }
        .allowsHitTesting(true)
    }
}

private extension SystemLibrary {
    func displayTitle(for language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return title
        case .english:
            switch self {
            case .all:
                return "All Papers"
            case .recentReading:
                return "Recent Reading"
            case .zombiePapers:
                return "Zombie Papers"
            case .unfiled:
                return "Unfiled"
            case .missingDOI:
                return "Missing DOI"
            case .missingAttachment:
                return "Missing Attachment"
            case .recentlyDeleted:
                return "Recently Deleted"
            }
        }
    }
}

private extension SidebarSelection {
    func displayTitle(for language: AppLanguage) -> String {
        switch self {
        case .library(let filter):
            return filter.displayTitle(for: language)
        case .collection(let name):
            return name
        case .tag(let name):
            return name
        }
    }
}

@MainActor
private final class TagColorPanelCoordinator: NSObject {
    static let shared = TagColorPanelCoordinator()

    private var activeTag: String?
    private var onChange: ((String, String?) -> Void)?

    func present(
        tag: String,
        initialHex: String?,
        onChange: @escaping (String, String?) -> Void
    ) {
        activeTag = tag
        self.onChange = onChange

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if let initialHex, let color = NSColor(litrixHexString: initialHex) {
            panel.color = color
        }
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc
    private func colorDidChange(_ sender: NSColorPanel) {
        guard let activeTag else { return }
        onChange?(activeTag, sender.color.litrixHexRGB)
    }
}

private extension Color {
    init?(hexString: String) {
        let hex = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let intValue = Int(hex, radix: 16) else { return nil }
        self.init(
            red: Double((intValue >> 16) & 0xFF) / 255.0,
            green: Double((intValue >> 8) & 0xFF) / 255.0,
            blue: Double(intValue & 0xFF) / 255.0
        )
    }

    var hexRGB: String? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB)
        guard let nsColor else { return nil }
        let red = min(max(Int((nsColor.redComponent * 255).rounded()), 0), 255)
        let green = min(max(Int((nsColor.greenComponent * 255).rounded()), 0), 255)
        let blue = min(max(Int((nsColor.blueComponent * 255).rounded()), 0), 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension NSColor {
    convenience init?(litrixHexString: String) {
        let hex = litrixHexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let intValue = Int(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((intValue >> 16) & 0xFF) / 255.0,
            green: CGFloat((intValue >> 8) & 0xFF) / 255.0,
            blue: CGFloat(intValue & 0xFF) / 255.0,
            alpha: 1
        )
    }

    var litrixHexRGB: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension InspectorMetadataField {
    var prefersMultiline: Bool {
        switch self {
        case .rqs, .conclusion, .results, .variables, .dataCollection, .dataAnalysis, .methodology,
             .theoreticalFoundation, .keywords, .limitations:
            return true
        case .year, .source, .doi, .volume, .issue, .pages, .paperType, .category, .impactFactor,
             .samples, .participantType, .educationalLevel, .country:
            return false
        }
    }
}
