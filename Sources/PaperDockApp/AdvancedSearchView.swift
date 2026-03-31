import AppKit
import SwiftUI

struct AdvancedSearchView: View {
    @ObservedObject var store: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @Binding var isPresented: Bool
    let onSelectPaper: (Paper) -> Void

    @State private var state = AdvancedSearchState()
    @State private var results: [Paper] = []
    @State private var selectedResultIDs: Set<UUID> = []
    @State private var resultIDSet: Set<UUID> = []
    @State private var resultIndexByID: [UUID: Int] = [:]
    @State private var pendingSearchTask: Task<Void, Never>?
    @State private var localKeyMonitor: Any?
    @State private var activeQuickLookURL: URL?

    private static let addedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Advanced Search")
                    .font(.largeTitle.weight(.bold))
                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                Text("Search in:")
                Picker("", selection: $state.scope) {
                    ForEach(scopeOptions, id: \.selection) { option in
                        Text(option.label).tag(option.selection)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 260)
            }

            HStack(spacing: 10) {
                Text("Match")
                Picker("", selection: $state.matchMode) {
                    ForEach(AdvancedSearchMatchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Text("Conditions:")
            }

            VStack(spacing: 12) {
                ForEach($state.conditions) { $condition in
                    HStack(spacing: 12) {
                        Picker("", selection: $condition.field) {
                            ForEach(AdvancedSearchField.allCases) { field in
                                Text(field.title).tag(field)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)

                        Picker("", selection: $condition.operator) {
                            ForEach(AdvancedSearchOperator.allCases) { `operator` in
                                Text(`operator`.title).tag(`operator`)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)

                        TextField("Enter search value", text: $condition.value)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            remove(conditionID: condition.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)

                        Button {
                            addCondition(after: condition.id)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Search") {
                    scheduleRunSearch()
                }
                .keyboardShortcut(.defaultAction)

                Button("Clear") {
                    let preservedScope = state.scope
                    state = AdvancedSearchState()
                    state.scope = preservedScope
                    applySearchResults([])
                }

                Button("Save Results to Collection") {
                    saveResultsAsCollection()
                }
                .disabled(results.isEmpty)
            }

            Table(results, selection: $selectedResultIDs) {
                resultTableColumns
            }
            .frame(minHeight: 420)
            .onTapGesture(count: 2) {
                // Wait one run-loop so Table selection binding settles before resolving target row.
                DispatchQueue.main.async {
                    openSelectedResult()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 1280, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            ensureValidScopeSelection()
            scheduleRunSearch()
            installLocalKeyMonitorIfNeeded()
        }
        .onDisappear {
            pendingSearchTask?.cancel()
            pendingSearchTask = nil
            removeLocalKeyMonitor()
        }
        .onChange(of: state.scope) {
            scheduleRunSearch()
        }
        .onChange(of: store.collections) {
            ensureValidScopeSelection()
            scheduleRunSearch(delayNanoseconds: 80_000_000)
        }
        .onChange(of: store.tags) {
            ensureValidScopeSelection()
            scheduleRunSearch(delayNanoseconds: 80_000_000)
        }
        .onExitCommand {
            isPresented = false
        }
    }

    @TableColumnBuilder<Paper, Never>
    private var resultTableColumns: some TableColumnContent<Paper, Never> {
        TableColumnForEach(visiblePaperTableColumns, id: \.self) { column in
            TableColumn(column.displayName) { paper in
                resultCell(for: paper, column: column)
            }
            .width(min: 0, ideal: settings.paperTableColumnWidth(for: column), max: nil)
        }
    }

    @ViewBuilder
    private func resultCell(for paper: Paper, column: PaperTableColumn) -> some View {
        switch column {
        case .title:
            HStack(spacing: 8) {
                Image(systemName: store.hasExistingPDFAttachment(for: paper) ? "doc.text" : "doc.badge.questionmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(displayValue(for: paper, column: .title).isEmpty ? "Untitled Paper" : displayValue(for: paper, column: .title))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .lineLimit(2)
            }
        case .rating:
            StarRatingBadge(rating: paper.rating)
        case .image:
            imageCell(for: paper)
        case .tags:
            tagsCell(for: paper)
        default:
            let value = displayValue(for: paper, column: column)
            Text(value.isEmpty ? "—" : value)
                .font(cellFont(for: column))
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func imageCell(for paper: Paper) -> some View {
        let urls = store.imageURLs(for: paper)
        if urls.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(urls.prefix(3)), id: \.self) { url in
                    ThumbnailImageView(url: url, maxPixel: 40, placeholderOpacity: 0.18)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if urls.count > 3 {
                    Text("+\(urls.count - 3)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func tagsCell(for paper: Paper) -> some View {
        if paper.tags.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(paper.tags.prefix(6)), id: \.self) { tag in
                    Circle()
                        .fill(tagColor(for: tag) ?? Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
                if paper.tags.count > 6 {
                    Text("+\(paper.tags.count - 6)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cellFont(for column: PaperTableColumn) -> Font {
        switch column {
        case .addedTime, .editedTime:
            return .system(size: 12.5, weight: .regular, design: .monospaced)
        default:
            return .system(size: 13, weight: .regular, design: .rounded)
        }
    }

    private func tagColor(for tag: String) -> Color? {
        guard let hex = store.tagColorHexes[tag] else { return nil }
        let normalized = hex.replacingOccurrences(of: "#", with: "")
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    private func displayValue(for paper: Paper, column: PaperTableColumn) -> String {
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

    private func formattedAddedTime(from milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        return Self.addedTimeFormatter.string(from: date)
    }

    private func formattedEditedTime(from milliseconds: Int64?) -> String {
        guard let milliseconds else { return "—" }
        return formattedAddedTime(from: milliseconds)
    }

    private var normalizedPaperTableColumnOrder: [PaperTableColumn] {
        var normalized: [PaperTableColumn] = []
        for column in settings.paperTableColumnOrder where !normalized.contains(column) {
            normalized.append(column)
        }
        for column in PaperTableColumn.defaultOrder where !normalized.contains(column) {
            normalized.append(column)
        }
        return normalized
    }

    private var visiblePaperTableColumns: [PaperTableColumn] {
        let visible = normalizedPaperTableColumnOrder.filter { settings.paperTableColumnVisibility[$0] }
        return visible.isEmpty ? [normalizedPaperTableColumnOrder.first ?? .title] : visible
    }

    private var scopeOptions: [AdvancedSearchScopeOption] {
        var options: [AdvancedSearchScopeOption] = SystemLibrary.allCases.map { library in
            AdvancedSearchScopeOption(
                selection: .library(library),
                label: "Library: \(library.englishTitle)"
            )
        }

        options.append(
            contentsOf: store.collections.map { collection in
                AdvancedSearchScopeOption(
                    selection: .collection(collection),
                    label: "Collection: \(collection)"
                )
            }
        )

        options.append(
            contentsOf: store.tags.map { tag in
                AdvancedSearchScopeOption(
                    selection: .tag(tag),
                    label: "Tag: \(tag)"
                )
            }
        )

        return options
    }

    private func ensureValidScopeSelection() {
        let validScopes = Set(scopeOptions.map(\.selection))
        if !validScopes.contains(state.scope) {
            state.scope = .library(.all)
        }
    }

    private func addCondition(after id: UUID) {
        guard let index = state.conditions.firstIndex(where: { $0.id == id }) else { return }
        state.conditions.insert(AdvancedSearchCondition(), at: index + 1)
    }

    private func remove(conditionID: UUID) {
        guard state.conditions.count > 1 else { return }
        state.conditions.removeAll(where: { $0.id == conditionID })
    }

    private func runSearch() {
        let perfStart = PerformanceMonitor.now()
        let scopedPapers = store.filteredPapers(for: state.scope, searchText: "")
        let nextResults = state.results(in: scopedPapers)
        applySearchResults(nextResults)
        let activeConditionCount = state.conditions.filter {
            $0.operator == .isEmpty || !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        PerformanceMonitor.logElapsed(
            "AdvancedSearchView.runSearch",
            from: perfStart,
            thresholdMS: 10
        ) {
            "scope=\(state.scope.performanceLabel), scoped=\(scopedPapers.count), results=\(nextResults.count), activeConditions=\(activeConditionCount), matchMode=\(state.matchMode.rawValue)"
        }
    }

    private func scheduleRunSearch(delayNanoseconds: UInt64 = 0) {
        pendingSearchTask?.cancel()
        pendingSearchTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            runSearch()
            pendingSearchTask = nil
        }
    }

    private func applySearchResults(_ papers: [Paper]) {
        results = papers
        let ids = papers.map(\.id)
        resultIDSet = Set(ids)
        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(ids.count)
        for (index, id) in ids.enumerated() {
            indexByID[id] = index
        }
        resultIndexByID = indexByID
        selectedResultIDs = selectedResultIDs.intersection(resultIDSet)
    }

    private func openSelectedResult() {
        let targetPaper: Paper?
        if let selectedID = primarySelectedResultID {
            if let index = resultIndexByID[selectedID], results.indices.contains(index) {
                targetPaper = results[index]
            } else {
                targetPaper = nil
            }
        } else {
            targetPaper = results.first
        }

        guard let targetPaper else { return }
        onSelectPaper(targetPaper)
        isPresented = false
    }

    private var primarySelectedResultID: UUID? {
        guard !selectedResultIDs.isEmpty else { return nil }
        let ordered = selectedResultIDs
            .compactMap { id -> (UUID, Int)? in
                guard let index = resultIndexByID[id] else { return nil }
                return (id, index)
            }
            .sorted { $0.1 < $1.1 }
        return ordered.first?.0
    }

    private func saveResultsAsCollection() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let name = "Search Results \(formatter.string(from: .now))"
        store.createCollection(named: name)
        store.setCollection(name, assigned: true, forPaperIDs: results.map(\.id))
    }

    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 49, modifiers.isEmpty {
                if isTextInputFocused {
                    return event
                }
                toggleSpacePreview()
                return nil
            }
            return event
        }
    }

    private func removeLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let activeQuickLookURL, QuickLookPreviewManager.shared.isPreviewing(url: activeQuickLookURL) {
            QuickLookPreviewManager.shared.closePreview()
            self.activeQuickLookURL = nil
        }
    }

    private var isTextInputFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func toggleSpacePreview() {
        if let activeQuickLookURL, QuickLookPreviewManager.shared.isPreviewing(url: activeQuickLookURL) {
            QuickLookPreviewManager.shared.closePreview()
            self.activeQuickLookURL = nil
            return
        }

        guard let paper = selectedResultPaper else { return }
        guard let url = store.pdfURL(for: paper), FileManager.default.fileExists(atPath: url.path) else { return }
        QuickLookPreviewManager.shared.preview(url: url)
        activeQuickLookURL = url
    }

    private var selectedResultPaper: Paper? {
        if let selectedID = primarySelectedResultID,
           let index = resultIndexByID[selectedID],
           results.indices.contains(index) {
            return results[index]
        }
        return results.first
    }
}

private struct AdvancedSearchScopeOption: Hashable {
    let selection: SidebarSelection
    let label: String
}

private extension SystemLibrary {
    var englishTitle: String {
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
