import AppKit
import SwiftUI

@MainActor
final class NoteEditorWindowManager {
    static let shared = NoteEditorWindowManager()

    private var controllers: [UUID: NSWindowController] = [:]
    private var windowObservers: [UUID: [NSObjectProtocol]] = [:]
    private var keyMonitors: [UUID: Any] = [:]

    private init() {}

    func present(for paperID: UUID, store: LibraryStore, settings: SettingsStore) {
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
        if let savedFrame = settings.resolvedNoteEditorWindowFrame {
            window.setFrame(savedFrame, display: false)
        } else {
            window.setContentSize(NSSize(width: 920, height: 680))
        }

        let controller = NSWindowController(window: window)
        controllers[paperID] = controller
        keyMonitors[paperID] = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard window?.isKeyWindow == true,
                  event.keyCode == 1,
                  modifiers == [.command] else {
                return event
            }
            NotificationCenter.default.post(name: .litrixNoteEditorSaveRequested, object: paperID)
            return nil
        }

        let center = NotificationCenter.default
        let moveObserver = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                settings.recordNoteEditorWindowFrame(window.frame)
            }
        }
        let resizeObserver = center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                settings.recordNoteEditorWindowFrame(window.frame)
            }
        }
        let closeObserver = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                settings.recordNoteEditorWindowFrame(window.frame)
                self?.cleanup(for: paperID)
            }
        }
        windowObservers[paperID] = [moveObserver, resizeObserver, closeObserver]

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cleanup(for paperID: UUID) {
        controllers.removeValue(forKey: paperID)

        if let observers = windowObservers.removeValue(forKey: paperID) {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        if let monitor = keyMonitors.removeValue(forKey: paperID) {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private extension Notification.Name {
    static let litrixNoteEditorSaveRequested = Notification.Name("LitrixNoteEditorSaveRequested")
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
        .onReceive(NotificationCenter.default.publisher(for: .litrixNoteEditorSaveRequested)) { notification in
            guard let requestedID = notification.object as? UUID,
                  requestedID == paperID else { return }
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            persistNow()
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
