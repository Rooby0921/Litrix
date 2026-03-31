import AppKit
import SwiftUI

@main
struct LitrixApp: App {
    @NSApplicationDelegateAdaptor(LitrixAppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: LibraryStore
    @StateObject private var mcpServer: LitrixMCPServerController
    @StateObject private var workspace = WorkspaceState()

    init() {
        let settingsStore = SettingsStore()
        let libraryStore = LibraryStore(settings: settingsStore)
        let mcpRuntime = LitrixMCPServerController(settings: settingsStore, store: libraryStore)
        _settings = StateObject(wrappedValue: settingsStore)
        _store = StateObject(wrappedValue: libraryStore)
        _mcpServer = StateObject(wrappedValue: mcpRuntime)
    }

    var body: some Scene {
        WindowGroup("Litrix") {
            ContentView(store: store)
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(mcpServer)
                .environmentObject(workspace)
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(localized(chinese: "新建笔记", english: "New Note")) {
                    workspace.requestOpenNoteEditor()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button(localized(chinese: "退出 Litrix", english: "Quit Litrix")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }

            SidebarCommands()
            CommandMenu(localized(chinese: "搜索", english: "Search")) {
                Button(localized(chinese: "搜索", english: "Search")) {
                    workspace.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(localized(chinese: "高级搜索", english: "Advanced Search")) {
                    workspace.presentAdvancedSearch()
                }
                .keyboardShortcut("F", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(mcpServer)
                .environmentObject(workspace)
        }
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }
}

final class LitrixAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
