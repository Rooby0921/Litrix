import AppKit
import SwiftUI

@MainActor
final class NoteEditorWindowManager {
    static let shared = NoteEditorWindowManager()
    private static let windowFrameAutosaveName = "litrix.note.editor.window.frame"

    private var controllers: [UUID: NSWindowController] = [:]
    private var closeObservers: [UUID: NSObjectProtocol] = [:]

    private init() {}

    func present(for paperID: UUID, store: LibraryStore) {
        guard let paper = store.paper(id: paperID) else { return }

        if let existing = controllers[paperID], let window = existing.window {
            window.title = store.noteDisplayFileName(for: paper)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = NoteEditorWindowView(
            store: store,
            paperID: paperID
        )
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = store.noteDisplayFileName(for: paper)
        window.minSize = NSSize(width: 560, height: 360)
        window.styleMask.insert([.titled, .closable, .resizable, .miniaturizable])
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.windowFrameAutosaveName)
        if !window.setFrameUsingName(Self.windowFrameAutosaveName) {
            window.setContentSize(NSSize(width: 920, height: 680))
        }

        let controller = NSWindowController(window: window)
        controllers[paperID] = controller

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanup(for: paperID)
            }
        }
        closeObservers[paperID] = observer

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cleanup(for paperID: UUID) {
        controllers.removeValue(forKey: paperID)

        if let observer = closeObservers.removeValue(forKey: paperID) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private struct NoteEditorWindowView: View {
    @ObservedObject var store: LibraryStore
    let paperID: UUID

    @State private var noteText = ""
    @State private var didInitialize = false
    @State private var pendingSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $noteText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            reloadFromStore()
        }
        .onDisappear {
            persistNow()
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
        }
        .onChange(of: noteText) {
            guard didInitialize else { return }
            scheduleAutoSave()
        }
    }

    private func reloadFromStore() {
        guard let paper = store.paper(id: paperID) else { return }
        noteText = paper.notes
        didInitialize = true
    }

    private func scheduleAutoSave() {
        pendingSaveTask?.cancel()
        let snapshot = noteText
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            persist(snapshot)
        }
    }

    private func persistNow() {
        persist(noteText)
    }

    private func persist(_ text: String) {
        guard var paper = store.paper(id: paperID) else { return }
        guard paper.notes != text else { return }
        paper.notes = text
        store.updatePaper(paper)
    }
}
