import Foundation

@MainActor
final class WorkspaceState: ObservableObject {
    @Published var isAdvancedSearchPresented = false
    @Published var searchFocusNonce = UUID()
    @Published var noteEditorRequestNonce = UUID()
    @Published var tableColumnRefreshNonce = UUID()
    @Published var selectedPaperID: UUID?

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

    func setSelectedPaperID(_ paperID: UUID?) {
        selectedPaperID = paperID
    }
}
