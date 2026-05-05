import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case api
    case pdf2zh
    case citation
    case importer
    case export
    case column
    case row

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .api:
            return "API"
        case .pdf2zh:
            return "PDF2ZH"
        case .citation:
            return "Citation"
        case .importer:
            return "Import"
        case .export:
            return "Export"
        case .column:
            return "Column"
        case .row:
            return "Row"
        }
    }

    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .general:
            return language == .english ? "General" : "通用"
        case .api:
            return "API"
        case .pdf2zh:
            return "PDF2ZH"
        case .citation:
            return language == .english ? "Citation" : "引用"
        case .importer:
            return language == .english ? "Import" : "导入"
        case .export:
            return language == .english ? "Export" : "导出"
        case .column:
            return language == .english ? "Column" : "列"
        case .row:
            return language == .english ? "Row" : "行"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .api:
            return "network"
        case .pdf2zh:
            return "doc.viewfinder"
        case .citation:
            return "quote.bubble"
        case .importer:
            return "square.and.arrow.down"
        case .export:
            return "square.and.arrow.up"
        case .column:
            return "tablecells"
        case .row:
            return "rectangle.split.1x2"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var mcpServer: LitrixMCPServerController
    @EnvironmentObject private var workspace: WorkspaceState
    @State private var selection: SettingsPane = .general
    @State private var papersDirectoryDraft = SettingsStore.defaultPapersDirectoryPath
    @State private var papersDirectoryBookmarkData: Data?
    @State private var papersDirectoryBookmarkPath: String?
    @State private var generalErrorMessage: String?
    @State private var generalStatusMessage: String?
    @State private var isCheckingConnection = false
    @State private var connectionCheckOutput = ""
    @State private var isCheckingPDF2ZH = false
    @State private var pdf2zhCheckOutput = ""
    @State private var mcpConfigStatusOutput = ""
    @State private var mcpClientType: MCPClientType = .codexCLI
    @State private var mcpConfigOutput = ""
    @State private var mcpUsageOutput = ""
    @State private var pluginResourceStatusMessage = ""
    @State private var isCheckingSafariWebPlugin = false
    @State private var isCheckingChromeWebPlugin = false
    @State private var draggingTableColumn: PaperTableColumn?
    @State private var configuredWindowNumber: Int?
    @State private var didApplyInitialWindowSize = false
    @State private var headerHeight: CGFloat = 120
    @State private var paneHeight: CGFloat = 500
    private let baseWindowWidth: CGFloat = 660
    private let minimumWindowWidth: CGFloat = 620
    private let maximumWindowWidth: CGFloat = 760
    private let minimumWindowHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selection {
                    case .general:
                        generalPane
                    case .api:
                        apiPane
                    case .pdf2zh:
                        pdf2zhPane
                    case .citation:
                        citationPane
                    case .importer:
                        importerPane
                    case .export:
                        exportPane
                    case .column:
                        columnPane
                    case .row:
                        rowPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SettingsPaneHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
            }
        }
        .frame(width: baseWindowWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            WindowConfigurator { window in
                configureSettingsWindow(window)
            }
        )
        .onPreferenceChange(SettingsHeaderHeightPreferenceKey.self) { newValue in
            guard newValue > 0 else { return }
            headerHeight = newValue
        }
        .onPreferenceChange(SettingsPaneHeightPreferenceKey.self) { newValue in
            guard newValue > 0 else { return }
            paneHeight = newValue
        }
        .onAppear {
            papersDirectoryDraft = settings.resolvedPapersDirectoryURL.path
            refreshMCPPreview()
        }
        .onChange(of: settings.papersStorageDirectoryPath) {
            papersDirectoryDraft = settings.resolvedPapersDirectoryURL.path
        }
        .onChange(of: mcpClientType) {
            refreshMCPPreview()
        }
        .onChange(of: settings.mcpServerName) {
            refreshMCPPreview()
        }
        .onChange(of: settings.mcpServerHost) {
            refreshMCPPreview()
        }
        .onChange(of: settings.mcpServerPort) {
            refreshMCPPreview()
        }
        .onChange(of: settings.mcpServerPath) {
            refreshMCPPreview()
        }
        .alert(
            "Path Update Failed",
            isPresented: generalErrorPresented,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(generalErrorMessage ?? "")
            }
        )
    }

    private var settingsHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(SettingsPane.allCases) { pane in
                    settingsPaneButton(pane)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SettingsHeaderHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    @ViewBuilder
    private func settingsPaneButton(_ pane: SettingsPane) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selection = pane
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: pane.icon)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 24, height: 24, alignment: .center)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selection == pane ? Color.accentColor : Color.secondary)
                Text(pane.localizedTitle(settings.appLanguage))
                    .font(.system(size: 10, weight: selection == pane ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(selection == pane ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(selection == pane ? Color.accentColor : Color.primary.opacity(0.7))
            .frame(width: 66, height: 52, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selection == pane ? Color(nsColor: .textBackgroundColor) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        selection == pane ? Color.black.opacity(0.1) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: selection == pane ? Color.black.opacity(0.08) : Color.clear,
                radius: 3,
                x: 0,
                y: 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(pane.localizedTitle(settings.appLanguage))
        .accessibilityLabel(pane.localizedTitle(settings.appLanguage))
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "存储", english: "Storage")) {
                SettingsInputRow(title: localized(chinese: "文献目录", english: "Papers Directory")) {
                    HStack(spacing: 10) {
                        TextField("e.g. ~/Litrix/Papers", text: $papersDirectoryDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)

                        Button(localized(chinese: "浏览…", english: "Browse...")) {
                            browsePapersDirectory()
                        }
                    }
                }

                SettingsInputRow(title: localized(chinese: "操作", english: "Actions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button(localized(chinese: "应用并迁移数据", english: "Apply and Move Data")) {
                                applyPapersDirectoryChange()
                            }

                            Button(localized(chinese: "打开文件夹", english: "Open Folder")) {
                                settings.openPapersStorageFolder()
                            }
                        }

                        Button(localized(chinese: "恢复默认", english: "Reset to Default")) {
                            papersDirectoryDraft = SettingsStore.defaultPapersDirectoryPath
                            applyPapersDirectoryChange()
                        }
                    }
                }

                Text("Default: \(SettingsStore.defaultPapersDirectoryPath)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !settings.hasPapersStoragePermission {
                    Text("Current folder may need macOS permission. Use Browse... to grant access.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            SettingsSection(title: localized(chinese: "阅读", english: "Reading")) {
                SettingsInputRow(title: localized(chinese: "打开文献", english: "Open Paper")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            localized(
                                chinese: "优先打开翻译后的文献",
                                english: "Prefer translated PDF"
                            ),
                            isOn: $settings.preferTranslatedPDF
                        )
                        Text(localized(
                            chinese: "开启后，如果同一条目下存在 -dual.pdf，打开和空格预览都会优先使用该文件。",
                            english: "When enabled, Open and Space preview prefer an available -dual.pdf in the same item."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "最近阅读窗口", english: "Recent Window")) {
                    Picker("Recent Reading", selection: $settings.recentReadingRange) {
                        ForEach(RecentReadingRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 460)
                }

                SettingsInputRow(title: localized(chinese: "僵尸文献窗口", english: "Zombie Window")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Slider(
                                value: zombieThresholdIndexBinding,
                                in: 0...Double(zombieThresholds.count - 1),
                                step: 1
                            )
                            Text(settings.zombiePapersThreshold.displayName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 110, alignment: .trailing)
                        }
                        Text("Papers become Zombie when Added Time and last edit are both older than this window.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }

            SettingsSection(title: localized(chinese: "外观", english: "Appearance")) {
                SettingsInputRow(title: localized(chinese: "选中文字颜色", english: "Selected Text Color")) {
                    HStack(spacing: 12) {
                        ColorPicker(
                            localized(chinese: "文字颜色", english: "Text Color"),
                            selection: tableSelectionTextColorBinding,
                            supportsOpacity: false
                        )

                        Button(localized(chinese: "系统默认", english: "System Default")) {
                            settings.tableSelectionTextColorHex = ""
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "星标颜色", english: "Star Color")) {
                    HStack(spacing: 12) {
                        ColorPicker(
                            localized(chinese: "星标颜色", english: "Star Color"),
                            selection: starColorBinding,
                            supportsOpacity: false
                        )

                        Button(localized(chinese: "恢复默认", english: "Reset")) {
                            settings.starColorHex = SettingsStore.defaultStarColorHex
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }

            SettingsSection(title: localized(chinese: "最近删除", english: "Recently Deleted")) {
                SettingsInputRow(title: localized(chinese: "保存时间", english: "Retention")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Slider(
                                value: recentlyDeletedRetentionDaysBinding,
                                in: Double(SettingsStore.recentlyDeletedRetentionDayRange.lowerBound)...Double(SettingsStore.recentlyDeletedRetentionDayRange.upperBound),
                                step: 1
                            )
                            Text(recentlyDeletedRetentionLabel)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 120, alignment: .trailing)
                        }
                        Text(localized(
                            chinese: "删除的文献会先保留在“最近删除”中；超过保存时间后会自动彻底删除。",
                            english: "Deleted papers stay in Recently Deleted first; after this window they are permanently deleted automatically."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }

            SettingsSection(title: "PDF") {
                SettingsInputRow(title: localized(chinese: "文件命名", english: "Source File Naming")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            localized(
                                chinese: "新导入文献自动重命名",
                                english: "Auto-rename newly imported PDFs"
                            ),
                            isOn: $settings.autoRenameImportedPDFFiles
                        )

                        Button(
                            localized(
                                chinese: "按元数据重命名现有文献文件",
                                english: "Rename Existing PDF Files from Metadata"
                            )
                        ) {
                            renameStoredPDFFilesFromMetadata()
                        }

                        Text(
                            localized(
                                chinese: "命名规则：title-authors-year.pdf（基于文献元数据）",
                                english: "Naming pattern: title-authors-year.pdf (based on paper metadata)"
                            )
                        )
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let generalStatusMessage,
                           !generalStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(generalStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsSection(title: localized(chinese: "元数据刷新", english: "Metadata Refresh")) {
                SettingsInputRow(title: localized(chinese: "刷新策略", english: "Refresh Strategy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Refresh Strategy", selection: $settings.metadataRefreshPriority) {
                            ForEach(MetadataRefreshPriority.allCases) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 460)

                        Text(localized(
                            chinese: "优先本地识别：从文件名和本地文件解析元数据；优先API识别：优先调用 API 获取元数据。",
                            english: "Local First: parse metadata from file name and local files. API First: prefer fetching metadata via API."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection(title: localized(chinese: "工具栏", english: "Toolbar")) {
                SettingsInputRow(title: localized(chinese: "显示模式", english: "Display Mode")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            localized(chinese: "仅显示图标（Icon Only）", english: "Icon Only (hide labels)"),
                            isOn: $settings.toolbarIconOnly
                        )
                        Text(localized(
                            chinese: "关闭后将同时显示图标和标签文字。设置即时生效。",
                            english: "When off, both icon and label are shown. Takes effect immediately."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSection(title: localized(chinese: "语言", english: "Language"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "应用语言", english: "App Language")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Language", selection: $settings.appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 460)

                        Text("Language preference is saved and takes effect after restarting Litrix.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var apiPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "提供商", english: "Provider")) {
                SettingsInputRow(title: localized(chinese: "API 提供商", english: "API Provider")) {
                    Picker("API Provider", selection: metadataProviderBinding) {
                        ForEach(MetadataAPIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }

                SettingsInputRow(title: localized(chinese: "API 端点", english: "API Endpoint")) {
                    TextField(SettingsStore.defaultAPIBaseURL, text: $settings.metadataAPIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: localized(chinese: "API 密钥", english: "API Key")) {
                    SecureField("Enter API Key", text: $settings.metadataAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: localized(chinese: "模型", english: "Model")) {
                    TextField(SettingsStore.defaultModel, text: $settings.metadataModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: localized(chinese: "推理模式", english: "Reasoning Mode")) {
                    Picker("Reasoning Mode", selection: $settings.metadataThinkingMode) {
                        ForEach(MetadataThinkingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }
            }

            SettingsSection(title: localized(chinese: "验证", english: "Validation")) {
                SettingsInputRow(title: localized(chinese: "API 测试", english: "API Test")) {
                    HStack(spacing: 10) {
                        Button {
                            checkAPIConnection()
                        } label: {
                            Text(isCheckingConnection ? "Checking..." : "Check Connection")
                        }
                        .disabled(isCheckingConnection)

                        if isCheckingConnection {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }
                }

                SettingsInputRow(title: localized(chinese: "提示词", english: "Prompt")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(localized(chinese: "编辑提示词", english: "Edit Prompt")) {
                            settings.openMetadataPromptFileInEditor()
                        }

                        Text("Prompt is stored as local .txt file and opened by system editor.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("Prompt supports per-field composition and is used by metadata refresh actions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: localized(chinese: "连接结果", english: "Connection Result")) {
                    TextEditor(text: $connectionCheckOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(minHeight: 130)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .frame(maxWidth: 620)
                }
            }

            SettingsSection(title: "MCP") {
                SettingsInputRow(title: localized(chinese: "启用 MCP", english: "Enable MCP")) {
                    Toggle("启用 Litrix MCP", isOn: $settings.mcpEnabled)
                        .toggleStyle(.switch)
                }

                SettingsInputRow(title: localized(chinese: "运行状态", english: "Runtime")) {
                    Text(mcpServer.runtimeStatusText)
                        .font(.footnote)
                        .foregroundStyle(mcpServer.runtimeListening ? .green : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "客户端", english: "Client")) {
                    HStack(spacing: 10) {
                        Picker("Client", selection: $mcpClientType) {
                            ForEach(MCPClientType.allCases) { client in
                                Text(client.displayName).tag(client)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 250)

                        Spacer()
                    }
                }

                SettingsInputRow(title: localized(chinese: "服务器", english: "Server")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("服务名称", text: $settings.mcpServerName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                            TextField("Host", text: $settings.mcpServerHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 160)
                            TextField(
                                "Port",
                                value: $settings.mcpServerPort,
                                format: .number
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                            TextField("Path", text: $settings.mcpServerPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }

                        Text("Endpoint: \(settings.resolvedMCPServerURLString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                SettingsInputRow(title: localized(chinese: "配置", english: "Configuration")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button("生成配置") {
                                generateMCPConfiguration()
                            }

                            Button("复制配置") {
                                copyMCPConfiguration()
                            }

                            Button("复制说明") {
                                copyMCPUsage()
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("配置内容")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $mcpConfigOutput)
                                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                                    .frame(minHeight: 220)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(nsColor: .textBackgroundColor))
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("使用说明")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $mcpUsageOutput)
                                    .font(.system(size: 12.5, weight: .regular, design: .rounded))
                                    .frame(minHeight: 220)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(nsColor: .textBackgroundColor))
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !mcpConfigStatusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(mcpConfigStatusOutput)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Button("打开配置目录") {
                            settings.openMCPConfigurationDirectory()
                        }
                    }
                }

                SettingsInputRow(title: localized(chinese: "自定义限制", english: "Custom Limits")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(
                            value: $settings.mcpMaxContentLength,
                            in: 500...100_000,
                            step: 500
                        ) {
                            Text("内容长度上限：\(settings.mcpMaxContentLength)")
                        }

                        Stepper(
                            value: $settings.mcpMaxAttachments,
                            in: 1...100
                        ) {
                            Text("最大附件数：\(settings.mcpMaxAttachments)")
                        }

                        Stepper(
                            value: $settings.mcpMaxNotes,
                            in: 1...200
                        ) {
                            Text("最大笔记数：\(settings.mcpMaxNotes)")
                        }

                        Stepper(
                            value: $settings.mcpKeywordLimit,
                            in: 1...200
                        ) {
                            Text("关键词数：\(settings.mcpKeywordLimit)")
                        }

                        Stepper(
                            value: $settings.mcpSearchResultLimit,
                            in: 1...500
                        ) {
                            Text("搜索结果上限：\(settings.mcpSearchResultLimit)")
                        }

                        Stepper(
                            value: $settings.mcpMaxNumericValues,
                            in: 1...2_000
                        ) {
                            Text("最大数值数：\(settings.mcpMaxNumericValues)")
                        }
                    }
                }

                SettingsInputRow(title: localized(chinese: "支持功能", english: "Supported Features")) {
                    Text("""
                    查看任意文献元数据、编辑任意文献元数据、语义搜索、普通检索、文库结构读取、摘要读取、全文提取、批注搜索、相似文献查找、条目详情、缓存状态、语义索引状态、Collection 管理、条目增改、标签管理、笔记创建/追加
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection(title: localized(chinese: "存储", english: "Storage"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "数据文件夹", english: "Data Folder")) {
                    Button(localized(chinese: "打开数据文件夹", english: "Open Data Folder")) {
                        settings.openStorageFolder()
                    }
                }
            }
        }
    }

    private var pdf2zhPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "安装", english: "Installation")) {
                SettingsInputRow(title: localized(chinese: "检查", english: "Check")) {
                    HStack(spacing: 10) {
                        Button {
                            checkPDF2ZHInstallation()
                        } label: {
                            Text(isCheckingPDF2ZH ? "Checking..." : "Check pdf2zh")
                        }
                        .disabled(isCheckingPDF2ZH)

                        if isCheckingPDF2ZH {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }
                }

                SettingsInputRow(title: localized(chinese: "状态", english: "Status")) {
                    Text(pdf2zhCheckOutput.isEmpty ? "Not checked yet." : pdf2zhCheckOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "安装命令", english: "Install Command")) {
                    Text(settings.pdf2zhInstallInstructions())
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: "Disclaimer / 免责声明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("pdf2zh is an open-source project. Litrix does not provide PDF translation by itself; this feature only invokes the capability of pdf2zh after you install and configure it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("pdf2zh 是一个开源项目。Litrix 本身不具备 PDF 翻译能力；这里的功能仅是在你安装并配置 pdf2zh 后，调用 pdf2zh 的能力。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Litrix only provides an integration entry and environment guidance. Litrix does not develop, control, or warrant pdf2zh itself, and is not responsible for defects, behavior changes, or availability issues originating from pdf2zh.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Litrix 仅提供集成入口与环境配置指引。Litrix 不开发、不控制、也不担保 pdf2zh 本身；对于源自 pdf2zh 的缺陷、行为变化或可用性问题，Litrix 不作功能承诺。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("pdf2zh is a great open-source project, and users should review and decide for themselves whether to install and use it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("pdf2zh 是一个很棒的开源项目，是否安装和使用由用户自行决定。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link(
                            "https://github.com/guaguastandup/zotero-pdf2zh",
                            destination: URL(string: "https://github.com/guaguastandup/zotero-pdf2zh")!
                        )
                        .font(.footnote)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }

            SettingsSection(title: localized(chinese: "环境", english: "Environment")) {
                SettingsInputRow(title: localized(chinese: "执行模式", english: "Execution Mode")) {
                    Picker("Execution Mode", selection: $settings.pdf2zhEnvironmentKind) {
                        ForEach(PDF2ZHEnvironmentKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }

                if settings.pdf2zhEnvironmentKind != .custom {
                    SettingsInputRow(title: localized(chinese: "环境名称", english: "Environment Name")) {
                        TextField(
                            settings.pdf2zhEnvironmentKind == .base ? "base" : SettingsStore.defaultPDF2ZHEnvironmentName,
                            text: $settings.pdf2zhEnvironmentName
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                    }
                } else {
                    SettingsInputRow(title: localized(chinese: "激活命令", english: "Activation Command")) {
                        TextField("source ~/miniconda3/etc/profile.d/conda.sh && conda activate tools-dev", text: $settings.pdf2zhCustomActivationCommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)
                    }
                }

                SettingsInputRow(title: localized(chinese: "并发上限", english: "Concurrency Limit")) {
                    Stepper(
                        value: $settings.pdf2zhMaxConcurrentTasks,
                        in: 1...6
                    ) {
                        Text(localized(
                            chinese: "同时翻译 \(settings.pdf2zhMaxConcurrentTasks) 篇文献",
                            english: "Translate \(settings.pdf2zhMaxConcurrentTasks) paper(s) at once"
                        ))
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "说明", english: "Notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Right-click Translate via pdf2zh uses the current API Endpoint, API Key, Model, and Reasoning Mode from the API pane.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Translation now runs silently in the background and starts selected papers in batches according to the concurrency limit above.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("The generated bilingual PDF is post-processed into a left-original / right-translation layout on the same page.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Font replacement is not exposed as a pdf2zh CLI option. The current integration keeps pdf2zh’s built-in Chinese font.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }
        }
    }

    private var citationPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "模板", english: "Templates")) {
                SettingsInputRow(title: localized(chinese: "预设", english: "Preset")) {
                    Picker("Preset", selection: citationPresetBinding) {
                        ForEach(CitationPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                SettingsInputRow(title: localized(chinese: "文内引用", english: "In-text Citation")) {
                    TextField("e.g. ({{author}}, {{year}})", text: inTextCitationBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 620)
                }

                SettingsInputRow(title: localized(chinese: "参考文献引用", english: "Bibliography Citation")) {
                    TextEditor(text: referenceCitationBinding)
                        .font(.body)
                        .frame(minHeight: 130)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .frame(maxWidth: 620)
                }

                SettingsInputRow(title: localized(chinese: "占位符", english: "Placeholders")) {
                    Text("{{author}} {{apaInTextAuthors}} {{apaReferenceAuthors}} {{year}} {{title}} {{journal}} {{volume}} {{number}} {{pages}} {{doi}} {{page}}")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: localized(chinese: "插件", english: "Plug-ins"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "文字处理器插件", english: "Word Processor Plug-ins")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button(localized(chinese: "安装 Word 插件", english: "Install Word Plug-in")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "OfficeAddin",
                                    "word"
                                ])
                            }

                            Button(localized(chinese: "启动本地服务", english: "Start Local Server")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "OfficeAddin",
                                    "start-local-server.command"
                                ])
                            }

                            Button(localized(chinese: "WPS（mac）桥接脚本", english: "WPS (mac) Bridge Scripts")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "WPSMacBridge"
                                ])
                            }

                            Button(localized(chinese: "教程", english: "Tutorial")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "Tutorials",
                                    "Litrix-Word-WPS插件教程.txt"
                                ])
                            }
                        }

                        Text(localized(
                            chinese: "Word（mac）支持 Office Add-in。WPS（mac）当前使用桥接脚本模式：先在 Litrix 复制快速引用，再由脚本粘贴为行内引用或脚注。",
                            english: "Word (mac) supports the Office add-in. WPS (mac) uses bridge scripts: copy Quick Citation from Litrix, then paste as inline text or footnote."
                        ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !pluginResourceStatusMessage.isEmpty {
                            Text(pluginResourceStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsInputRow(title: localized(chinese: "网页插件", english: "Web Plug-ins")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                checkSafariWebPlugin()
                            } label: {
                                if isCheckingSafariWebPlugin {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(localized(chinese: "检查 Safari", english: "Check Safari"))
                                }
                            }
                            .disabled(isCheckingSafariWebPlugin)

                            Button {
                                checkChromeWebPlugin()
                            } label: {
                                if isCheckingChromeWebPlugin {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(localized(chinese: "检查 Chrome", english: "Check Chrome"))
                                }
                            }
                            .disabled(isCheckingChromeWebPlugin)

                            Button(localized(chinese: "教程", english: "Tutorial")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "Tutorials",
                                    "Litrix-浏览器插件教程.txt"
                                ])
                            }
                        }

                        Text(localized(
                            chinese: "用于从网页读取文献信息、下载 PDF 并写入 Litrix。检查未检测到已加载插件时，会打开对应浏览器的重新加载/安装入口。",
                            english: "Use this plug-in to read paper metadata from web pages, download PDFs, and add them to Litrix. If the plug-in is not detected, the check opens the browser-specific install or reload entry."
                        ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !pluginResourceStatusMessage.isEmpty {
                            Text(pluginResourceStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var importerPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "浏览器插件", english: "Browser Plug-in"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "网页文献导入", english: "Web Paper Import")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button(localized(chinese: "安装 Chrome/Edge/Firefox 插件", english: "Install Chrome/Edge/Firefox Plug-in")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "BrowserImporter"
                                ])
                            }

                            Button(localized(chinese: "安装 Safari 插件", english: "Install Safari Plug-in")) {
                                checkSafariWebPlugin()
                            }

                            Button(localized(chinese: "教程", english: "Tutorial")) {
                                openBundledPluginResource([
                                    "Plugins",
                                    "Tutorials",
                                    "Litrix-浏览器插件教程.txt"
                                ])
                            }
                        }

                        Text(localized(
                            chinese: "浏览器插件已适配 mac。Safari 通过系统转换器生成本地 Safari Web Extension，其余浏览器直接加载 BrowserImporter 目录。",
                            english: "Browser plug-ins are adapted for macOS. Safari uses the system converter to generate a local Safari Web Extension; other browsers load BrowserImporter directly."
                        ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !pluginResourceStatusMessage.isEmpty {
                            Text(pluginResourceStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var exportPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "BibTeX", showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "字段", english: "Fields")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Title", isOn: exportFieldBinding(\.title))
                        Toggle("Author", isOn: exportFieldBinding(\.author))
                        Toggle("Year", isOn: exportFieldBinding(\.year))
                        Toggle("Journal", isOn: exportFieldBinding(\.journal))
                        Toggle("DOI", isOn: exportFieldBinding(\.doi))
                        Toggle("Volume", isOn: exportFieldBinding(\.volume))
                        Toggle("Number (Issue)", isOn: exportFieldBinding(\.number))
                        Toggle("Pages", isOn: exportFieldBinding(\.pages))
                        Toggle("Abstract", isOn: exportFieldBinding(\.abstract))
                    }
                    .toggleStyle(.checkbox)
                }

                SettingsInputRow(title: localized(chinese: "操作", english: "Actions")) {
                    Button(localized(chinese: "恢复默认字段", english: "Restore Default Fields")) {
                        settings.resetExportFieldsToDefault()
                    }
                }
            }
        }
    }

    private var columnPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "列", english: "Columns"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "操作", english: "Actions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(localized(chinese: "刷新文库列顺序", english: "Refresh Library Column Order")) {
                            workspace.requestTableColumnRefresh()
                        }
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                        Text("After reordering here, click refresh to apply immediately in Library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: localized(chinese: "拖拽排序", english: "Drag To Reorder")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(settings.paperTableColumnOrder.enumerated()), id: \.element) { index, column in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)

                                Toggle(column.displayName(for: settings.appLanguage), isOn: tableColumnBinding(column))
                                    .toggleStyle(.checkbox)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggingTableColumn = column
                                return NSItemProvider(object: NSString(string: column.rawValue))
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: TableColumnOrderDropDelegate(
                                    target: column,
                                    order: tableColumnOrderBinding,
                                    dragging: $draggingTableColumn
                                )
                            )

                            if index < settings.paperTableColumnOrder.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .frame(maxWidth: 620, alignment: .leading)
                }
            }
        }
    }

    private var rowPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: localized(chinese: "表格", english: "Table"), showsDivider: false) {
                SettingsInputRow(title: localized(chinese: "行高模式", english: "Row Height Mode")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized(chinese: "紧凑模式：1x 单行；扩展模式：使用下方倍率并自动换行。", english: "Compact mode: 1x single-line rows; Expanded mode: uses the scale below with wrapped text."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(localized(chinese: "快捷键：Command + = 开启扩展模式；Command + - 返回紧凑模式。", english: "Shortcuts: Command + = for Expanded mode; Command + - for Compact mode."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: localized(chinese: "扩展行倍率", english: "Expanded Row Scale")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.rowHeightScaleFactor, in: 1...6, step: 1)
                            Text("\(Int(settings.resolvedTableRowHeightScaleFactor))x")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .frame(maxWidth: 520, alignment: .leading)

                        Text(localized(chinese: "扩展行视图使用此倍率，并限制在单倍行高的 6x 内。默认：6x。", english: "Expanded row view uses this scale and is capped at 6x the compact row height. Default: 6x."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: localized(chinese: "图片缩略图最大尺寸", english: "Image Thumbnail Max Size")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.imageThumbnailMaxSizeMultiplier, in: 0.1...4, step: 0.1)
                            Text("\(settings.imageThumbnailMaxSizeMultiplier, specifier: "%.1f")x")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .frame(maxWidth: 520, alignment: .leading)

                        Text("Max thumbnail size = row height × this multiplier. Default: 0.5x")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var citationPresetBinding: Binding<CitationPreset> {
        Binding(
            get: { settings.citationPreset },
            set: { newValue in
                settings.applyCitationPreset(newValue)
            }
        )
    }

    private var metadataProviderBinding: Binding<MetadataAPIProvider> {
        Binding(
            get: { settings.metadataAPIProvider },
            set: { newValue in
                settings.applyMetadataAPIProvider(newValue)
            }
        )
    }

    private var inTextCitationBinding: Binding<String> {
        Binding(
            get: { settings.inTextCitationTemplate },
            set: { newValue in
                settings.inTextCitationTemplate = newValue
                if settings.citationPreset != .custom {
                    settings.citationPreset = .custom
                }
            }
        )
    }

    private var referenceCitationBinding: Binding<String> {
        Binding(
            get: { settings.referenceCitationTemplate },
            set: { newValue in
                settings.referenceCitationTemplate = newValue
                if settings.citationPreset != .custom {
                    settings.citationPreset = .custom
                }
            }
        )
    }

    private func exportFieldBinding(_ keyPath: WritableKeyPath<BibTeXExportFieldOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.exportBibTeXFields[keyPath: keyPath] },
            set: { newValue in
                var options = settings.exportBibTeXFields
                options[keyPath: keyPath] = newValue
                settings.exportBibTeXFields = options
            }
        )
    }

    private func tableColumnBinding(_ keyPath: WritableKeyPath<PaperTableColumnVisibility, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.paperTableColumnVisibility[keyPath: keyPath] },
            set: { newValue in
                var options = settings.paperTableColumnVisibility
                options[keyPath: keyPath] = newValue
                settings.paperTableColumnVisibility = options
            }
        )
    }

    private func tableColumnBinding(_ column: PaperTableColumn) -> Binding<Bool> {
        tableColumnBinding(column.visibilityKeyPath)
    }

    private var tableColumnOrderBinding: Binding<[PaperTableColumn]> {
        Binding(
            get: { settings.paperTableColumnOrder },
            set: { settings.applyPaperTableColumnOrder($0) }
        )
    }

    private var tableSelectionTextColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hexString: settings.tableSelectionTextColorHex)
                    ?? Color(hexString: SettingsStore.defaultTableSelectionTextColorHex)
                    ?? .white
            },
            set: { color in
                settings.tableSelectionTextColorHex = color.hexRGB ?? SettingsStore.defaultTableSelectionTextColorHex
            }
        )
    }

    private var starColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hexString: settings.starColorHex)
                    ?? Color(hexString: SettingsStore.defaultStarColorHex)
                    ?? Color(red: 0x5D / 255, green: 0xC3 / 255, blue: 0xF5 / 255)
            },
            set: { color in
                settings.starColorHex = color.hexRGB ?? SettingsStore.defaultStarColorHex
            }
        )
    }

    private var zombieThresholds: [ZombiePaperThreshold] {
        ZombiePaperThreshold.sliderOrdered
    }

    private var zombieThresholdIndexBinding: Binding<Double> {
        Binding(
            get: {
                let index = zombieThresholds.firstIndex(of: settings.zombiePapersThreshold) ?? 0
                return Double(index)
            },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                let clamped = max(0, min(zombieThresholds.count - 1, rounded))
                settings.zombiePapersThreshold = zombieThresholds[clamped]
            }
        )
    }

    private var recentlyDeletedRetentionDaysBinding: Binding<Double> {
        Binding(
            get: { Double(settings.recentlyDeletedRetentionDays) },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                let range = SettingsStore.recentlyDeletedRetentionDayRange
                settings.recentlyDeletedRetentionDays = min(max(rounded, range.lowerBound), range.upperBound)
            }
        )
    }

    private var recentlyDeletedRetentionLabel: String {
        let days = settings.recentlyDeletedRetentionDays
        if settings.appLanguage == .english {
            return days == 1 ? "1 day" : "\(days) days"
        }
        return "\(days) 天"
    }

    private var generalErrorPresented: Binding<Bool> {
        Binding(
            get: { generalErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    generalErrorMessage = nil
                }
            }
        )
    }

    private func browsePapersDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.resolvedPapersDirectoryURL
        panel.prompt = "Choose"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        papersDirectoryDraft = url.standardizedFileURL.path
        papersDirectoryBookmarkPath = url.standardizedFileURL.path
        papersDirectoryBookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func applyPapersDirectoryChange() {
        let trimmed = papersDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            papersDirectoryDraft = settings.resolvedPapersDirectoryURL.path
            return
        }

        let expandedPath = (trimmed as NSString).expandingTildeInPath
        let destination = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try store.migratePapersDirectory(to: destination)
            let bookmarkData = papersDirectoryBookmarkPath == destination.path ? papersDirectoryBookmarkData : nil
            settings.updatePapersStorageDirectory(to: destination, bookmarkData: bookmarkData)
            papersDirectoryDraft = destination.path
            papersDirectoryBookmarkData = nil
            papersDirectoryBookmarkPath = nil
        } catch {
            generalErrorMessage = error.localizedDescription
        }
    }

    private func checkAPIConnection() {
        guard !isCheckingConnection else { return }
        isCheckingConnection = true
        connectionCheckOutput = "Checking connection..."

        Task {
            do {
                let reply = try await MetadataEnrichmentService.checkConnection(
                    apiProvider: settings.resolvedAPIProvider,
                    apiEndpoint: settings.resolvedAPIEndpoint,
                    apiKey: settings.resolvedAPIKey,
                    model: settings.resolvedModel,
                    thinkingEnabled: settings.resolvedThinkingEnabled
                )
                await MainActor.run {
                    connectionCheckOutput = "Connection succeeded.\n\n\(reply)"
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionCheckOutput = "Connection failed.\n\n\(error.localizedDescription)"
                    isCheckingConnection = false
                }
            }
        }
    }

    private func checkPDF2ZHInstallation() {
        guard !isCheckingPDF2ZH else { return }

        guard let activationLines = settings.pdf2zhActivationShellLines() else {
            pdf2zhCheckOutput = """
            Environment activation is not configured yet.

            Install with:
            \(settings.pdf2zhInstallInstructions())
            """
            return
        }

        isCheckingPDF2ZH = true
        pdf2zhCheckOutput = "Checking pdf2zh..."

        let script = (activationLines + [
            "if command -v pdf2zh >/dev/null 2>&1; then",
            "  echo status=installed",
            "  echo version=$(pdf2zh --version 2>/dev/null)",
            "  echo path=$(command -v pdf2zh)",
            "  echo env=${CONDA_DEFAULT_ENV:-system}",
            "  echo python=$(command -v python)",
            "else",
            "  echo status=missing",
            "fi"
        ]).joined(separator: "\n")

        Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh", isDirectory: false)
            process.arguments = ["-lc", script]
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                await MainActor.run {
                    if output.contains("status=installed") {
                        let cleaned = output
                            .split(separator: "\n")
                            .filter { !$0.hasPrefix("status=") }
                            .joined(separator: "\n")
                        pdf2zhCheckOutput = cleaned
                    } else if output.contains("status=missing") {
                        pdf2zhCheckOutput = """
                        pdf2zh is not installed in the configured environment.

                        Install with:
                        \(settings.pdf2zhInstallInstructions())
                        """
                    } else {
                        let details = (output + "\n" + errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
                        pdf2zhCheckOutput = details.isEmpty
                            ? "pdf2zh check failed."
                            : details
                    }
                    isCheckingPDF2ZH = false
                }
            } catch {
                await MainActor.run {
                    pdf2zhCheckOutput = """
                    Failed to run pdf2zh check: \(error.localizedDescription)

                    Install with:
                    \(settings.pdf2zhInstallInstructions())
                    """
                    isCheckingPDF2ZH = false
                }
            }
        }
    }

    private func renameStoredPDFFilesFromMetadata() {
        let renamedCount = store.renameAllStoredPDFsToMetadataPattern()
        generalStatusMessage = localized(
            chinese: "已重命名 \(renamedCount) 个 PDF 文件。",
            english: "Renamed \(renamedCount) PDF files."
        )
    }

    private func generateMCPConfiguration() {
        do {
            let url = try settings.generateMCPConfigurationFile(for: mcpClientType)
            refreshMCPPreview()
            mcpConfigStatusOutput = "配置已生成：\(url.path)"
        } catch {
            mcpConfigStatusOutput = "配置生成失败：\(error.localizedDescription)"
        }
    }

    private func refreshMCPPreview() {
        mcpConfigOutput = settings.mcpConfigurationSnippet(for: mcpClientType)
        mcpUsageOutput = settings.mcpUsageGuide(for: mcpClientType)
    }

    private func copyMCPConfiguration() {
        refreshMCPPreview()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(mcpConfigOutput, forType: .string)
        mcpConfigStatusOutput = "已复制配置内容"
    }

    private func copyMCPUsage() {
        refreshMCPPreview()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(mcpUsageOutput, forType: .string)
        mcpConfigStatusOutput = "已复制使用说明"
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        let isNewWindow = configuredWindowNumber != window.windowNumber
        if isNewWindow {
            configuredWindowNumber = window.windowNumber
            didApplyInitialWindowSize = false
        }

        window.title = localized(chinese: "Litrix设置", english: "Litrix Settings")
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = true
        window.toolbar = nil

        let screenHeight = window.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        let maxHeight = max(360, floor(screenHeight * 0.8))
        let desiredHeight = max(minimumWindowHeight, min(headerHeight + paneHeight + 16, maxHeight))

        window.minSize = NSSize(width: minimumWindowWidth, height: minimumWindowHeight)
        window.maxSize = NSSize(width: maximumWindowWidth, height: maxHeight)

        let currentContentSize = window.contentLayoutRect.size
        let clampedWidth = min(max(baseWindowWidth, minimumWindowWidth), maximumWindowWidth)

        if didApplyInitialWindowSize {
            if abs(currentContentSize.height - desiredHeight) > 1
                || abs(currentContentSize.width - clampedWidth) > 1 {
                window.setContentSize(
                    NSSize(
                        width: clampedWidth,
                        height: desiredHeight
                    )
                )
            }
            return
        }

        didApplyInitialWindowSize = true
        let initialWidth = min(max(baseWindowWidth, minimumWindowWidth), maximumWindowWidth)
        window.setContentSize(NSSize(width: initialWidth, height: desiredHeight))
    }

    private func localized(chinese: String, english: String) -> String {
        settings.appLanguage == .english ? english : chinese
    }

    private func checkSafariWebPlugin() {
        isCheckingSafariWebPlugin = true
        pluginResourceStatusMessage = localized(
            chinese: "正在检查 Safari 网页插件…",
            english: "Checking Safari web plug-in..."
        )

        Task { @MainActor in
            let wasRegistered = await Task.detached(priority: .utility) {
                Self.safariWebPluginIsLoaded()
            }.value

            guard let scriptURL = bundledPluginResourceURL([
                "Plugins",
                "BrowserImporter",
                "Safari",
                "create-safari-extension.command"
            ]) else {
                isCheckingSafariWebPlugin = false
                pluginResourceStatusMessage = localized(
                    chinese: "未找到 Safari 插件安装器。",
                    english: "Safari plug-in installer was not found."
                )
                return
            }

            pluginResourceStatusMessage = wasRegistered
                ? localized(
                    chinese: "检测到 Safari 插件注册记录，正在重新注册并打开宿主 App…",
                    english: "Safari plug-in registration was found. Re-registering and opening the host app..."
                )
                : localized(
                    chinese: "未检测到 Safari 网页插件，正在后台生成并打开 Safari 插件宿主 App…",
                    english: "Safari web plug-in was not detected. Generating and opening the Safari extension host app in the background..."
                )

            let result = await Task.detached(priority: .utility) {
                Self.runProcessResult(
                    executablePath: "/bin/zsh",
                    arguments: [scriptURL.path],
                    timeoutSeconds: 240
                )
            }.value
            let isLoaded = await Task.detached(priority: .utility) {
                Self.safariWebPluginIsLoaded()
            }.value
            isCheckingSafariWebPlugin = false

            if result.timedOut {
                pluginResourceStatusMessage = localized(
                    chinese: "Safari 插件安装等待超时。请稍后再点“检查 Safari”；如果仍未出现，请手动运行 create-safari-extension.command。",
                    english: "Safari plug-in installation timed out. Try Check Safari again shortly; if it still does not appear, run create-safari-extension.command manually."
                )
            } else if result.exitCode == 0 {
                pluginResourceStatusMessage = localized(
                    chinese: isLoaded
                        ? "已重新注册并打开 Litrix Safari Importer。请在 Safari 设置 > 扩展 中启用它；如果列表仍没有 Litrix，请退出 Safari 后重开，再点一次“检查 Safari”。"
                        : "已运行 Safari 插件安装器，但系统尚未报告插件已加载。请退出 Safari 后重开，再点一次“检查 Safari”。",
                    english: isLoaded
                        ? "Litrix Safari Importer has been re-registered and opened. Enable it in Safari Settings > Extensions; if it still does not appear, quit and reopen Safari, then Check Safari again."
                        : "The Safari plug-in installer ran, but the system has not reported it as loaded yet. Quit and reopen Safari, then Check Safari again."
                )
            } else {
                let tail = Self.shortCommandOutput(result.output)
                pluginResourceStatusMessage = localized(
                    chinese: "Safari 插件命令行安装未完成，已尽量打开生成工程。\(tail.isEmpty ? "" : "\n\(tail)")",
                    english: "Safari plug-in command-line install did not finish; the generated project was opened when possible.\(tail.isEmpty ? "" : "\n\(tail)")"
                )
            }
        }
    }
    private func checkChromeWebPlugin() {
        isCheckingChromeWebPlugin = true
        pluginResourceStatusMessage = localized(
            chinese: "正在检查 Chrome 网页插件…",
            english: "Checking Chrome web plug-in..."
        )

        Task { @MainActor in
            let isLoaded = await Task.detached(priority: .utility) {
                Self.chromeWebPluginIsLoaded()
            }.value
            isCheckingChromeWebPlugin = false

            if isLoaded {
                pluginResourceStatusMessage = localized(
                    chinese: "Chrome 网页插件已加载。",
                    english: "Chrome web plug-in is loaded."
                )
            } else {
                openChromeExtensionsPage()
                openBundledPluginResource(["Plugins", "BrowserImporter"])
                pluginResourceStatusMessage = localized(
                    chinese: "未检测到 Chrome 网页插件，已打开 Chrome 扩展页和 BrowserImporter 目录。请开启开发者模式，选择“加载已解压的扩展程序”，或在已安装项上点重新加载。",
                    english: "Chrome web plug-in was not detected. Chrome Extensions and the BrowserImporter folder have been opened. Enable Developer Mode, choose Load unpacked, or reload the existing item."
                )
            }
        }
    }

    private func openChromeExtensionsPage() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
        process.arguments = ["-a", "Google Chrome", "chrome://extensions"]
        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(URL(string: "https://www.google.com/chrome/")!)
        }
    }

    private func openBundledPluginResource(_ components: [String]) {
        guard let url = bundledPluginResourceURL(components) else {
            let missingPath = components.joined(separator: "/")
            pluginResourceStatusMessage = localized(
                chinese: "未找到插件资源：\(missingPath)",
                english: "Plug-in resource not found: \(missingPath)"
            )
            return
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        pluginResourceStatusMessage = localized(
            chinese: "已打开：\(url.lastPathComponent)",
            english: "Opened: \(url.lastPathComponent)"
        )

        if isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func bundledPluginResourceURL(_ components: [String]) -> URL? {
        let baseURLs = [
            Bundle.module.resourceURL,
            Bundle.main.resourceURL
        ].compactMap { $0 }

        for baseURL in baseURLs {
            let candidate = components.reduce(baseURL) { url, component in
                url.appendingPathComponent(component, isDirectory: false)
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    nonisolated private static func safariWebPluginIsLoaded() -> Bool {
        let output = runProcess(
            executablePath: "/usr/bin/pluginkit",
            arguments: ["-m", "-A", "-D", "-v", "-p", "com.apple.Safari.web-extension"]
        )
        .lowercased()

        return output.contains("com.rooby.litrix.safariimporter")
            || output.contains("litrix safari importer")
    }

    nonisolated private static func chromeWebPluginIsLoaded() -> Bool {
        let chromeRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        guard FileManager.default.fileExists(atPath: chromeRoot.path) else { return false }

        let preferenceNames = ["Preferences", "Secure Preferences"]
        guard let profileURLs = try? FileManager.default.contentsOfDirectory(
            at: chromeRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        for profileURL in profileURLs {
            let isDirectory = (try? profileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }

            for preferenceName in preferenceNames {
                let preferenceURL = profileURL.appendingPathComponent(preferenceName, isDirectory: false)
                guard let data = try? Data(contentsOf: preferenceURL),
                      let text = String(data: data, encoding: .utf8)?.lowercased() else {
                    continue
                }
                if text.contains("litrix web importer")
                    || text.contains("browserimporter")
                    || text.contains("com.rooby.litrix") {
                    return true
                }
            }
        }

        return false
    }

    nonisolated private static func runProcess(executablePath: String, arguments: [String]) -> String {
        runProcessResult(
            executablePath: executablePath,
            arguments: arguments,
            timeoutSeconds: 3
        ).output
    }

    nonisolated private static func runProcessResult(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> (exitCode: Int32, output: String, timedOut: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath, isDirectory: false)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            let semaphore = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                semaphore.signal()
            }
            try process.run()
            if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.15)
                if process.isRunning {
                    process.interrupt()
                }
                let data = pipe.fileHandleForReading.availableData
                return (exitCode: -1, output: String(data: data, encoding: .utf8) ?? "", timedOut: true)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (
                exitCode: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? "",
                timedOut: false
            )
        } catch {
            return (exitCode: -1, output: error.localizedDescription, timedOut: false)
        }
    }

    nonisolated private static func shortCommandOutput(_ output: String) -> String {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .suffix(8)
        return lines.joined(separator: "\n")
    }

}

private struct SettingsHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsPaneHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var showsDivider: Bool = true
    let content: () -> Content

    init(
        title: String,
        showsDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)

            if showsDivider {
                Divider()
            }
        }
    }
}

private struct SettingsInputRow<Content: View>: View {
    let title: String
    let content: () -> Content

    init(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TableColumnOrderDropDelegate: DropDelegate {
    let target: PaperTableColumn
    @Binding var order: [PaperTableColumn]
    @Binding var dragging: PaperTableColumn?

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

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
