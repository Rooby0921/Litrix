import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case api
    case pdf2zh
    case citation
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
        case .export:
            return "Export"
        case .column:
            return "Column"
        case .row:
            return "Row"
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
    @State private var draggingTableColumn: PaperTableColumn?
    @State private var configuredWindowNumber: Int?
    @State private var didApplyInitialWindowSize = false
    @State private var headerHeight: CGFloat = 120
    @State private var paneHeight: CGFloat = 500
    private let baseWindowWidth: CGFloat = 504
    private let minimumWindowWidth: CGFloat = 500
    private let maximumWindowWidth: CGFloat = 620
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
        .frame(minWidth: minimumWindowWidth)
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
        .padding(.top, 8)
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
                Text(pane.title)
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
        .help(pane.title)
        .accessibilityLabel(pane.title)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Storage") {
                SettingsInputRow(title: "Papers Directory") {
                    HStack(spacing: 10) {
                        TextField("e.g. ~/Litrix/Papers", text: $papersDirectoryDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)

                        Button("Browse...") {
                            browsePapersDirectory()
                        }
                    }
                }

                SettingsInputRow(title: "Actions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button("Apply and Move Data") {
                                applyPapersDirectoryChange()
                            }

                            Button("Open Folder") {
                                settings.openPapersStorageFolder()
                            }
                        }

                        Button("Reset to Default") {
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

            SettingsSection(title: "Reading") {
                SettingsInputRow(title: "Recent Window") {
                    Picker("Recent Reading", selection: $settings.recentReadingRange) {
                        ForEach(RecentReadingRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 460)
                }

                SettingsInputRow(title: "Zombie Window") {
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

            SettingsSection(title: "PDF") {
                SettingsInputRow(title: "Source File Naming") {
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

            SettingsSection(title: "Language", showsDivider: false) {
                SettingsInputRow(title: "App Language") {
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
            SettingsSection(title: "Provider") {
                SettingsInputRow(title: "API Provider") {
                    Picker("API Provider", selection: metadataProviderBinding) {
                        ForEach(MetadataAPIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }

                SettingsInputRow(title: "API Endpoint") {
                    TextField(SettingsStore.defaultAPIBaseURL, text: $settings.metadataAPIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: "API Key") {
                    SecureField("Enter API Key", text: $settings.metadataAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: "Model") {
                    TextField(SettingsStore.defaultModel, text: $settings.metadataModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                }

                SettingsInputRow(title: "Reasoning Mode") {
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

            SettingsSection(title: "Validation") {
                SettingsInputRow(title: "API Test") {
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

                SettingsInputRow(title: "Prompt") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Edit Prompt") {
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

                SettingsInputRow(title: "Connection Result") {
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
                SettingsInputRow(title: "Enable MCP") {
                    Toggle("启用 Litrix MCP", isOn: $settings.mcpEnabled)
                        .toggleStyle(.switch)
                }

                SettingsInputRow(title: "Runtime") {
                    Text(mcpServer.runtimeStatusText)
                        .font(.footnote)
                        .foregroundStyle(mcpServer.runtimeListening ? .green : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsInputRow(title: "Client") {
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

                SettingsInputRow(title: "Server") {
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

                SettingsInputRow(title: "Configuration") {
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

                SettingsInputRow(title: "Custom Limits") {
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

                SettingsInputRow(title: "Supported Features") {
                    Text("""
                    查看任意文献元数据、编辑任意文献元数据、语义搜索、普通检索、文库结构读取、摘要读取、全文提取、批注搜索、相似文献查找、条目详情、缓存状态、语义索引状态、Collection 管理、条目增改、标签管理、笔记创建/追加
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSection(title: "Storage", showsDivider: false) {
                SettingsInputRow(title: "Data Folder") {
                    Button("Open Data Folder") {
                        settings.openStorageFolder()
                    }
                }
            }
        }
    }

    private var pdf2zhPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Installation") {
                SettingsInputRow(title: "Check") {
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

                SettingsInputRow(title: "Status") {
                    Text(pdf2zhCheckOutput.isEmpty ? "Not checked yet." : pdf2zhCheckOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: 520, alignment: .leading)
                }

                SettingsInputRow(title: "Install Command") {
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

            SettingsSection(title: "Environment") {
                SettingsInputRow(title: "Execution Mode") {
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
                    SettingsInputRow(title: "Environment Name") {
                        TextField(
                            settings.pdf2zhEnvironmentKind == .base ? "base" : SettingsStore.defaultPDF2ZHEnvironmentName,
                            text: $settings.pdf2zhEnvironmentName
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 520)
                    }
                } else {
                    SettingsInputRow(title: "Activation Command") {
                        TextField("source ~/miniconda3/etc/profile.d/conda.sh && conda activate tools-dev", text: $settings.pdf2zhCustomActivationCommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)
                    }
                }

                SettingsInputRow(title: "Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Right-click “Translate via pdf2zh” uses the current API Endpoint, API Key, Model, and Reasoning Mode from the API pane.")
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
            SettingsSection(title: "Templates", showsDivider: false) {
                SettingsInputRow(title: "Preset") {
                    Picker("Preset", selection: citationPresetBinding) {
                        ForEach(CitationPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                SettingsInputRow(title: "In-text Citation") {
                    TextField("e.g. ({{author}}, {{year}})", text: inTextCitationBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 620)
                }

                SettingsInputRow(title: "Bibliography Citation") {
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

                SettingsInputRow(title: "Placeholders") {
                    Text("{{author}} {{apaInTextAuthors}} {{apaReferenceAuthors}} {{year}} {{title}} {{journal}} {{volume}} {{number}} {{pages}} {{doi}} {{page}}")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var exportPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "BibTeX", showsDivider: false) {
                SettingsInputRow(title: "Fields") {
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

                SettingsInputRow(title: "Actions") {
                    Button("Restore Default Fields") {
                        settings.resetExportFieldsToDefault()
                    }
                }
            }
        }
    }

    private var columnPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Columns", showsDivider: false) {
                SettingsInputRow(title: "Actions") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Refresh Library Column Order") {
                            workspace.requestTableColumnRefresh()
                        }
                        .keyboardShortcut("r", modifiers: [.command, .shift])

                        Text("After reordering here, click refresh to apply immediately in Library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: "Drag To Reorder") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(settings.paperTableColumnOrder.enumerated()), id: \.element) { index, column in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)

                                Toggle(column.displayName, isOn: tableColumnBinding(column))
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
            SettingsSection(title: "Table", showsDivider: false) {
                SettingsInputRow(title: "Maximum Row Height / 最大行高") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.rowHeightScaleFactor, in: 1...24, step: 1)
                            Text("\(Int(settings.rowHeightScaleFactor))x")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .frame(width: 42, alignment: .trailing)
                        }
                        .frame(maxWidth: 520, alignment: .leading)

                        Text("Compact: 1 line. Expanded: auto-fit content up to \(Int(settings.resolvedMaximumTableRowHeight)) pt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("快捷键：Command + = 开启扩展模式；Command + - 返回紧凑模式。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsInputRow(title: "Image Thumbnail Max Size") {
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
            let url = try settings.generateMCPConfigurationFile()
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
        let clampedWidth = min(max(currentContentSize.width, minimumWindowWidth), maximumWindowWidth)

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
