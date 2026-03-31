import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var workspace: WorkspaceState
    private static let addedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    @State private var sidebarSelection: SidebarSelection = .library(.all)
    @State private var selectedPaperID: UUID?
    @State private var selectedPaperIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var toolbarSearchField: AdvancedSearchField?
    @State private var isPDFImporterPresented = false
    @State private var isBibTeXImporterPresented = false
    @State private var isLitrixImporterPresented = false
    @State private var isDOIImportSheetPresented = false
    @State private var isImportPopoverPresented = false
    @State private var isExportPopoverPresented = false
    @State private var doiImportDraft = ""
    @State private var isDOIImportAvailable = true
    @State private var taxonomySheetKind: TaxonomyKind?
    @State private var taxonomyDraftName = ""
    @State private var isCreatingCollectionInline = false
    @State private var alertMessage: String?
    @State private var updatingPaperIDs: Set<UUID> = []
    @State private var metadataRefreshQueue: [MetadataRefreshQueueItem] = []
    @State private var metadataRefreshWorkerTask: Task<Void, Never>?
    @State private var metadataPlannedTasks: [TaskStatusEntry] = []
    @State private var metadataCompletedTasks: [TaskStatusEntry] = []
    @State private var translationPlannedTasks: [TaskStatusEntry] = []
    @State private var translationQueuedTasks: [TaskStatusEntry] = []
    @State private var translationCompletedTasks: [TaskStatusEntry] = []
    @State private var translationWatchJobs: [TranslationWatchJob] = []
    @State private var translationWatchTask: Task<Void, Never>?
    @State private var isAPIToolPopoverPresented = false
    @State private var isTaskViewPopoverPresented = false
    @State private var isCheckingAPIConnectionFromTool = false
    @State private var apiToolKeyDraft = ""
    @State private var apiToolEndpointDraft = ""
    @State private var apiToolModelDraft = ""
    @State private var apiToolStatusText = ""
    @State private var apiToolConnectionResult = ""
    @State private var isPDFImportInProgress = false
    @State private var isPDFImportProgressVisible = false
    @State private var pdfImportTask: Task<Void, Never>?
    @State private var pdfImportProcessedCount = 0
    @State private var pdfImportTotalCount = 0
    @State private var pdfImportStatusText = ""
    @State private var localKeyMonitor: Any?
    @State private var didApplyInitialWindowSize = false
    @State private var configuredWindowNumber: Int?
    @State private var windowSizePersistenceObservers: [NSObjectProtocol] = []
    @State private var isDropTargeted = false
    @State private var sortOrder = [KeyPathComparator(\Paper.addedAtMilliseconds, order: .reverse)]
    @State private var isInspectorPanelOnscreen = false
    @State private var rightPaneMode: RightPaneMode = .details
    @State private var lastInspectedPaperID: UUID?
    @State private var hoveredPreviewImageURL: URL?
    @State private var activeQuickLookURL: URL?
    @State private var pendingDeletePaper: Paper?
    @State private var toolbarSearchFocusRequest: UUID?
    @State private var isCollectionsCollapsed = false
    @State private var isTagsCollapsed = false
    @State private var isCollectionsHeaderHovered = false
    @State private var isTagsHeaderHovered = false
    @State private var isCustomRefreshChooserPresented = false
    @State private var customRefreshTargetPaperIDs: [UUID] = []
    @State private var editingCollectionName: String?
    @State private var editingTagName: String?
    @State private var inlineRenameDraft = ""
    @State private var activeCellEditTarget: TableCellEditTarget?
    @State private var cellEditDraft = ""
    @State private var previousSidebarSelection: SidebarSelection = .library(.all)
    @State private var sidebarSelectionMemory: [SidebarSelection: SidebarSelectionState] = [:]
    @State private var cachedSortedPapers: [Paper] = []
    @State private var cachedSortedPaperIDs: [UUID] = []
    @State private var cachedSortedPaperIDSet: Set<UUID> = []
    @State private var cachedSortedPaperIndexByID: [UUID: Int] = [:]
    @State private var cachedAttachmentStatusByID: [UUID: Bool] = [:]
    @State private var cachedImageURLsByID: [UUID: [URL]] = [:]
    @State private var sortedResultIDCache: [SortedResultCacheKey: [UUID]] = [:]
    @State private var sortedResultCacheOrder: [SortedResultCacheKey] = []
    @State private var pendingSortedPapersRecomputeTask: Task<Void, Never>?
    @State private var preserveSelectedRowPositionRequestNonce = UUID()
    @State private var isFilterEnabled = false
    @State private var filterMatchMode: FilterMatchMode = .all
    @State private var filterConditions: [PaperFilterCondition] = []
    @FocusState private var isNewCollectionFieldFocused: Bool
    @FocusState private var isInlineRenameFocused: Bool
    private let inspectorPanelWidth: CGFloat = 360
    private let pdfImportBatchSize = 10
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
    }

    private struct TranslationWatchJob: Identifiable, Hashable {
        var id = UUID()
        var paperID: UUID
        var title: String
        var outputURL: URL
        var launchedAt: Date
    }

    private enum RightPaneMode {
        case details
        case filter
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

    private struct SortedResultCacheKey: Hashable {
        var selection: SidebarSelection
        var searchText: String
        var searchFieldRawValue: String
        var sortSignature: String
        var filterSignature: String
        var recentReadingRange: RecentReadingRange
        var zombieThreshold: ZombiePaperThreshold
        var dataRevision: Int
    }

    var body: some View {
        workspaceRoot
            .background(
                WindowConfigurator { window in
                    configureWindow(window)
                }
            )
            .fileImporter(
                isPresented: $isPDFImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    importPDFsAndAutoEnrich(urls)
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
            .sheet(item: $taxonomySheetKind) { kind in
                TaxonomyCreationSheet(
                    kind: kind,
                    name: $taxonomyDraftName,
                    onSave: {
                        saveTaxonomy(kind: kind)
                    }
                )
                .presentationDetents([.height(220)])
            }
            .sheet(item: $activeCellEditTarget) { target in
                TableCellEditSheet(
                    title: "Edit \(target.column.displayName)",
                    value: $cellEditDraft,
                    isMultiline: target.column.prefersMultilineEditor,
                    onCancel: {
                        activeCellEditTarget = nil
                    },
                    onSave: {
                        saveCellEdit(target)
                    }
                )
                .presentationDetents(target.column.prefersMultilineEditor ? [.height(360)] : [.height(220)])
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
            .confirmationDialog(
                "Delete Paper",
                isPresented: deleteConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingDeletePaper
            ) { paper in
                Button("Delete", role: .destructive) {
                    deletePaper(paper)
                }

                Button("Cancel", role: .cancel) {}
            } message: { paper in
                Text("“\(paper.title.isEmpty ? "Untitled Paper" : paper.title)” will be removed from the library and storage.")
            }
            .popover(isPresented: $isCustomRefreshChooserPresented, arrowEdge: .top) {
                CustomRefreshFieldChooserPopover(
                    selectedFields: Binding(
                        get: { settings.metadataCustomRefreshFields },
                        set: { settings.metadataCustomRefreshFields = $0 }
                    ),
                    onRun: {
                        beginCustomRefreshSelection(forPaperIDs: customRefreshTargetPaperIDs)
                        isCustomRefreshChooserPresented = false
                    }
                )
            }
            .onAppear {
                previousSidebarSelection = sidebarSelection
                recomputeSortedPapers()
                alignSelectionWithVisibleResults()
                workspace.setSelectedPaperID(selectedPaperID)
                installLocalKeyMonitorIfNeeded()
                checkDOIImportAvailability()
            }
            .onDisappear {
                rememberSidebarSelectionState(for: sidebarSelection)
                persistAPIToolDraftsIfNeeded()
                removeLocalKeyMonitor()
                removeWindowSizePersistenceObservers()
                pdfImportTask?.cancel()
                pdfImportTask = nil
                pendingSortedPapersRecomputeTask?.cancel()
                pendingSortedPapersRecomputeTask = nil
                translationWatchTask?.cancel()
                translationWatchTask = nil
            }
            .onChange(of: isAPIToolPopoverPresented) { _, isPresented in
                if !isPresented {
                    persistAPIToolDraftsIfNeeded()
                }
            }
            .onChange(of: sidebarSelection) {
                rememberSidebarSelectionState(for: previousSidebarSelection)
                previousSidebarSelection = sidebarSelection
                restoreSidebarSelectionState(for: sidebarSelection)
                cancelInlineRename()
                scheduleSortedPapersRecompute()
            }
            .onChange(of: searchText) {
                scheduleSortedPapersRecompute(delayNanoseconds: 200_000_000)
            }
            .onChange(of: toolbarSearchField) {
                scheduleSortedPapersRecompute(delayNanoseconds: 120_000_000)
            }
            .onChange(of: sortOrder) {
                scheduleSortedPapersRecompute()
            }
            .onChange(of: store.dataRevision) {
                clearSortedResultIDCache()
                scheduleSortedPapersRecompute(delayNanoseconds: 90_000_000)
            }
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
            .onChange(of: selectedPaperID) {
                workspace.setSelectedPaperID(selectedPaperID)
                if let selectedPaperID {
                    lastInspectedPaperID = selectedPaperID
                }
                hoveredPreviewImageURL = nil
            }
            .onChange(of: selectedPaperIDs) {
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
            .onChange(of: workspace.searchFocusNonce) {
                revealSearchFieldAndFocus()
            }
            .onChange(of: workspace.noteEditorRequestNonce) {
                openNoteEditorWindow()
            }
    }

    private var workspaceRoot: some View {
        workspaceLayout
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar { mainToolbar }
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
    }

    private var workspaceLayout: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        } content: {
            centerPane
        } detail: {
            Color.clear
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.clear)
        .overlay(alignment: .topTrailing) {
            inspectorColumn
                .frame(width: inspectorPanelWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(x: isInspectorPanelOnscreen ? 0 : inspectorPanelWidth)
                .allowsHitTesting(isInspectorPanelOnscreen)
                .accessibilityHidden(!isInspectorPanelOnscreen)
                .animation(inspectorSlideAnimation, value: isInspectorPanelOnscreen)
                .zIndex(1)
        }
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
                language: settings.appLanguage
            )
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)
            .help(settings.appLanguage == .english ? "Search" : "搜索")
            .accessibilityLabel(settings.appLanguage == .english ? "Search" : "搜索")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    isExportPopoverPresented = false
                    isImportPopoverPresented.toggle()
                } label: {
                    toolbarIconLabel("square.and.arrow.down")
                }
                .help("导入")
                .accessibilityLabel("导入")
                .popover(isPresented: $isImportPopoverPresented, arrowEdge: .top) {
                    ImportActionsPopover(
                        canImportDOI: isDOIImportAvailable,
                        onImportPDF: {
                            isImportPopoverPresented = false
                            isPDFImporterPresented = true
                        },
                        onImportBibTeX: {
                            isImportPopoverPresented = false
                            isBibTeXImporterPresented = true
                        },
                        onImportLitrix: {
                            isImportPopoverPresented = false
                            isLitrixImporterPresented = true
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
                    toolbarIconLabel("square.and.arrow.up")
                }
                .help("导出")
                .accessibilityLabel("导出")
                .popover(isPresented: $isExportPopoverPresented, arrowEdge: .top) {
                    ExportActionsPopover(
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

                Button {
                    isTaskViewPopoverPresented = false
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
                    toolbarIconLabel("network")
                }
                .help("API链接测试")
                .accessibilityLabel("API链接测试")
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

                Button {
                    isAPIToolPopoverPresented = false
                    isTaskViewPopoverPresented.toggle()
                } label: {
                    toolbarIconLabel("list.bullet.rectangle.portrait")
                }
                .help("任务情况")
                .accessibilityLabel("任务情况")
                .popover(isPresented: $isTaskViewPopoverPresented, arrowEdge: .top) {
                    MetadataTaskPopover(
                        language: settings.appLanguage,
                        metadataPlanningTitles: metadataPlanningTitles,
                        metadataQueuedTitles: metadataQueuedTitles,
                        metadataCompletedTitles: metadataCompletedTitles,
                        translationPlanningTitles: translationPlanningTitles,
                        translationQueuedTitles: translationQueuedTitles,
                        translationCompletedTitles: translationCompletedTitles
                    )
                    .presentationCompactAdaptation(.none)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    presentRightPane(.filter)
                } label: {
                    toolbarModeToggleLabel(
                        "line.3.horizontal.decrease.circle",
                        isActive: isInspectorPanelOnscreen && rightPaneMode == .filter
                    )
                }
                .help("筛选")
                .accessibilityLabel("筛选")

                Button {
                    presentRightPane(.details)
                } label: {
                    toolbarModeToggleLabel(
                        "info.circle",
                        isActive: isInspectorPanelOnscreen && rightPaneMode == .details
                    )
                }
                .help("详情")
                .accessibilityLabel("详情")
            }
        }
    }

    private var toolbarSearchPlaceholder: String {
        if let toolbarSearchField {
            if settings.appLanguage == .english {
                return "Search \(toolbarSearchField.title)"
            }
            return "搜索\(toolbarSearchField.title)"
        }
        return settings.appLanguage == .english ? "Search" : "搜索"
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        activeRightPane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(InspectorNativeGlassBackground())
            .clipped()
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
    private func toolbarIconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 18, height: 18, alignment: .center)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func toolbarModeToggleLabel(_ systemName: String, isActive: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .frame(width: 18, height: 18, alignment: .center)
            .padding(5)
            .background(
                Circle()
                    .fill(
                        isActive
                            ? Color(red: 0, green: 136.0 / 255.0, blue: 1.0)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
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
            List(selection: $sidebarSelection) {
                Section {
                    ForEach(SystemLibrary.allCases, id: \.self) { item in
                        SidebarItemRow(
                            title: item.displayTitle(for: settings.appLanguage),
                            count: store.count(for: .library(item)),
                            systemImage: item.icon
                        )
                        .tag(SidebarSelection.library(item))
                    }
                } header: {
                    SidebarSectionHeader(title: "Library")
                }

                Section {
                    if !isCollectionsCollapsed {
                        if store.collections.isEmpty {
                            SidebarPlaceholderRow(title: "No Collections")
                        } else {
                            ForEach(store.collections, id: \.self) { collection in
                                Group {
                                    if editingCollectionName == collection {
                                        InlineRenameSidebarRow(
                                            systemImage: "folder",
                                            name: $inlineRenameDraft,
                                            onSubmit: {
                                                saveInlineCollectionRename(original: collection)
                                            },
                                            onCancel: cancelInlineRename
                                        )
                                        .focused($isInlineRenameFocused)
                                    } else {
                                        SidebarItemRow(
                                            title: collection,
                                            count: store.count(for: .collection(collection)),
                                            systemImage: "folder"
                                        )
                                    }
                                }
                                .tag(SidebarSelection.collection(collection))
                                .contextMenu {
                                    Button("Rename") {
                                        beginInlineCollectionRename(collection)
                                    }

                                    Divider()

                                    Button("Delete", role: .destructive) {
                                        if case .collection(let selectedCollection) = sidebarSelection, selectedCollection == collection {
                                            sidebarSelection = .library(.all)
                                        }
                                        store.deleteCollection(named: collection)
                                    }
                                }
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
                        title: "Collections",
                        isCollapsed: isCollectionsCollapsed,
                        showChevron: isCollectionsHeaderHovered || isCollectionsCollapsed,
                        onToggle: { isCollectionsCollapsed.toggle() }
                    )
                        .onHover { isCollectionsHeaderHovered = $0 }
                        .contextMenu {
                            Button("New Collection") {
                                beginInlineCollectionCreation()
                            }
                            Divider()
                            Button(isCollectionsCollapsed ? "Expand" : "Collapse") {
                                isCollectionsCollapsed.toggle()
                            }
                        }
                }

                Section {
                    if !isTagsCollapsed {
                        if store.tags.isEmpty {
                            SidebarPlaceholderRow(title: "No Tags")
                        } else {
                            ForEach(store.tags, id: \.self) { tag in
                                Group {
                                    if editingTagName == tag {
                                        InlineRenameSidebarRow(
                                            systemImage: nil,
                                            leadingDotColor: tagColor(for: tag),
                                            name: $inlineRenameDraft,
                                            onSubmit: {
                                                saveInlineTagRename(original: tag)
                                            },
                                            onCancel: cancelInlineRename
                                        )
                                        .focused($isInlineRenameFocused)
                                    } else {
                                        TagSidebarRow(
                                            title: tag,
                                            count: store.count(for: .tag(tag)),
                                            color: tagColor(for: tag)
                                        )
                                    }
                                }
                                .tag(SidebarSelection.tag(tag))
                                .contextMenu {
                                    Button("Rename") {
                                        beginInlineTagRename(tag)
                                    }

                                    Menu("Quick Number") {
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
                                        Button("Remove Quick Number") {
                                            settings.removeQuickNumber(forTag: tag)
                                        }
                                    }

                                    Menu("Color") {
                                        ForEach(TagPaletteColor.allCases) { paletteColor in
                                            Button {
                                                store.setTagColor(hex: paletteColor.hex, forTag: tag)
                                            } label: {
                                                HStack {
                                                    Circle()
                                                        .fill(colorFromHex(paletteColor.hex))
                                                        .frame(width: 10, height: 10)
                                                    Text(paletteColor.displayName)
                                                    if isTagColorSelected(tag, hex: paletteColor.hex) {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }

                                        Divider()
                                        Button("Remove Color") {
                                            store.setTagColor(hex: nil, forTag: tag)
                                        }
                                    }

                                    Divider()

                                    Button("Delete", role: .destructive) {
                                        if case .tag(let selectedTag) = sidebarSelection, selectedTag == tag {
                                            sidebarSelection = .library(.all)
                                        }
                                        settings.removeQuickNumber(forTag: tag)
                                        store.deleteTag(named: tag)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    SidebarCollapsibleHeader(
                        title: "Tags",
                        isCollapsed: isTagsCollapsed,
                        showChevron: isTagsHeaderHovered || isTagsCollapsed,
                        onToggle: { isTagsCollapsed.toggle() }
                    )
                    .onHover { isTagsHeaderHovered = $0 }
                    .contextMenu {
                        Button("New Tag") {
                            taxonomyDraftName = ""
                            taxonomySheetKind = .tag
                        }

                        Divider()

                        Button(isTagsCollapsed ? "Expand" : "Collapse") {
                            isTagsCollapsed.toggle()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 40)
        }
    }

    private var centerPane: some View {
        VStack(spacing: 0) {
            papersTable
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(16)
                    .overlay {
                        Text("拖拽 PDF 到这里即可导入")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handlePDFDrop(providers:))
    }

    private var papersTable: some View {
        Table(sortedPapers, selection: $selectedPaperIDs, sortOrder: $sortOrder) {
            configuredPaperTableColumns
        }
        .id(paperTableViewIdentity)
        .background(
            TableViewConfigurator(
                autosaveName: "litrix.main.table.columns",
                language: settings.appLanguage,
                columnVisibility: paperTableColumnVisibilityMap,
                columnWidths: paperTableColumnWidthMap,
                rowIDs: cachedSortedPaperIDs,
                desiredColumnOrder: settings.paperTableColumnOrder,
                preserveRowID: selectedPaperID,
                preserveRequestNonce: preserveSelectedRowPositionRequestNonce,
                rowHeightMultiplier: settings.resolvedTableRowHeightMultiplier,
                onSelectRows: { rowIDs, clickedRowID in
                    selectedPaperIDs = Set(rowIDs)
                    if let clickedRowID {
                        selectedPaperID = clickedRowID
                    } else {
                        selectedPaperID = primarySelection(from: selectedPaperIDs)
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
                }
            )
        )
        .overlay {
            if sortedPapers.isEmpty {
                ContentUnavailableView(
                    "还没有文献",
                    systemImage: "books.vertical",
                    description: Text("先导入 PDF，或者直接导入当前工作区下的 /papers。")
                )
            }
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
        "\(paperTableVisibilitySignature)|\(workspace.tableColumnRefreshNonce.uuidString)"
    }

    private var paperTableVisibilitySignature: String {
        PaperTableColumn.allCases.map { column in
            "\(column.rawValue):\(settings.paperTableColumnVisibility[column] ? "1" : "0")"
        }
        .joined(separator: "|")
    }

    private var normalizedPaperTableColumnOrder: [PaperTableColumn] {
        var result: [PaperTableColumn] = []
        for column in settings.paperTableColumnOrder where !result.contains(column) {
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
        case .rqs: metadataTableColumn("RQs", value: \.rqs, column: .rqs)
        case .conclusion: metadataTableColumn("Conclusion", value: \.conclusion, column: .conclusion)
        case .results: metadataTableColumn("Results", value: \.results, column: .results)
        case .category: metadataTableColumn("Category", value: \.category, column: .category)
        case .impactFactor: metadataTableColumn("IF", value: \.impactFactor, column: .impactFactor)
        case .samples: metadataTableColumn("Samples", value: \.samples, column: .samples)
        case .participantType: metadataTableColumn("Participant Type", value: \.participantType, column: .participantType)
        case .variables: metadataTableColumn("Variables", value: \.variables, column: .variables)
        case .dataCollection: metadataTableColumn("Data Collection", value: \.dataCollection, column: .dataCollection)
        case .dataAnalysis: metadataTableColumn("Data Analysis", value: \.dataAnalysis, column: .dataAnalysis)
        case .methodology: metadataTableColumn("Methodology", value: \.methodology, column: .methodology)
        case .theoreticalFoundation: metadataTableColumn("Theoretical Foundation", value: \.theoreticalFoundation, column: .theoreticalFoundation)
        case .educationalLevel: metadataTableColumn("Educational Level", value: \.educationalLevel, column: .educationalLevel)
        case .country: metadataTableColumn("Country", value: \.country, column: .country)
        case .keywords: metadataTableColumn("Keywords", value: \.keywords, column: .keywords)
        case .limitations: metadataTableColumn("Limitations", value: \.limitations, column: .limitations)
        }
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var titleTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Title", value: \.title) { paper in
            paperCell(for: paper, column: .title) {
                let row = HStack(spacing: 8) {
                    paperTitleIcon(for: paper)
                    Text(paper.title.isEmpty ? "Untitled Paper" : paper.title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .lineLimit(tableTextLineLimit)
                        .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
                }
                .contentShape(Rectangle())
                if store.pdfURL(for: paper) != nil {
                    row.onDrag {
                        pdfDragItemProvider(for: paper) ?? NSItemProvider()
                    }
                } else {
                    row
                }
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.title), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var authorsTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Authors", value: \.authors) { paper in
            paperCell(for: paper, column: .authors) {
                Text(paper.authors.isEmpty ? "Unknown" : paper.authors)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.authors.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
                    .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.authors), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var englishTitleTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("English Title", value: \.englishTitle) { paper in
            paperCell(for: paper, column: .englishTitle) {
                Text(paper.englishTitle.isEmpty ? "—" : paper.englishTitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.englishTitle.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
                    .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.englishTitle), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var authorsEnglishTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Authors (English)", value: \.authorsEnglish) { paper in
            paperCell(for: paper, column: .authorsEnglish) {
                Text(paper.authorsEnglish.isEmpty ? "—" : paper.authorsEnglish)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.authorsEnglish.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
                    .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.authorsEnglish), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var yearTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Year", value: \.year) { paper in
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
        TableColumn("Source", value: \.source) { paper in
            paperCell(for: paper, column: .source) {
                Text(paper.source.isEmpty ? "—" : paper.source)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(paper.source.isEmpty ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
                    .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.source), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var addedTimeTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Added Time", value: \.addedAtMilliseconds) { paper in
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
        TableColumn("Edited Time", value: \.editedSortKey) { paper in
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
        TableColumn("Tags", value: \.tagsSortKey) { paper in
            paperCell(for: paper, column: .tags) {
                tagsDotCell(for: paper)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.tags), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var ratingTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Rating", value: \.rating) { paper in
            paperCell(for: paper, column: .rating) {
                StarRatingBadge(rating: paper.rating)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.rating), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var imageTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Image", value: \.imageSortKey) { paper in
            paperCell(for: paper, column: .image) {
                paperImageStrip(for: paper)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.image), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var noteTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn("Note", value: \.notes) { paper in
            let text = noteCellText(for: paper)
            paperCell(for: paper, column: .note) {
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(text == "—" ? .secondary : .primary)
                    .lineLimit(tableTextLineLimit)
                    .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.note), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private var attachmentStatusTableColumn: some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(localized(chinese: "附件", english: "Attachment"), value: \.attachmentSortKey) { paper in
            paperCell(for: paper, column: .attachmentStatus) {
                let hasAttachment = cachedAttachmentStatus(for: paper)
                HStack(spacing: 6) {
                    Image(systemName: hasAttachment ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(hasAttachment ? Color.green : Color.secondary)
                    Text(hasAttachment
                        ? localized(chinese: "已附带", english: "Attached")
                        : localized(chinese: "缺失", english: "Missing")
                    )
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(hasAttachment ? .primary : .secondary)
                }
                .lineLimit(1)
            }
        }
        .width(min: 0, ideal: paperTableColumnWidth(.attachmentStatus), max: nil)
    }

    @TableColumnBuilder<Paper, KeyPathComparator<Paper>>
    private func metadataTableColumn(
        _ title: String,
        value: KeyPath<Paper, String>,
        column: PaperTableColumn
    ) -> some TableColumnContent<Paper, KeyPathComparator<Paper>> {
        TableColumn(title, value: value) { paper in
            metadataTextCell(for: paper, value: paper[keyPath: value], isVisible: true, column: column)
        }
        .width(min: 0, ideal: paperTableColumnWidth(column), max: nil)
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
                            }
                        }
                    },
                    onRevealImage: { fileName in
                        if let paper = inspectorPaper {
                            store.revealImage(for: paper.id, fileName: fileName)
                        }
                    },
                    onDeleteImage: { fileName in
                        if let paper = inspectorPaper {
                            store.removeImage(from: paper.id, fileName: fileName)
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
            HStack {
                Text("Filter")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Filter", isOn: $isFilterEnabled)
                        .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Match Mode")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Picker("Match Mode", selection: $filterMatchMode) {
                            ForEach(FilterMatchMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    ForEach($filterConditions) { $condition in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(condition.column.displayName)
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
                                    Text(column.displayName).tag(column)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Picker("Operator", selection: $condition.filterOperator) {
                                ForEach(FilterOperator.allCases) { op in
                                    Text(op.displayName).tag(op)
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
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private var litrixImportContentTypes: [UTType] {
        if let litrixType = UTType(filenameExtension: "litrix") {
            return [litrixType, .zip]
        }
        return [.zip, .data]
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

    private func alignSelectionWithVisibleResults() {
        selectedPaperIDs = selectedPaperIDs.intersection(cachedSortedPaperIDSet)

        if let selectedPaperID,
           cachedSortedPaperIDSet.contains(selectedPaperID) {
            if !selectedPaperIDs.contains(selectedPaperID) {
                selectedPaperIDs.insert(selectedPaperID)
            }
            return
        }

        selectSinglePaper(sortedPapers.first?.id)
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
        alignSelection: Bool = true
    ) {
        pendingSortedPapersRecomputeTask?.cancel()
        pendingSortedPapersRecomputeTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            recomputeSortedPapers()
            if alignSelection {
                alignSelectionWithVisibleResults()
            }
            pendingSortedPapersRecomputeTask = nil
        }
    }

    private func recomputeSortedPapers() {
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

        let base = store.filteredPapers(
            for: sidebarSelection,
            searchText: searchText,
            searchField: toolbarSearchField
        )
        let filtered = applyRuleFilters(to: base)
        let result: [Paper]
        var sortMode = "custom"
        if case .library(.recentReading) = sidebarSelection {
            result = filtered.sorted {
                ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            }
            sortMode = "recentReading"
        } else if usesNaturalOrderForCurrentSort {
            if isSortedByAddedTimeDescending(filtered) {
                result = filtered
                sortMode = "naturalOrder"
            } else {
                result = filtered.sorted(using: sortOrder)
                sortMode = "naturalOrderFallback"
            }
        } else {
            result = filtered.sorted(using: sortOrder)
        }
        applySortedPaperCache(result)
        cacheSortedResultIDs(result.map(\.id), for: cacheKey)
        PerformanceMonitor.logElapsed(
            "ContentView.recomputeSortedPapers",
            from: perfStart,
            thresholdMS: 12
        ) {
            "scope=\(sidebarSelection.performanceLabel), searchLength=\(searchText.count), base=\(base.count), filtered=\(filtered.count), result=\(result.count), mode=\(sortMode)"
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
        case \Paper.authors: return "authors"
        case \Paper.year: return "year"
        case \Paper.source: return "source"
        case \Paper.addedAtMilliseconds: return "addedAt"
        case \Paper.editedSortKey: return "editedAt"
        case \Paper.tagsSortKey: return "tags"
        case \Paper.rating: return "rating"
        case \Paper.imageSortKey: return "image"
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
        cachedSortedPapers = papers
        cachedSortedPaperIDs = papers.map(\.id)
        cachedSortedPaperIDSet = Set(cachedSortedPaperIDs)
        var indexMap: [UUID: Int] = [:]
        var attachmentMap: [UUID: Bool] = [:]
        var imageURLsMap: [UUID: [URL]] = [:]
        indexMap.reserveCapacity(cachedSortedPaperIDs.count)
        attachmentMap.reserveCapacity(cachedSortedPaperIDs.count)
        imageURLsMap.reserveCapacity(cachedSortedPaperIDs.count)
        for (index, id) in cachedSortedPaperIDs.enumerated() {
            indexMap[id] = index
            let paper = papers[index]
            attachmentMap[id] = store.hasExistingPDFAttachment(for: paper)
            if !paper.imageFileNames.isEmpty {
                imageURLsMap[id] = store.imageURLs(for: paper)
            }
        }
        cachedSortedPaperIndexByID = indexMap
        cachedAttachmentStatusByID = attachmentMap
        cachedImageURLsByID = imageURLsMap
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

    private func applyRuleFilters(to papers: [Paper]) -> [Paper] {
        guard isFilterEnabled else { return papers }
        let activeConditions = filterConditions.filter { condition in
            condition.filterOperator.needsValue
                ? !condition.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : true
        }
        guard !activeConditions.isEmpty else { return papers }

        return papers.filter { paper in
            switch filterMatchMode {
            case .any:
                return activeConditions.contains { condition in
                    filterCondition(condition, matches: paper)
                }
            case .all:
                return activeConditions.allSatisfy { condition in
                    filterCondition(condition, matches: paper)
                }
            }
        }
    }

    private func filterCondition(_ condition: PaperFilterCondition, matches paper: Paper) -> Bool {
        let source = filterSourceValue(for: condition.column, paper: paper)
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

    private func filterSourceValue(for column: PaperTableColumn, paper: Paper) -> String {
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
            return formattedAddedTime(from: paper.addedAtMilliseconds)
        case .editedTime:
            return formattedEditedTime(from: paper.lastEditedAtMilliseconds)
        case .tags:
            return paper.tags.joined(separator: ", ")
        case .rating:
            return String(paper.rating)
        case .image:
            return paper.imageFileNames.joined(separator: ", ")
        case .attachmentStatus:
            return store.hasExistingPDFAttachment(for: paper) ? "Attached" : "Missing"
        case .note:
            return paper.notes
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

    private func importPDFsAndAutoEnrich(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard !isPDFImportInProgress else {
            alertMessage = "已有导入任务正在进行，请稍候。"
            return
        }

        let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfURLs.isEmpty else { return }

        let batches = makePDFImportBatches(from: pdfURLs, batchSize: pdfImportBatchSize)
        guard !batches.isEmpty else { return }

        isPDFImportInProgress = true
        isPDFImportProgressVisible = pdfURLs.count >= pdfImportBatchSize
        pdfImportTotalCount = pdfURLs.count
        pdfImportProcessedCount = 0
        pdfImportStatusText = "准备导入 \(pdfURLs.count) 篇文献..."

        pdfImportTask?.cancel()
        pdfImportTask = Task { @MainActor in
            var aggregateResult = PDFImportResult.empty

            defer {
                isPDFImportInProgress = false
                isPDFImportProgressVisible = false
                pdfImportTotalCount = 0
                pdfImportProcessedCount = 0
                pdfImportStatusText = ""
                pdfImportTask = nil
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
            }

            pdfImportStatusText = "正在整理导入结果..."
            recomputeSortedPapers()
            alignSelectionWithVisibleResults()

            let imported = aggregateResult.importedPaperIDs.compactMap { store.paper(id: $0) }
            if !imported.isEmpty {
                pdfImportStatusText = "正在补全元数据..."
                refreshMetadata(
                    forPaperIDs: imported.map(\.id),
                    mode: .refreshMissing,
                    customFields: nil,
                    showErrorsInAlert: false
                )
            }

            var messages: [String] = []
            if !aggregateResult.duplicateTitles.isEmpty {
                let uniqueTitles = Array(NSOrderedSet(array: aggregateResult.duplicateTitles)) as? [String]
                    ?? aggregateResult.duplicateTitles
                let previewTitles = uniqueTitles.prefix(6).joined(separator: "\n")
                let suffix = uniqueTitles.count > 6 ? "\n..." : ""
                let prefix = imported.isEmpty
                    ? "文献已添加，已跳过重复导入："
                    : "以下文献已存在，已跳过重复导入："
                messages.append("\(prefix)\n\(previewTitles)\(suffix)")
            }

            if !aggregateResult.failedFiles.isEmpty {
                let preview = aggregateResult.failedFiles.prefix(8).joined(separator: "、")
                let suffix = aggregateResult.failedFiles.count > 8 ? "..." : ""
                messages.append("导入失败：\(preview)\(suffix)")
            }

            if !messages.isEmpty {
                alertMessage = messages.joined(separator: "\n\n")
            }
        }
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
        store.importBibTeX(from: urls)
        recomputeSortedPapers()
        alignSelectionWithVisibleResults()
    }

    private func importPaperViaDOI() {
        let doi = doiImportDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !doi.isEmpty else { return }
        isDOIImportSheetPresented = false

        Task {
            do {
                let paper = try await fetchPaperMetadataFromDOI(doi)
                await MainActor.run {
                    store.addMetadataOnlyPaper(paper)
                    recomputeSortedPapers()
                    alignSelectionWithVisibleResults()
                }
            } catch {
                await MainActor.run {
                    alertMessage = "DOI import failed: \(error.localizedDescription)"
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
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        guard let url = URL(string: "https://api.crossref.org/works/\(encodedDOI)") else {
            throw NSError(domain: "Litrix", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid DOI"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Litrix", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = root["message"] as? [String: Any]
        else {
            throw NSError(domain: "Litrix", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected DOI response format"])
        }

        let title = (message["title"] as? [String])?.first ?? ""
        let source = (message["container-title"] as? [String])?.first ?? ""
        let year: String = {
            guard
                let issued = message["issued"] as? [String: Any],
                let dateParts = issued["date-parts"] as? [[[Int]]],
                let firstPart = dateParts.first?.first?.first
            else { return "" }
            return String(firstPart)
        }()
        let authors: String = {
            guard let authorItems = message["author"] as? [[String: Any]] else { return "" }
            return authorItems.compactMap { item in
                let family = (item["family"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let given = (item["given"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !family.isEmpty && !given.isEmpty {
                    return "\(given) \(family)"
                }
                return family.isEmpty ? given : family
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        }()
        let abstractRaw = (message["abstract"] as? String) ?? ""
        let abstractText = abstractRaw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let volume = (message["volume"] as? String) ?? ""
        let issue = (message["issue"] as? String) ?? ""
        let pages = (message["page"] as? String) ?? ""
        let paperType = mapCrossrefType((message["type"] as? String) ?? "")

        return Paper(
            title: title,
            authors: authors,
            year: year,
            source: source,
            doi: doi,
            abstractText: abstractText,
            notes: "",
            paperType: paperType,
            volume: volume,
            issue: issue,
            pages: pages,
            storageFolderName: nil,
            storedPDFFileName: nil,
            originalPDFFileName: nil,
            imageFileNames: []
        )
    }

    private func mapCrossrefType(_ type: String) -> String {
        let normalized = type.lowercased()
        if normalized.contains("journal") || normalized == "article" {
            return "期刊"
        }
        if normalized.contains("proceedings") || normalized.contains("conference") {
            return "会议"
        }
        if normalized.contains("book") {
            return "书籍"
        }
        return "电子文献"
    }

    private func openQuickLook(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        QuickLookPreviewManager.shared.preview(url: url)
        activeQuickLookURL = url
    }

    private func toggleSpacePreview() {
        if let activeQuickLookURL, QuickLookPreviewManager.shared.isPreviewing(url: activeQuickLookURL) {
            QuickLookPreviewManager.shared.closePreview()
            self.activeQuickLookURL = nil
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
        guard let url = store.pdfURL(for: selectedPaper) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func configureWindow(_ window: NSWindow) {
        window.title = sidebarSelection.displayTitle(for: settings.appLanguage)

        let isNewWindow = configuredWindowNumber != window.windowNumber
        if isNewWindow {
            configuredWindowNumber = window.windowNumber
            // Keep native system default window sizing behavior:
            // do not apply custom initial size/min size rules and do not persist size.
            // didApplyInitialWindowSize = false
            // removeWindowSizePersistenceObservers()

            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .automatic
            if let toolbar = window.toolbar {
                toolbar.showsBaselineSeparator = true
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                toolbar.displayMode = .iconOnly
            }
            // installWindowSizePersistenceObserversIfNeeded(window: window)
        }

        // Native sizing path:
        // guard !didApplyInitialWindowSize else { return }
        // didApplyInitialWindowSize = true
        // window.styleMask.insert(.resizable)
        // let initialSize = settings.resolvedMainWindowSize ?? NSSize(width: 1160, height: 760)
        // window.setContentSize(initialSize)
        // window.minSize = NSSize(width: 900, height: 560)
        // persistWindowSize(window)
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

    private var translationPlanningTitles: [String] {
        translationPlannedTasks
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.title)
    }

    private var translationQueuedTitles: [String] {
        translationQueuedTasks
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.title)
    }

    private var translationCompletedTitles: [String] {
        translationCompletedTasks
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map(\.title)
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

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if event.keyCode == 3, modifiers == [.command] {
                workspace.focusSearch()
                return nil
            }

            if event.keyCode == 3, modifiers == [.command, .shift] {
                workspace.presentAdvancedSearch()
                return nil
            }

            if isTextInputFocused {
                return event
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

            if event.keyCode == 49, modifiers.isEmpty {
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

            if event.keyCode == 24, modifiers == [.command] || modifiers == [.command, .shift] {
                requestPreserveSelectedRowPosition()
                settings.applyExpandedRowHeight()
                return nil
            }

            if event.keyCode == 27, modifiers == [.command] {
                requestPreserveSelectedRowPosition()
                settings.applyCompactRowHeight()
                return nil
            }

            return event
        }
    }

    private var isTextInputFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func requestPreserveSelectedRowPosition() {
        guard selectedPaperID != nil else { return }
        preserveSelectedRowPositionRequestNonce = UUID()
    }

    private func removeLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func isUpdatingMetadata(for paper: Paper) -> Bool {
        updatingPaperIDs.contains(paper.id)
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

    private func beginCustomRefreshSelection(forPaperIDs paperIDs: [UUID]) {
        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }
        refreshMetadata(
            forPaperIDs: targetIDs,
            mode: .customRefresh,
            customFields: settings.metadataCustomRefreshFields,
            showErrorsInAlert: targetIDs.count == 1
        )
    }

    private func openCustomRefreshFieldChooser(forPaperIDs paperIDs: [UUID]) {
        let targetIDs = uniqueOrderedPaperIDs(from: paperIDs)
        guard !targetIDs.isEmpty else { return }
        customRefreshTargetPaperIDs = targetIDs
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
                let item = metadataRefreshQueue.removeFirst()
                await processMetadataRefresh(item)
            }
            metadataRefreshWorkerTask = nil
        }
    }

    @MainActor
    private func processMetadataRefresh(_ item: MetadataRefreshQueueItem) async {
        let paperID = item.paperID
        let showErrorsInAlert = item.showErrorsInAlert
        let requestedFields = item.fields
        let refreshMode = item.mode

        guard let paper = store.paper(id: paperID),
              let pdfURL = store.pdfURL(for: paper) else {
            if showErrorsInAlert {
                alertMessage = "这篇文献还没有可读取的 PDF。"
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
                pdfURL: pdfURL,
                originalFileName: paper.originalPDFFileName,
                apiEndpoint: settings.resolvedAPIEndpoint,
                apiKey: settings.resolvedAPIKey,
                model: settings.resolvedModel,
                thinkingEnabled: settings.resolvedThinkingEnabled,
                promptBlueprint: settings.resolvedMetadataPromptBlueprint,
                requestedFields: requestedFields
            )

            guard var latest = store.paper(id: paperID) else { return }
            latest.apply(suggestion, fields: requestedFields, mode: refreshMode)
            store.updatePaper(latest)
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
                print("自动更新元数据失败(\(paperID)): \(error.localizedDescription)")
            }
        }
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
        - DOI: \(paper.doi.isEmpty ? "—" : paper.doi)
        - Type: \(paper.paperType.isEmpty ? "—" : paper.paperType)
        - Rating: \(clampedRating(paper.rating))/\(PaperRatingScale.maximum)

        ## Abstract
        \(paper.abstractText.isEmpty ? "—" : paper.abstractText)

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
            pendingDeletePaper = first
            return
        }
        guard let paper = selectedPaper else { return }
        pendingDeletePaper = paper
    }

    private func requestDelete(_ paper: Paper) {
        pendingDeletePaper = paper
    }

    private func deletePaper(_ paper: Paper) {
        let idsToDelete: [UUID]
        if selectedPaperIDs.contains(paper.id), selectedPaperIDs.count > 1 {
            idsToDelete = Array(selectedPaperIDs)
        } else {
            idsToDelete = [paper.id]
        }

        for id in idsToDelete {
            store.removePaper(id: id)
        }

        if let lastInspectedPaperID, idsToDelete.contains(lastInspectedPaperID) {
            self.lastInspectedPaperID = store.papers.first?.id
        }
        selectSinglePaper(nil)
        alignSelectionWithVisibleResults()
        pendingDeletePaper = nil
    }

    private func presentRightPane(_ mode: RightPaneMode) {
        if isInspectorPanelOnscreen, rightPaneMode == mode {
            hideRightPane()
            return
        }
        rightPaneMode = mode
        showRightPane()
    }

    private func toggleDetailsPaneVisibility() {
        presentRightPane(.details)
    }

    private func showRightPane() {
        guard !isInspectorPanelOnscreen else { return }
        withAnimation(inspectorSlideAnimation) {
            isInspectorPanelOnscreen = true
        }
    }

    private func hideRightPane() {
        withAnimation(inspectorSlideAnimation) {
            isInspectorPanelOnscreen = false
        }
    }

    private func toggleSidebarVisibility() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
    }

    private func revealSearchFieldAndFocus() {
        toolbarSearchFocusRequest = UUID()
    }

    private func openNoteEditorWindow() {
        guard let selectedPaperID else {
            alertMessage = "Please select a paper first."
            return
        }
        NoteEditorWindowManager.shared.present(for: selectedPaperID, store: store)
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

        var result = template
        let replacements: [(String, String)] = [
            ("author", author),
            ("apaInTextAuthors", apaInTextAuthors),
            ("apaReferenceAuthors", apaReferenceAuthors),
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
            for paperID in selectedPaperIDs {
                guard let paper = store.paper(id: paperID) else { continue }
                applyQuickTag(number: number, for: paper)
            }
            return
        }
        guard let paper = selectedPaper else { return }
        guard let tag = settings.tagQuickNumberMap.first(where: { $0.value == number })?.key else { return }
        toggleTag(tag, for: paper)
    }

    private func applyQuickTag(number: Int, for paper: Paper) {
        guard let tag = settings.tagQuickNumberMap.first(where: { $0.value == number })?.key else { return }
        toggleTag(tag, for: paper)
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

    private func saveTaxonomy(kind: TaxonomyKind) {
        switch kind {
        case .collection:
            store.createCollection(named: taxonomyDraftName)
        case .tag:
            store.createTag(named: taxonomyDraftName)
        }

        taxonomyDraftName = ""
        taxonomySheetKind = nil
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
        inlineRenameDraft = collection
        DispatchQueue.main.async {
            isInlineRenameFocused = true
        }
    }

    private func beginInlineTagRename(_ tag: String) {
        editingCollectionName = nil
        editingTagName = tag
        inlineRenameDraft = tag
        DispatchQueue.main.async {
            isInlineRenameFocused = true
        }
    }

    private func saveInlineCollectionRename(original: String) {
        let destination = inlineRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { cancelInlineRename() }
        guard !destination.isEmpty else { return }
        guard destination != original else { return }
        store.renameCollection(oldName: original, newName: destination)
        if case .collection(let selectedCollection) = sidebarSelection, selectedCollection == original {
            sidebarSelection = .collection(destination)
        }
    }

    private func saveInlineTagRename(original: String) {
        let destination = inlineRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @ViewBuilder
    private func defaultOpenPDFMenu(for paper: Paper) -> some View {
        Menu(localized(chinese: "修改默认打开文献", english: "Change Default Open PDF")) {
            let availablePDFFileNames = store.availablePDFFileNames(for: paper)
            if availablePDFFileNames.isEmpty {
                Text(localized(chinese: "当前文件夹没有可选 PDF", english: "No PDFs Available"))
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

        let command = makePDF2ZHTerminalCommand(
            activationLines: activationLines,
            tasks: tasks,
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            enableThinking: settings.resolvedThinkingEnabled
        )

        do {
            try launchTerminal(withShellCommand: command)
            registerTranslationJobs(tasks, launchedAt: requestTime)
        } catch {
            alertMessage = localized(
                chinese: "启动 Terminal 失败：\(error.localizedDescription)",
                english: "Failed to launch Terminal: \(error.localizedDescription)"
            )
        }
    }

    private func makePDF2ZHTerminalCommand(
        activationLines: [String],
        tasks: [(paper: Paper, url: URL)],
        apiKey: String,
        baseURL: String,
        model: String,
        enableThinking: Bool
    ) -> String {
        let serviceArgument = "openai:\(model)"
        let sideBySideScript = """
import sys
from pathlib import Path
import fitz

source_path = Path(sys.argv[1])
translated_path = source_path.with_name(f"{source_path.stem}-zh.pdf")
output_path = source_path.with_name(f"{source_path.stem}-dual.pdf")

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

if output_path.exists():
    output_path.unlink()

output_doc.save(output_path)
print(f"Saved side-by-side bilingual PDF: {output_path}")
"""
        var lines: [String] = activationLines + [
            "export OPENAI_BASE_URL=\(shellQuote(baseURL))",
            "export OPENAI_API_KEY=\(shellQuote(apiKey))",
            "export PDF2ZH_OPENAI_ENABLE_THINKING=\(enableThinking ? "true" : "false")",
            "echo \(shellQuote(localized(chinese: "开始通过 pdf2zh 翻译文献…", english: "Starting pdf2zh translation…")))",
            "echo"
        ]

        for (index, task) in tasks.enumerated() {
            lines.append("cd \(shellQuote(task.url.deletingLastPathComponent().path))")
            lines.append("echo \(shellQuote("[\(index + 1)/\(tasks.count)] \(task.url.lastPathComponent)"))")
            lines.append("if pdf2zh \(shellQuote(task.url.path)) -li en -lo zh -s \(shellQuote(serviceArgument)); then")
            lines.append("python - \(shellQuote(task.url.path)) <<'PY'")
            lines.append(sideBySideScript)
            lines.append("PY")
            lines.append("else")
            lines.append("echo \(shellQuote(localized(chinese: "pdf2zh 翻译失败，已跳过该文件。", english: "pdf2zh failed for this file and was skipped.")))")
            lines.append("fi")
            lines.append("echo")
        }

        lines.append("echo \(shellQuote(localized(chinese: "pdf2zh 翻译任务已结束。", english: "pdf2zh translation tasks finished.")))")
        return lines.joined(separator: "\n")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func registerTranslationJobs(_ tasks: [(paper: Paper, url: URL)], launchedAt: Date) {
        let queuedEntries = makeTaskStatusEntries(from: tasks.map(\.paper), timestamp: launchedAt)
        for entry in queuedEntries {
            translationQueuedTasks = upsertRecentTaskEntry(entry, into: translationQueuedTasks, limit: 200)
        }

        let watchJobs = tasks.map { task in
            TranslationWatchJob(
                paperID: task.paper.id,
                title: normalizedTitle(task.paper.title),
                outputURL: task.url.deletingLastPathComponent().appendingPathComponent(
                    "\(task.url.deletingPathExtension().lastPathComponent)-dual.pdf",
                    isDirectory: false
                ),
                launchedAt: launchedAt
            )
        }

        for job in watchJobs {
            translationWatchJobs.removeAll { $0.paperID == job.paperID }
            translationWatchJobs.append(job)
        }

        scheduleTranslationWatchIfNeeded()
    }

    private func scheduleTranslationWatchIfNeeded() {
        guard translationWatchTask == nil else { return }

        translationWatchTask = Task {
            while !Task.isCancelled {
                let hasPendingJobs = await MainActor.run { () -> Bool in
                    checkTranslationWatchJobs()
                    return !translationWatchJobs.isEmpty
                }

                if Task.isCancelled {
                    break
                }

                if !hasPendingJobs {
                    await MainActor.run {
                        translationWatchTask = nil
                    }
                    break
                }

                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    @MainActor
    private func checkTranslationWatchJobs() {
        guard !translationWatchJobs.isEmpty else { return }

        let fileManager = FileManager.default
        var remainingJobs: [TranslationWatchJob] = []

        for job in translationWatchJobs {
            guard fileManager.fileExists(atPath: job.outputURL.path),
                  let values = try? job.outputURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= job.launchedAt.addingTimeInterval(-1) else {
                remainingJobs.append(job)
                continue
            }

            translationQueuedTasks = removeTaskEntry(for: job.paperID, from: translationQueuedTasks)
            translationCompletedTasks = upsertRecentTaskEntry(
                TaskStatusEntry(
                    paperID: job.paperID,
                    title: job.title,
                    timestamp: modifiedAt
                ),
                into: translationCompletedTasks
            )
        }

        translationWatchJobs = remainingJobs
        if remainingJobs.isEmpty {
            translationWatchTask?.cancel()
            translationWatchTask = nil
        }
    }

    private func launchTerminal(withShellCommand shellCommand: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript", isDirectory: false)
        process.arguments = [
            "-e", "on run argv",
            "-e", "tell application \"Terminal\"",
            "-e", "activate",
            "-e", "do script (item 1 of argv)",
            "-e", "end tell",
            "-e", "end run",
            shellCommand
        ]
        try process.run()
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }

    private func metadataField(for column: PaperTableColumn) -> MetadataField? {
        MetadataField.allCases.first { $0.tableColumn == column }
    }

    private func pdfDragItemProvider(for paper: Paper) -> NSItemProvider? {
        guard let pdfURL = store.pdfURL(for: paper) else { return nil }
        if let provider = NSItemProvider(contentsOf: pdfURL) {
            provider.suggestedName = pdfURL.lastPathComponent
            return provider
        }

        let provider = NSItemProvider(object: pdfURL as NSURL)
        provider.suggestedName = pdfURL.lastPathComponent
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(pdfURL.dataRepresentation, nil)
            return nil
        }
        return provider
    }

    @ViewBuilder
    private func paperTitleIcon(for paper: Paper) -> some View {
        let hasPDF = store.pdfURL(for: paper) != nil
        let baseIcon = Image(systemName: hasPDF ? "doc.text" : "doc.badge.questionmark")
            .foregroundStyle(.secondary)

        if hasPDF {
            baseIcon
                .help("Drag PDF to another app")
                .onDrag {
                    pdfDragItemProvider(for: paper) ?? NSItemProvider()
                }
        } else {
            baseIcon
        }
    }

    private func toggleCollection(_ collection: String, for paper: Paper) {
        let assigned = !paper.collections.contains(collection)
        let targetIDs = targetPaperIDs(for: paper)
        store.setCollection(collection, assigned: assigned, forPaperIDs: targetIDs)
    }

    private func toggleTag(_ tag: String, for paper: Paper) {
        let assigned = !paper.tags.contains(tag)
        let targetIDs = targetPaperIDs(for: paper)
        store.setTag(tag, assigned: assigned, forPaperIDs: targetIDs)
    }

    private func tagColor(for tag: String) -> Color {
        guard let hex = store.tagColorHex(forTag: tag) else {
            return .secondary
        }
        return colorFromHex(hex)
    }

    private func isTagColorSelected(_ tag: String, hex: String) -> Bool {
        guard let assigned = store.tagColorHex(forTag: tag) else { return false }
        return assigned.caseInsensitiveCompare(hex) == .orderedSame
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
    private func paperCell<Content: View>(
        for paper: Paper,
        column: PaperTableColumn,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: settings.resolvedTableRowHeight, alignment: .leading)
            .frame(
                maxHeight: supportsWrappedCellContent
                    ? settings.resolvedMaximumTableRowHeight
                    : settings.resolvedTableRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .contextMenu {
                if column == .image {
                    Button("Paste Image") {
                        pasteImageFromClipboard(for: paper)
                    }
                } else if column != .addedTime && column != .editedTime && column != .tags && column != .attachmentStatus {
                    Button("Edit") {
                        beginCellEdit(for: paper, column: column)
                    }
                } else {
                    Text("Read-only")
                }

                Divider()

                Menu("Refresh Metadata") {
                    let targetIDs = targetPaperIDs(for: paper)
                    if let field = metadataField(for: column) {
                        Button("Refresh \(field.displayName)") {
                            refreshMetadata(
                                forPaperIDs: targetIDs,
                                mode: .customRefresh,
                                customFields: [field],
                                showErrorsInAlert: targetIDs.count == 1
                            )
                        }

                        Divider()
                    }

                    Button("Refresh All") {
                        refreshMetadata(
                            forPaperIDs: targetIDs,
                            mode: .refreshAll,
                            customFields: nil,
                            showErrorsInAlert: targetIDs.count == 1
                        )
                    }

                    Button("Refresh Missing") {
                        refreshMetadata(
                            forPaperIDs: targetIDs,
                            mode: .refreshMissing,
                            customFields: nil,
                            showErrorsInAlert: targetIDs.count == 1
                        )
                    }

                    Button("Custom Refresh...") {
                        openCustomRefreshFieldChooser(forPaperIDs: targetIDs)
                    }
                }

                Button("Reveal in Finder") {
                    let papers = targetPapers(for: paper)
                    let urls = papers.compactMap { store.pdfURL(for: $0) }
                    guard !urls.isEmpty else { return }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }

                Button("Open PDF") {
                    for item in targetPapers(for: paper) {
                        store.openPDF(for: item)
                    }
                }

                Button(localized(chinese: "通过 pdf2zh 翻译", english: "Translate via pdf2zh")) {
                    translateViaPDF2ZH(for: paper)
                }

                defaultOpenPDFMenu(for: paper)

                Button("Copy Paper Address") {
                    copyPaperAddress(for: paper)
                }

                Divider()

                Menu("Collections") {
                    if store.collections.isEmpty {
                        Text("No Collections")
                    } else {
                        ForEach(store.collections, id: \.self) { collection in
                            Button {
                                toggleCollection(collection, for: paper)
                            } label: {
                                if paper.collections.contains(collection) {
                                    Label(collection, systemImage: "checkmark")
                                } else {
                                    Text(collection)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("New Collection") {
                        beginInlineCollectionCreation()
                    }
                }

                Menu("Tags") {
                    Menu("Quick Number") {
                        ForEach(1...9, id: \.self) { number in
                            Button(quickNumberMenuTitle(number: number)) {
                                applyQuickTag(number: number, for: paper)
                            }
                            .disabled(settings.tagQuickNumberMap.first(where: { $0.value == number }) == nil)
                        }
                    }

                    Divider()

                    if store.tags.isEmpty {
                        Text("No Tags")
                    } else {
                        ForEach(store.tags, id: \.self) { tag in
                            let label = tagMenuLabel(for: tag)
                            Button {
                                toggleTag(tag, for: paper)
                            } label: {
                                if paper.tags.contains(tag) {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("New Tag") {
                        taxonomyDraftName = ""
                        taxonomySheetKind = .tag
                    }
                }

                Divider()

                Button("Export BibTeX") {
                    exportBibTeX(for: targetPapers(for: paper))
                }

                Button("Delete", role: .destructive) {
                    if selectedPaperIDs.contains(paper.id), selectedPaperIDs.count > 1 {
                        requestDeleteSelectedPaper()
                    } else {
                        requestDelete(paper)
                    }
                }
            }
    }

    private func cachedAttachmentStatus(for paper: Paper) -> Bool {
        cachedAttachmentStatusByID[paper.id] ?? store.hasExistingPDFAttachment(for: paper)
    }

    private func cachedImageURLs(for paper: Paper) -> [URL] {
        cachedImageURLsByID[paper.id] ?? store.imageURLs(for: paper)
    }

    private var supportsWrappedCellContent: Bool {
        settings.resolvedTableRowHeightMultiplier > 1.01
    }

    private var tableTextLineLimit: Int? {
        supportsWrappedCellContent ? settings.resolvedExpandedTableLineLimit : 1
    }

    @ViewBuilder
    private func metadataTextCell(for value: String, isVisible: Bool) -> some View {
        if isVisible {
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(tableTextLineLimit)
                .fixedSize(horizontal: false, vertical: supportsWrappedCellContent)
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
            metadataTextCell(for: value, isVisible: isVisible)
        }
    }

    @ViewBuilder
    private func paperImageStrip(for paper: Paper) -> some View {
        if paper.imageFileNames.isEmpty {
            Text("—")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
        } else {
            let rowReferenceHeight = supportsWrappedCellContent
                ? settings.resolvedMaximumTableRowHeight
                : settings.resolvedTableRowHeight
            let size = max(
                supportsWrappedCellContent ? 12 : 28,
                min(
                    rowReferenceHeight * (supportsWrappedCellContent
                        ? settings.resolvedImageThumbnailMaxSizeMultiplier
                        : max(settings.resolvedImageThumbnailMaxSizeMultiplier * 2.2, 1.25)
                    ),
                    supportsWrappedCellContent ? 120 : 156
                )
            )
            let urls = cachedImageURLs(for: paper).prefix(supportsWrappedCellContent ? 5 : 4)
            HStack(spacing: 6) {
                ForEach(Array(urls), id: \.self) { url in
                    ThumbnailImageView(url: url, maxPixel: size * 2, placeholderOpacity: 0.16)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.6)
                        )
                        .onHover { hovering in
                            if hovering {
                                hoveredPreviewImageURL = url
                            } else if hoveredPreviewImageURL?.standardizedFileURL == url.standardizedFileURL {
                                hoveredPreviewImageURL = nil
                            }
                        }
                }
            }
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
        }
    }

    private func beginCellEdit(for paper: Paper, column: PaperTableColumn) {
        selectSinglePaper(paper.id)

        if column == .image {
            pasteImageFromClipboard(for: paper)
            return
        }

        if column == .addedTime || column == .editedTime || column == .tags {
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
        activeCellEditTarget = nil
    }

    private func pasteImageFromClipboard(for paper: Paper) {
        Task { @MainActor in
            let pasted = await store.addImageFromPasteboard(to: paper.id)
            if !pasted {
                alertMessage = "Clipboard does not contain an image."
            }
        }
    }

    private func editableCellValue(for paper: Paper, column: PaperTableColumn) -> String {
        switch column {
        case .title: return paper.title
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
        }
    }

    private func applyEditableCellValue(_ value: String, to paper: inout Paper, column: PaperTableColumn) -> Bool {
        switch column {
        case .title: paper.title = value
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
        }
        return true
    }

    private func clampedRating(_ rating: Int) -> Int {
        PaperRatingScale.clamped(rating)
    }

    private func formattedAddedTime(from milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        return Self.addedTimeFormatter.string(from: date)
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

    private func handlePDFDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else {
                    return
                }

                Task { @MainActor in
                    importPDFsAndAutoEnrich([url])
                }
            }
            handled = true
        }

        return handled
    }
}

private struct TableCellEditTarget: Identifiable {
    let paperID: UUID
    let column: PaperTableColumn

    var id: String {
        "\(paperID.uuidString)-\(column.rawValue)"
    }
}

private extension PaperTableColumn {
    var prefersMultilineEditor: Bool {
        switch self {
        case .title, .englishTitle, .authors, .authorsEnglish, .source, .note, .rqs, .conclusion, .results, .participantType,
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
                    .frame(minHeight: 180)
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
        .frame(minWidth: 420)
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

private struct MetadataTaskPopover: View {
    let language: AppLanguage
    let metadataPlanningTitles: [String]
    let metadataQueuedTitles: [String]
    let metadataCompletedTitles: [String]
    let translationPlanningTitles: [String]
    let translationQueuedTitles: [String]
    let translationCompletedTitles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            taskBoard(
                title: localized(chinese: "元数据更新", english: "Metadata Updates"),
                planningTitles: metadataPlanningTitles,
                queuedTitles: metadataQueuedTitles,
                completedTitles: metadataCompletedTitles
            )

            Divider()

            taskBoard(
                title: localized(chinese: "翻译情况", english: "Translation Status"),
                planningTitles: translationPlanningTitles,
                queuedTitles: translationQueuedTitles,
                completedTitles: translationCompletedTitles
            )
        }
        .padding(14)
        .frame(width: 420)
    }

    @ViewBuilder
    private func taskBoard(
        title: String,
        planningTitles: [String],
        queuedTitles: [String],
        completedTitles: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            headerRow(title: localized(chinese: "计划中", english: "Planning"), count: planningTitles.count)
            titlesList(planningTitles, emptyText: localized(chinese: "暂无", english: "None"))

            headerRow(title: localized(chinese: "排队中", english: "Queued"), count: queuedTitles.count)
            titlesList(queuedTitles, emptyText: localized(chinese: "暂无", english: "None"))

            headerRow(title: localized(chinese: "已完成", english: "Completed"), count: completedTitles.count)
            titlesList(completedTitles, emptyText: localized(chinese: "暂无", english: "None"))
        }
    }

    @ViewBuilder
    private func titlesList(_ titles: [String], emptyText: String) -> some View {
        if titles.isEmpty {
            Text(emptyText)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func headerRow(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(alignment: .trailing)
        }
    }

    private func localized(chinese: String, english: String) -> String {
        language == .english ? english : chinese
    }
}

private struct ImportActionsPopover: View {
    let canImportDOI: Bool
    let onImportPDF: () -> Void
    let onImportBibTeX: () -> Void
    let onImportLitrix: () -> Void
    let onImportDOI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Divider()

            Button("Import PDF...", action: onImportPDF)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Import BibTeX...", action: onImportBibTeX)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Import Litrix...", action: onImportLitrix)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canImportDOI {
                Button("Add via DOI...", action: onImportDOI)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

private struct ExportActionsPopover: View {
    let isPaperExportDisabled: Bool
    let onExportBibTeX: () -> Void
    let onExportDetailed: () -> Void
    let onExportAttachments: () -> Void
    let onExportLitrix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Divider()

            Button("Export BibTeX...", action: onExportBibTeX)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Export Detailed...", action: onExportDetailed)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Export Attachments...", action: onExportAttachments)
                .disabled(isPaperExportDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Export Litrix...", action: onExportLitrix)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 280)
    }
}

private struct CustomRefreshFieldChooserPopover: View {
    @Binding var selectedFields: [MetadataField]
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
            Text("Custom Refresh")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(MetadataField.allCases) { field in
                        Toggle(field.displayName, isOn: binding(for: field))
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)

            Divider()

            Button("Run Custom Refresh", action: onRun)
                .disabled(selectedFields.isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct InspectorNativeGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        InspectorNativeGlassBackgroundView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class InspectorNativeGlassBackgroundView: NSView {
    private let fallbackView = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    var showChevron = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.secondary)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .textCase(nil)
        .padding(.top, 10)
    }
}

private struct SidebarCollapsibleHeader: View {
    let title: String
    let isCollapsed: Bool
    let showChevron: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.secondary)

            Spacer()

            if showChevron {
                Button(action: onToggle) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .textCase(nil)
        .padding(.top, 10)
    }
}

private struct TagSidebarRow: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.system(size: 13.5, weight: .regular, design: .rounded))

            Spacer(minLength: 8)

            Text("\(count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
    }
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
        .padding(.vertical, 4)
        .listRowBackground(Color.clear)
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
            inspectorTopCard
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.clear)

            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorSection("LIBRARY") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rating")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        StarRatingView(rating: $paper.rating, starSize: 14, showsLabel: false)
                    }

                    TaxonomyChipEditor(
                        title: "Collections",
                        items: paper.collections,
                        availableItems: allCollections,
                        emptyText: "No Collections",
                        newItemLabel: "New Collection",
                        colorForItem: { _ in nil },
                        onAdd: addCollection,
                        onRemove: removeCollection
                    )

                    TaxonomyChipEditor(
                        title: "Tags",
                        items: paper.tags,
                        availableItems: allTags,
                        emptyText: "No Tags",
                        newItemLabel: "New Tag",
                        colorForItem: tagColor(for:),
                        onAdd: addTag,
                        onRemove: removeTag
                    )
                }

                inspectorSection("CONTENT") {
                    modernEditorBlock("Abstract", text: $paper.abstractText, minHeight: 120)
                    modernEditorBlock("Note", text: $paper.notes, minHeight: 140)
                }

                inspectorSection("METADATA") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Drag rows to reorder metadata fields.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        ForEach(metadataOrder, id: \.self) { field in
                            MetadataRowEditor(
                                title: field.displayName,
                                text: binding(for: field),
                                placeholder: field.placeholder,
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

                inspectorSection("IMAGE") {
                    HStack {
                        Button("Paste Image", action: onPasteImage)
                        Text("\(imageURLs.count) 张")
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

                inspectorSection("ACTIONS") {
                    HStack(spacing: 10) {
                        Button("Refresh All", action: onRefreshAllMetadata)
                        Button("Refresh Missing", action: onRefreshMissingMetadata)
                        Button("Custom Refresh...", action: onCustomRefreshMetadata)
                        Button("Export BibTeX", action: onExportBibTeX)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
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
            Text(paper.paperType.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            TextField("Title", text: $paper.title, axis: .vertical)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                TextField("Source", text: $paper.source, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Year", text: $paper.year)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
            }

            TextField("Authors", text: $paper.authors)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if isUpdatingMetadata {
                ProgressView()
                    .controlSize(.small)
            }
        }
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
                            Text("No Existing \(title)")
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

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailImageView(url: url, maxPixel: 120, placeholderOpacity: 0.15)
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        .onHover(perform: onHoverChanged)
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
