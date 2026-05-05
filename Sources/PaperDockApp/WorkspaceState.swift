import Foundation

enum WorkspaceFileMenuAction {
    case importPDF
    case importBibTeX
    case importLitrix
    case importDOI
    case exportBibTeX
    case exportDetailed
    case exportAttachments
    case exportLitrix
}

enum WorkspaceViewMenuAction {
    case toggleRightPane
    case showFilterPane
    case toggleImageView
    case applyExpandedRowHeight
    case applyCompactRowHeight
}

@MainActor
final class WorkspaceState: ObservableObject {
    @Published var isAdvancedSearchPresented = false
    @Published var searchFocusNonce = UUID()
    @Published var noteEditorRequestNonce = UUID()
    @Published var tableColumnRefreshNonce = UUID()
    @Published var fileMenuActionNonce = UUID()
    @Published var viewMenuActionNonce = UUID()
    @Published var selectedPaperID: UUID?
    private(set) var pendingFileMenuAction: WorkspaceFileMenuAction?
    private(set) var pendingViewMenuAction: WorkspaceViewMenuAction?

    func focusSearch() {
        searchFocusNonce = UUID()
    }

    func presentAdvancedSearch() {
        isAdvancedSearchPresented = true
    }

    func requestOpenNoteEditor() {
        noteEditorRequestNonce = UUID()
    }

    func requestTableColumnRefresh() {
        tableColumnRefreshNonce = UUID()
    }

    func requestFileMenuAction(_ action: WorkspaceFileMenuAction) {
        pendingFileMenuAction = action
        fileMenuActionNonce = UUID()
    }

    func requestViewMenuAction(_ action: WorkspaceViewMenuAction) {
        pendingViewMenuAction = action
        viewMenuActionNonce = UUID()
    }

    func setSelectedPaperID(_ paperID: UUID?) {
        selectedPaperID = paperID
    }
}
