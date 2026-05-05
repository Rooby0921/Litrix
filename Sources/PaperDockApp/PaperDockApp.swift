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
        LanguageRuntimeConfigurator.applyProcessLanguagePreference(for: settingsStore.appLanguage)
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
                .onAppear {
                    MainMenuLocalizer.apply(language: settings.appLanguage)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        MainMenuLocalizer.apply(language: settings.appLanguage)
                    }
                }
                .onChange(of: settings.appLanguage) { _, language in
                    MainMenuLocalizer.apply(language: language)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        MainMenuLocalizer.apply(language: language)
                    }
                }
        }
        .windowResizability(.automatic)
        .commandsRemoved()
        .commands {
            LitrixApplicationMenuCommands(settings: settings)
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowArrangement) {}

            CommandMenu(localized(chinese: "文件", english: "File")) {
                Button(localized(chinese: "新建笔记", english: "New Note")) {
                    workspace.requestOpenNoteEditor()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(localized(chinese: "关闭窗口", english: "Close Window")) {
                    if let window = NSApp.keyWindow {
                        window.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Menu(localized(chinese: "导入文件", english: "Import Files")) {
                    Button(localized(chinese: "导入 PDF…", english: "Import PDF…")) {
                        workspace.requestFileMenuAction(.importPDF)
                    }

                    Button(localized(chinese: "导入 BibTeX…", english: "Import BibTeX…")) {
                        workspace.requestFileMenuAction(.importBibTeX)
                    }

                    Button(localized(chinese: "导入 Litrix…", english: "Import Litrix…")) {
                        workspace.requestFileMenuAction(.importLitrix)
                    }

                    Button(localized(chinese: "通过 DOI 添加…", english: "Add via DOI…")) {
                        workspace.requestFileMenuAction(.importDOI)
                    }
                }

                Menu(localized(chinese: "导出文件", english: "Export Files")) {
                    Button(localized(chinese: "导出 BibTeX…", english: "Export BibTeX…")) {
                        workspace.requestFileMenuAction(.exportBibTeX)
                    }

                    Button(localized(chinese: "导出详细信息…", english: "Export Detailed…")) {
                        workspace.requestFileMenuAction(.exportDetailed)
                    }

                    Button(localized(chinese: "导出附件…", english: "Export Attachments…")) {
                        workspace.requestFileMenuAction(.exportAttachments)
                    }

                    Button(localized(chinese: "导出 Litrix…", english: "Export Litrix…")) {
                        workspace.requestFileMenuAction(.exportLitrix)
                    }
                }
            }

            CommandMenu(localized(chinese: "编辑", english: "Edit")) {
                Button(localized(chinese: "撤销", english: "Undo")) {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button(localized(chinese: "重做", english: "Redo")) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("Z", modifiers: [.command, .shift])

                Divider()

                Button(localized(chinese: "剪切", english: "Cut")) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(localized(chinese: "复制", english: "Copy")) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(localized(chinese: "粘贴", english: "Paste")) {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button(localized(chinese: "全选", english: "Select All")) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandMenu(localized(chinese: "窗口", english: "Window")) {
                Button(localized(chinese: "隐藏/显示左边栏", english: "Show/Hide Left Sidebar")) {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button(localized(chinese: "隐藏/显示右边栏", english: "Show/Hide Right Sidebar")) {
                    workspace.requestViewMenuAction(.toggleRightPane)
                }
                .keyboardShortcut("]", modifiers: .command)

                Button(localized(chinese: "显示详情", english: "Show Details")) {
                    workspace.requestViewMenuAction(.toggleRightPane)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(localized(chinese: "显示/隐藏筛选", english: "Show/Hide Filter")) {
                    workspace.requestViewMenuAction(.showFilterPane)
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Divider()

                Button(localized(chinese: "扩展行视图", english: "Expanded Row View")) {
                    workspace.requestViewMenuAction(.applyExpandedRowHeight)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button(localized(chinese: "单倍行视图", english: "Single Row View")) {
                    workspace.requestViewMenuAction(.applyCompactRowHeight)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button(localized(chinese: "图片视图", english: "Image View")) {
                    workspace.requestViewMenuAction(.toggleImageView)
                }

                Divider()

                Button(localized(chinese: "最小化", english: "Minimize")) {
                    NSApp.sendAction(#selector(NSWindow.performMiniaturize(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button(localized(chinese: "缩放", english: "Zoom")) {
                    NSApp.sendAction(#selector(NSWindow.performZoom(_:)), to: nil, from: nil)
                }

                Button(localized(chinese: "全部置于前端", english: "Bring All to Front")) {
                    NSApp.arrangeInFront(nil)
                }

                Button(localized(chinese: "切换全屏", english: "Toggle Full Screen")) {
                    NSApp.sendAction(#selector(NSWindow.toggleFullScreen(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }

            CommandMenu(localized(chinese: "帮助", english: "Help")) {
                Button(localized(chinese: "关于 Litrix", english: "About Litrix")) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

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
        .defaultSize(width: 660, height: 520)
        .commandsRemoved()
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }
}

private struct LitrixApplicationMenuCommands: Commands {
    let settings: SettingsStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(localized(chinese: "关于 Litrix", english: "About Litrix")) {
                NSApp.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Text(localized(chinese: "设置…", english: "Settings…"))
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appVisibility) {
            Button(localized(chinese: "隐藏 Litrix", english: "Hide Litrix")) {
                NSApp.hide(nil)
            }
            .keyboardShortcut("h", modifiers: .command)

            Button(localized(chinese: "隐藏其他", english: "Hide Others")) {
                NSApp.hideOtherApplications(nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .option])

            Button(localized(chinese: "全部显示", english: "Show All")) {
                NSApp.unhideAllApplications(nil)
            }
        }

        CommandGroup(replacing: .appTermination) {
            Button(localized(chinese: "退出 Litrix", english: "Quit Litrix")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }
}

@MainActor
final class LitrixAppDelegate: NSObject, NSApplicationDelegate {
    private var menuLocalizationTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchRecovery.shared.prepareForLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.windowsMenu = nil
        MainMenuLocalizer.applyUsingPersistedLanguage()

        menuLocalizationTimer?.invalidate()
        menuLocalizationTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                MainMenuLocalizer.applyUsingPersistedLanguage()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainMenuLocalizer.applyUsingPersistedLanguage()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainMenuLocalizer.applyUsingPersistedLanguage()
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        MainMenuLocalizer.applyToOpenMenuUsingPersistedLanguage(menu)
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuLocalizationTimer?.invalidate()
        menuLocalizationTimer = nil
        NotificationCenter.default.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
        LaunchRecovery.shared.markCleanExit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let window = sender.windows.first(where: { !$0.isMiniaturized && !$0.title.isEmpty }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@MainActor
private final class LaunchRecovery {
    static let shared = LaunchRecovery()

    private let fileManager = FileManager.default
    private var launchMarkerURL: URL?
    private var didPrepare = false

    private init() {}

    func prepareForLaunch() {
        guard !didPrepare else { return }
        didPrepare = true

        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let markerURL = makeLaunchMarkerURL()
        launchMarkerURL = markerURL

        if fileManager.fileExists(atPath: markerURL.path) {
            recoverFromUncleanExit(bundleID: bundleID)
        }

        try? fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let launchStamp = ISO8601DateFormatter().string(from: Date())
        try? launchStamp.data(using: .utf8)?.write(to: markerURL, options: .atomic)
    }

    func markCleanExit() {
        guard let launchMarkerURL else { return }
        try? fileManager.removeItem(at: launchMarkerURL)
    }

    private func recoverFromUncleanExit(bundleID: String) {
        let defaults = UserDefaults.standard
        let domainNames = recoveryDomainNames(bundleID: bundleID)
        for domainName in domainNames {
            clearPotentiallyCorruptedUIState(domainName: domainName, defaults: defaults)
            clearSavedStateDirectory(bundleID: domainName)
        }
        clearSavedStateDirectory(bundleID: bundleID)
    }

    private func clearPotentiallyCorruptedUIState(domainName: String, defaults: UserDefaults) {
        guard var domain = defaults.persistentDomain(forName: domainName) else { return }

        let keysToRemove = domain.keys.filter { key in
            key.hasPrefix("NSWindow Frame ")
                || key.hasPrefix("NSSplitView Subview Frames ")
                || key.hasPrefix("NSToolbar Configuration ")
                || key.hasPrefix("litrix.main.window")
                || key.hasPrefix("litrix.main.split")
                || key.hasPrefix("litrix.main.toolbar")
        }

        guard !keysToRemove.isEmpty else { return }
        for key in keysToRemove {
            domain.removeValue(forKey: key)
        }
        defaults.setPersistentDomain(domain, forName: domainName)
        defaults.synchronize()
    }

    private func recoveryDomainNames(bundleID: String) -> [String] {
        var candidates = Set<String>()
        candidates.insert(bundleID)
        candidates.insert("Litrix")
        candidates.insert("com.rooby.Litrix")

        let preferencesURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        if let entries = try? fileManager.contentsOfDirectory(
            at: preferencesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                guard entry.pathExtension == "plist" else { continue }
                let domainName = entry.deletingPathExtension().lastPathComponent
                if domainName == "Litrix" || domainName.hasPrefix("com.rooby.Litrix") {
                    candidates.insert(domainName)
                }
            }
        }

        return candidates.sorted()
    }

    private func clearSavedStateDirectory(bundleID: String) {
        let savedStateURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State", isDirectory: true)
            .appendingPathComponent("\(bundleID).savedState", isDirectory: true)
        guard fileManager.fileExists(atPath: savedStateURL.path) else { return }
        try? fileManager.removeItem(at: savedStateURL)
    }

    private func makeLaunchMarkerURL() -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseDirectory
            .appendingPathComponent("Litrix", isDirectory: true)
            .appendingPathComponent(".launch-in-progress", isDirectory: false)
    }
}

@MainActor
private enum MainMenuLocalizer {
    private static let englishToChinese: [String: String] = [
        "Window": "窗口",
        "Windows": "窗口",
        "View": "视图",
        "Icon Only": "仅图标",
        "Icons Only": "仅图标",
        "Icon and Text": "图标与文字",
        "Icon & Text": "图标与文字",
        "Text Only": "仅文字",
        "Customize Toolbar…": "自定义工具栏…",
        "Customize Toolbar...": "自定义工具栏...",
        "Show Tab Bar": "显示标签栏",
        "Hide Tab Bar": "隐藏标签栏",
        "Show All Tabs": "显示所有标签页",
        "Enter Full Screen": "进入全屏",
        "Exit Full Screen": "退出全屏",
        "Fill": "填充",
        "Center": "居中",
        "Move & Resize": "移动与调整大小",
        "Full Screen Tile": "全屏平铺",
        "Remove Window from Set": "从窗口组中移除",
        "Show Previous Tab": "显示上一个标签页",
        "Show Next Tab": "显示下一个标签页",
        "Move Tab to New Window": "将标签页移至新窗口",
        "Merge All Windows": "合并所有窗口"
    ]

    private static let chineseToEnglish: [String: String] = {
        Dictionary(uniqueKeysWithValues: englishToChinese.map { ($1, $0) })
    }()

    static func apply(language: AppLanguage) {
        guard let menu = NSApp.mainMenu else { return }
        translate(menu: menu, language: language)
        pruneSystemInjectedMenus(in: menu)
        NSApp.mainMenu = menu
    }

    static func applyUsingPersistedLanguage() {
        apply(language: persistedLanguage() ?? .chinese)
    }

    static func applyToOpenMenuUsingPersistedLanguage(_ menu: NSMenu) {
        translate(menu: menu, language: persistedLanguage() ?? .chinese)
    }

    private static func translate(menu: NSMenu, language: AppLanguage) {
        for item in menu.items {
            switch language {
            case .chinese:
                if let mapped = englishToChinese[item.title] {
                    item.title = mapped
                }
            case .english:
                if let mapped = chineseToEnglish[item.title] {
                    item.title = mapped
                }
            }

            if let submenu = item.submenu {
                translate(menu: submenu, language: language)
            }
        }
    }

    private static func persistedLanguage() -> AppLanguage? {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Litrix/settings.json", isDirectory: false)
        guard let data = try? Data(contentsOf: settingsURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawLanguage = payload["appLanguage"] as? String else {
            return nil
        }
        return AppLanguage(rawValue: rawLanguage)
    }

    private static func pruneSystemInjectedMenus(in menu: NSMenu) {
        bindWindowsMenu(in: menu)
        mergeAndHideDuplicateWindowMenus(in: menu)

        for item in menu.items.reversed() {
            guard let submenu = item.submenu else { continue }
            let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let titles = Set(
                submenu.items
                    .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )

            if normalizedTitle == "Litrix" {
                let hasAbout = titles.contains("About Litrix") || titles.contains("关于 Litrix")
                let hasSettings = titles.contains("Settings…") || titles.contains("Settings...") || titles.contains("设置…")
                let looksLikeSystemWindowMenu = titles.contains("Enter Full Screen")
                    || titles.contains("Show Tab Bar")
                    || titles.contains("Hide Tab Bar")
                    || titles.contains("Show All Tabs")

                if !hasAbout && !hasSettings && looksLikeSystemWindowMenu {
                    item.isHidden = true
                }
                continue
            }

            if normalizedTitle == "View" || normalizedTitle == "视图" {
                item.isHidden = true
            }
        }
    }

    private static func bindWindowsMenu(in menu: NSMenu) {
        let windowTitles: Set<String> = ["Window", "Windows", "窗口"]
        let candidates = menu.items.filter { item in
            guard item.submenu != nil else { return false }
            return windowTitles.contains(item.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard !candidates.isEmpty else { return }

        let preferred = candidates.first(where: isPrimaryWindowMenu)
            ?? candidates.first
        guard let preferred, let submenu = preferred.submenu else { return }
        if NSApp.windowsMenu !== submenu {
            NSApp.windowsMenu = submenu
        }
    }

    private static func isPrimaryWindowMenu(_ item: NSMenuItem) -> Bool {
        guard let submenu = item.submenu else { return false }
        let titles = Set(
            submenu.items
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        return titles.contains("Minimize") || titles.contains("最小化")
    }

    private static func mergeAndHideDuplicateWindowMenus(in menu: NSMenu) {
        let windowTitles: Set<String> = ["Window", "Windows", "窗口"]
        let candidates = menu.items.filter { item in
            guard item.submenu != nil else { return false }
            return windowTitles.contains(item.title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard candidates.count > 1 else { return }

        let primary = candidates.first(where: { item in
            guard let submenu = item.submenu else { return false }
            return NSApp.windowsMenu === submenu
        }) ?? candidates.first(where: isPrimaryWindowMenu) ?? candidates[0]

        guard let primaryMenu = primary.submenu else { return }

        for item in candidates where item !== primary {
            guard let secondaryMenu = item.submenu else {
                item.isHidden = true
                continue
            }
            mergeDistinctItems(from: secondaryMenu, into: primaryMenu)
            item.isHidden = true
        }
    }

    private static func mergeDistinctItems(from source: NSMenu, into destination: NSMenu) {
        var existingSignatures = Set(destination.items.map(menuItemSignature))
        var appendedItems: [NSMenuItem] = []

        for sourceItem in Array(source.items) {
            guard !sourceItem.isSeparatorItem else { continue }
            let signature = menuItemSignature(sourceItem)
            source.removeItem(sourceItem)
            guard !existingSignatures.contains(signature) else { continue }
            appendedItems.append(sourceItem)
            existingSignatures.insert(signature)
        }

        guard !appendedItems.isEmpty else { return }
        if let last = destination.items.last, !last.isSeparatorItem {
            destination.addItem(.separator())
        }
        for item in appendedItems {
            destination.addItem(item)
        }
    }

    private static func menuItemSignature(_ item: NSMenuItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = item.action.map { NSStringFromSelector($0) } ?? ""
        return "\(title)|\(action)|\(item.keyEquivalent)|\(item.keyEquivalentModifierMask.rawValue)"
    }
}

private enum LanguageRuntimeConfigurator {
    static func applyProcessLanguagePreference(for language: AppLanguage) {
        let preferredLanguages: [String] = {
            switch language {
            case .chinese:
                return ["zh-Hans", "en"]
            case .english:
                return ["en", "zh-Hans"]
            }
        }()
        UserDefaults.standard.set(preferredLanguages, forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}
