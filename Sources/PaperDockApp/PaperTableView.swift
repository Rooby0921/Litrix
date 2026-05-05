import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PaperDragPayload {
    var paperIDs: [UUID]
    var fileURL: URL?
    var dragDisplayName: String?
}

@MainActor
struct PaperTableView: NSViewRepresentable {
    let papers: [Paper]
    let language: AppLanguage
    let visibleColumns: [PaperTableColumn]
    let fullColumnOrder: [PaperTableColumn]
    let columnVisibility: [PaperTableColumn: Bool]
    let columnWidths: [PaperTableColumn: CGFloat]
    let selectedPaperID: UUID?
    let selectedPaperIDs: Set<UUID>
    let translatingPaperIDs: Set<UUID>
    let contentRevision: Int
    let rowHeight: CGFloat
    let baseRowHeight: CGFloat
    let maximumRowHeightMultiplier: CGFloat
    let centerRequestNonce: UUID
    let sortColumn: PaperTableColumn?
    let sortOrder: SortOrder
    let cellContent: (Paper, PaperTableColumn) -> AnyView
    let onSelectRows: ([UUID], UUID?) -> Void
    let onDoubleClickRow: (UUID) -> Void
    let onColumnOrderChange: ([PaperTableColumn]) -> Void
    let onColumnWidthChange: (PaperTableColumn, CGFloat) -> Void
    let onSetColumnVisibility: (PaperTableColumn, Bool) -> Void
    let onSortChange: (PaperTableColumn, SortOrder) -> Void
    let onOpenColumnSettings: (PaperTableColumn) -> Void
    let onInternalDragActiveChange: (Bool) -> Void
    let onHoverCellChange: (UUID?, PaperTableColumn?) -> Void
    let dragPayload: (Paper) -> PaperDragPayload?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = context.coordinator.makeScrollView()
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            papers: papers,
            language: language,
            visibleColumns: visibleColumns,
            fullColumnOrder: fullColumnOrder,
            columnVisibility: columnVisibility,
            columnWidths: columnWidths,
            selectedPaperID: selectedPaperID,
            selectedPaperIDs: selectedPaperIDs,
            translatingPaperIDs: translatingPaperIDs,
            contentRevision: contentRevision,
            rowHeight: rowHeight,
            baseRowHeight: baseRowHeight,
            maximumRowHeightMultiplier: maximumRowHeightMultiplier,
            centerRequestNonce: centerRequestNonce,
            sortColumn: sortColumn,
            sortOrder: sortOrder,
            cellContent: cellContent,
            onSelectRows: onSelectRows,
            onDoubleClickRow: onDoubleClickRow,
            onColumnOrderChange: onColumnOrderChange,
            onColumnWidthChange: onColumnWidthChange,
            onSetColumnVisibility: onSetColumnVisibility,
            onSortChange: onSortChange,
            onOpenColumnSettings: onOpenColumnSettings,
            onInternalDragActiveChange: onInternalDragActiveChange,
            onHoverCellChange: onHoverCellChange,
            dragPayload: dragPayload
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let headerHeight: CGFloat = 26
        private let tableView = PaperNSTableView(frame: .zero)
        private var papers: [Paper] = []
        private var paperIDs: [UUID] = []
        private var language: AppLanguage = .chinese
        private var visibleColumns: [PaperTableColumn] = []
        private var fullColumnOrder: [PaperTableColumn] = PaperTableColumn.defaultOrder
        private var columnVisibility: [PaperTableColumn: Bool] = Dictionary(
            uniqueKeysWithValues: PaperTableColumn.allCases.map { ($0, true) }
        )
        private var columnWidths: [PaperTableColumn: CGFloat] = [:]
        private var selectedPaperID: UUID?
        private var selectedPaperIDs: Set<UUID> = []
        private var translatingPaperIDs: Set<UUID> = []
        private var contentRevision = 0
        private var targetRowHeight: CGFloat = 24
        private var baseRowHeight: CGFloat = 24
        private var maximumRowHeightMultiplier: CGFloat = 6
        private var lastProcessedCenterRequestNonce: UUID?
        private var sortColumn: PaperTableColumn?
        private var sortOrder: SortOrder = .reverse
        private var cellContent: ((Paper, PaperTableColumn) -> AnyView)?
        private var onSelectRows: (([UUID], UUID?) -> Void)?
        private var onDoubleClickRow: ((UUID) -> Void)?
        private var onColumnOrderChange: (([PaperTableColumn]) -> Void)?
        private var onColumnWidthChange: ((PaperTableColumn, CGFloat) -> Void)?
        private var onSetColumnVisibility: ((PaperTableColumn, Bool) -> Void)?
        private var onSortChange: ((PaperTableColumn, SortOrder) -> Void)?
        private var onOpenColumnSettings: ((PaperTableColumn) -> Void)?
        private var onInternalDragActiveChange: ((Bool) -> Void)?
        private var onHoverCellChange: ((UUID?, PaperTableColumn?) -> Void)?
        private var dragPayload: ((Paper) -> PaperDragPayload?)?
        private var isSyncingSelection = false
        private var isApplyingColumnOrder = false
        private var isApplyingSortDescriptors = false
        private weak var scrollView: NSScrollView?
        private var lastHoveredCell: (row: Int, column: Int)?

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView(frame: .zero)
            self.scrollView = scrollView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.postsBoundsChangedNotifications = true

            tableView.delegate = self
            tableView.dataSource = self
            tableView.hoverCellHandler = { [weak self] row, column in
                self?.handleHoverCellChange(row: row, column: column)
            }
            tableView.headerView = PaperTableHeaderView(
                frame: NSRect(x: 0, y: 0, width: 0, height: Self.headerHeight)
            )
            (tableView.headerView as? PaperTableHeaderView)?.columnMenuProvider = { [weak self] column in
                self?.makeColumnContextMenu(for: column)
            }
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true
            tableView.allowsColumnReordering = true
            tableView.allowsColumnResizing = true
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            tableView.usesAlternatingRowBackgroundColors = false
            tableView.usesAutomaticRowHeights = false
            // Horizontal separator lines between rows for visual clarity.
            // Custom draw in PaperAnimatedRowView.draw(_:) renders them per-row.
            tableView.gridStyleMask = .solidHorizontalGridLineMask
            tableView.gridColor = NSColor.separatorColor
            tableView.rowHeight = targetRowHeight
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            tableView.setDraggingSourceOperationMask(.copy, forLocal: true)

            scrollView.documentView = tableView
            updateHeaderFrame()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleColumnDidMoveNotification(_:)),
                name: NSTableView.columnDidMoveNotification,
                object: tableView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleColumnDidResizeNotification(_:)),
                name: NSTableView.columnDidResizeNotification,
                object: tableView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleClipViewBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            return scrollView
        }

        func update(
            papers: [Paper],
            language: AppLanguage,
            visibleColumns: [PaperTableColumn],
            fullColumnOrder: [PaperTableColumn],
            columnVisibility: [PaperTableColumn: Bool],
            columnWidths: [PaperTableColumn: CGFloat],
            selectedPaperID: UUID?,
            selectedPaperIDs: Set<UUID>,
            translatingPaperIDs: Set<UUID>,
            contentRevision: Int,
            rowHeight: CGFloat,
            baseRowHeight: CGFloat,
            maximumRowHeightMultiplier: CGFloat,
            centerRequestNonce: UUID,
            sortColumn: PaperTableColumn?,
            sortOrder: SortOrder,
            cellContent: @escaping (Paper, PaperTableColumn) -> AnyView,
            onSelectRows: @escaping ([UUID], UUID?) -> Void,
            onDoubleClickRow: @escaping (UUID) -> Void,
            onColumnOrderChange: @escaping ([PaperTableColumn]) -> Void,
            onColumnWidthChange: @escaping (PaperTableColumn, CGFloat) -> Void,
            onSetColumnVisibility: @escaping (PaperTableColumn, Bool) -> Void,
            onSortChange: @escaping (PaperTableColumn, SortOrder) -> Void,
            onOpenColumnSettings: @escaping (PaperTableColumn) -> Void,
            onInternalDragActiveChange: @escaping (Bool) -> Void,
            onHoverCellChange: @escaping (UUID?, PaperTableColumn?) -> Void,
            dragPayload: @escaping (Paper) -> PaperDragPayload?
        ) {
            let previousLanguage = self.language
            let previousContentRevision = self.contentRevision
            let previousSelectedPaperIDs = self.selectedPaperIDs
            let previousTranslatingPaperIDs = self.translatingPaperIDs
            self.language = language
            self.contentRevision = contentRevision
            self.fullColumnOrder = normalizeColumnOrder(fullColumnOrder)
            self.columnVisibility = columnVisibility
            self.columnWidths = columnWidths
            self.selectedPaperID = selectedPaperID
            self.selectedPaperIDs = selectedPaperIDs
            self.translatingPaperIDs = translatingPaperIDs
            self.baseRowHeight = max(1, baseRowHeight)
            self.maximumRowHeightMultiplier = max(1, maximumRowHeightMultiplier)
            self.sortColumn = sortColumn
            self.sortOrder = sortOrder
            self.cellContent = cellContent
            self.onSelectRows = onSelectRows
            self.onDoubleClickRow = onDoubleClickRow
            self.onColumnOrderChange = onColumnOrderChange
            self.onColumnWidthChange = onColumnWidthChange
            self.onSetColumnVisibility = onSetColumnVisibility
            self.onSortChange = onSortChange
            self.onOpenColumnSettings = onOpenColumnSettings
            self.onInternalDragActiveChange = onInternalDragActiveChange
            self.onHoverCellChange = onHoverCellChange
            self.dragPayload = dragPayload

            let previousIDs = paperIDs
            let previousColumns = self.visibleColumns
            let previousRowHeight = targetRowHeight
            let normalizedColumns = visibleColumns.isEmpty ? [self.fullColumnOrder.first ?? .title] : visibleColumns
            self.visibleColumns = normalizedColumns

            let normalizedRowHeight = clampedRowHeight(rowHeight)
            let shouldCenterSelectedRow = lastProcessedCenterRequestNonce != nil
                && lastProcessedCenterRequestNonce != centerRequestNonce

            self.papers = papers
            self.paperIDs = papers.map(\.id)

            let didColumnsChange = previousColumns != normalizedColumns
            if didColumnsChange {
                rebuildColumns()
            } else {
                updateColumnHeadersAndWidths()
            }

            applySortDescriptors()

            let didRowHeightChange = abs(previousRowHeight - normalizedRowHeight) > 0.001
            let didContentChange = previousLanguage != language
                || previousContentRevision != contentRevision
            let didSelectionContextChange = previousSelectedPaperIDs != selectedPaperIDs
            let didRowStyleChange = previousTranslatingPaperIDs != translatingPaperIDs
            if didColumnsChange
                || previousIDs != paperIDs
                || didRowHeightChange {
                tableView.reloadData()
            } else if didContentChange || didSelectionContextChange {
                refreshVisibleCellContent()
            }
            if didRowStyleChange {
                refreshVisibleRowStyles()
            }

            syncSelection()

            targetRowHeight = normalizedRowHeight
            if shouldCenterSelectedRow || didRowHeightChange {
                applyTargetRowHeight(centerPaperID: shouldCenterSelectedRow ? selectedPaperID : nil)
            } else {
                reassertTargetRowHeight()
            }

            if lastProcessedCenterRequestNonce == nil || shouldCenterSelectedRow {
                lastProcessedCenterRequestNonce = centerRequestNonce
            }
        }

        func teardown() {
            // Do NOT call SwiftUI-side callbacks here (onInternalDragActiveChange, onHoverCellChange).
            // During dismantleNSView the SwiftUI state system is already being torn down,
            // and writing @State at this point triggers an exclusivity violation → SIGABRT.
            NotificationCenter.default.removeObserver(self)
            tableView.delegate = nil
            tableView.dataSource = nil
            tableView.hoverCellHandler = nil
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            papers.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            targetRowHeight
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = (tableView.makeView(
                withIdentifier: PaperAnimatedRowView.identifier,
                owner: self
            ) as? PaperAnimatedRowView) ?? PaperAnimatedRowView()
            configure(rowView: rowView, row: row)
            return rowView
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard row >= 0,
                  row < papers.count,
                  let tableColumn,
                  let column = PaperTableColumn(rawValue: tableColumn.identifier.rawValue),
                  let cellContent else {
                return nil
            }

            let identifier = NSUserInterfaceItemIdentifier("paper-cell-\(column.rawValue)")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? PaperHostingCellView)
                ?? PaperHostingCellView(identifier: identifier)
            cell.setRootView(cellContent(papers[row], column))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection else { return }
            let selectedRows = tableView.selectedRowIndexes.compactMap { row -> UUID? in
                guard row >= 0, row < paperIDs.count else { return nil }
                return paperIDs[row]
            }
            let selectedSet = Set(selectedRows)
            let primaryID: UUID? = {
                let clickedRow = tableView.clickedRow
                if clickedRow >= 0, clickedRow < paperIDs.count {
                    let clickedID = paperIDs[clickedRow]
                    if selectedSet.contains(clickedID) {
                        return clickedID
                    }
                }
                let selectedRow = tableView.selectedRow
                guard selectedRow >= 0, selectedRow < paperIDs.count else { return nil }
                return paperIDs[selectedRow]
            }()
            onSelectRows?(selectedRows, primaryID)
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0,
                  row < papers.count,
                  let payload = dragPayload?(papers[row]) else {
                return nil
            }
            return LitrixPaperPasteboardItem(payload: payload)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            onInternalDragActiveChange?(true)
            session.draggingFormation = .list
            session.animatesToStartingPositionsOnCancelOrFail = true
            applyCustomDragPreview(to: session, rowIndexes: rowIndexes)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            onInternalDragActiveChange?(false)
        }

        func tableView(
            _ tableView: NSTableView,
            sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
        ) {
            guard !isApplyingSortDescriptors,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let column = PaperTableColumn(rawValue: key) else {
                return
            }
            onSortChange?(column, descriptor.ascending ? .forward : .reverse)
        }

        @objc
        private func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < paperIDs.count else { return }
            onDoubleClickRow?(paperIDs[row])
        }

        @objc
        private func handleColumnDidMoveNotification(_ notification: Notification) {
            guard !isApplyingColumnOrder else { return }
            let visibleOrder = currentVisibleColumnOrder()
            let merged = mergeVisibleOrder(visibleOrder, into: fullColumnOrder)
            guard merged != fullColumnOrder else { return }
            fullColumnOrder = merged
            onColumnOrderChange?(merged)
        }

        @objc
        private func handleColumnDidResizeNotification(_ notification: Notification) {
            if let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
               let column = PaperTableColumn(rawValue: tableColumn.identifier.rawValue) {
                onColumnWidthChange?(column, tableColumn.width)
                return
            }

            for tableColumn in tableView.tableColumns {
                guard let column = PaperTableColumn(rawValue: tableColumn.identifier.rawValue) else { continue }
                onColumnWidthChange?(column, tableColumn.width)
            }
        }

        @objc
        private func handleClipViewBoundsChanged(_ notification: Notification) {
            updateHeaderFrame()
        }

        private func rebuildColumns() {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            for column in visibleColumns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
                tableColumn.title = column.displayName(for: language)
                tableColumn.width = columnWidths[column] ?? column.defaultWidth
                tableColumn.minWidth = 0
                tableColumn.resizingMask = .userResizingMask
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: column.rawValue,
                    ascending: true
                )
                tableView.addTableColumn(tableColumn)
            }
            updateHeaderFrame()
        }

        private func updateColumnHeadersAndWidths() {
            for tableColumn in tableView.tableColumns {
                guard let column = PaperTableColumn(rawValue: tableColumn.identifier.rawValue) else { continue }
                tableColumn.title = column.displayName(for: language)
                let targetWidth = columnWidths[column] ?? column.defaultWidth
                if abs(tableColumn.width - targetWidth) > 0.5 {
                    tableColumn.width = targetWidth
                }
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: column.rawValue,
                    ascending: true
                )
            }
            updateHeaderFrame()
        }

        private func updateHeaderFrame() {
            if tableView.headerView == nil {
                tableView.headerView = PaperTableHeaderView(
                    frame: NSRect(x: 0, y: 0, width: 0, height: Self.headerHeight)
                )
            }
            guard let headerView = tableView.headerView else { return }

            let totalColumnWidth = tableView.tableColumns.reduce(CGFloat(0)) { partial, column in
                partial + column.width
            }
            let targetWidth = max(tableView.bounds.width, totalColumnWidth)
            let targetFrame = NSRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: Self.headerHeight
            )
            if headerView.frame != targetFrame {
                headerView.frame = targetFrame
            }
            headerView.needsDisplay = true
            tableView.enclosingScrollView?.tile()
        }

        private func applySortDescriptors() {
            isApplyingSortDescriptors = true
            defer { isApplyingSortDescriptors = false }

            guard let sortColumn else {
                tableView.sortDescriptors = []
                return
            }

            let ascending = sortOrder != .reverse
            if tableView.sortDescriptors.count != 1
                || tableView.sortDescriptors.first?.key != sortColumn.rawValue
                || tableView.sortDescriptors.first?.ascending != ascending {
                tableView.sortDescriptors = [
                    NSSortDescriptor(key: sortColumn.rawValue, ascending: ascending)
                ]
            }
        }

        private func syncSelection() {
            let indexes = IndexSet(
                paperIDs.enumerated().compactMap { index, id in
                    selectedPaperIDs.contains(id) ? index : nil
                }
            )
            guard tableView.selectedRowIndexes != indexes else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isSyncingSelection = false
        }

        private func refreshVisibleCellContent() {
            guard let cellContent else { return }
            let rowRange = tableView.rows(in: tableView.visibleRect)
            guard rowRange.location != NSNotFound, rowRange.length > 0 else { return }

            for row in rowRange.location..<(rowRange.location + rowRange.length) {
                guard row >= 0, row < papers.count else { continue }
                for columnIndex in 0..<tableView.numberOfColumns {
                    guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else { continue }
                    let tableColumn = tableView.tableColumns[columnIndex]
                    guard let column = PaperTableColumn(rawValue: tableColumn.identifier.rawValue),
                          let cell = tableView.view(
                            atColumn: columnIndex,
                            row: row,
                            makeIfNecessary: false
                    ) as? PaperHostingCellView else {
                        continue
                    }
                    cell.setRootView(cellContent(papers[row], column))
                }
            }
        }

        private func refreshVisibleRowStyles() {
            let rowRange = tableView.rows(in: tableView.visibleRect)
            guard rowRange.location != NSNotFound, rowRange.length > 0 else { return }

            for row in rowRange.location..<(rowRange.location + rowRange.length) {
                guard row >= 0, row < papers.count,
                      let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? PaperAnimatedRowView else {
                    continue
                }
                configure(rowView: rowView, row: row)
            }
        }

        private func configure(rowView: PaperAnimatedRowView, row: Int) {
            guard row >= 0, row < papers.count else {
                rowView.isTranslationActive = false
                rowView.customSelectionColor = nil
                return
            }

            rowView.isTranslationActive = translatingPaperIDs.contains(papers[row].id)
            // Selected-row cursor color: #3b3b3b at 15% opacity, i.e. 85% transparent.
            rowView.customSelectionColor = NSColor(red: 59/255, green: 59/255, blue: 59/255, alpha: 0.15)
        }

        private func dragPreviewPayload(for rowIndexes: IndexSet) -> PaperDragPayload? {
            guard let firstRow = rowIndexes.first,
                  firstRow >= 0,
                  firstRow < papers.count,
                  let payload = dragPayload?(papers[firstRow]) else {
                return nil
            }
            return payload
        }

        private func applyCustomDragPreview(to session: NSDraggingSession, rowIndexes: IndexSet) {
            guard let payload = dragPreviewPayload(for: rowIndexes) else {
                return
            }
            let title = (payload.dragDisplayName ?? payload.fileURL?.lastPathComponent ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                return
            }

            let image = DragPreviewImageFactory.make(
                title: title,
                fileURL: payload.fileURL,
                count: rowIndexes.count
            )
            session.enumerateDraggingItems(
                options: [],
                for: tableView,
                classes: [NSPasteboardItem.self],
                searchOptions: [:]
            ) { draggingItem, _, _ in
                draggingItem.imageComponentsProvider = {
                    DragPreviewImageFactory.makeComponents(
                        title: title,
                        fileURL: payload.fileURL,
                        count: rowIndexes.count
                    )
                }
                let currentFrame = draggingItem.draggingFrame
                let origin = currentFrame.origin == .zero
                    ? NSPoint(x: 12, y: 12)
                    : currentFrame.origin
                draggingItem.setDraggingFrame(
                    NSRect(origin: origin, size: image.size),
                    contents: image
                )
            }
        }

        private func handleHoverCellChange(row: Int, column: Int) {
            let normalized: (row: Int, column: Int)? = row >= 0 && column >= 0 ? (row, column) : nil
            if let normalized,
               let previous = lastHoveredCell,
               previous.row == normalized.row,
               previous.column == normalized.column {
                return
            }
            if normalized == nil, lastHoveredCell == nil {
                return
            }

            lastHoveredCell = normalized
            guard let normalized,
                  normalized.row < paperIDs.count,
                  normalized.column < tableView.tableColumns.count,
                  let columnID = PaperTableColumn(rawValue: tableView.tableColumns[normalized.column].identifier.rawValue) else {
                onHoverCellChange?(nil, nil)
                return
            }
            onHoverCellChange?(paperIDs[normalized.row], columnID)
        }

        private func applyTargetRowHeight(centerPaperID: UUID?) {
            guard !(tableView.inLiveResize || (tableView.window?.inLiveResize ?? false)) else { return }
            let centerRow = centerPaperID.flatMap { paperIDs.firstIndex(of: $0) }
            let scrollView = tableView.enclosingScrollView
            let clipView = scrollView?.contentView
            let anchorY = (clipView?.bounds.height ?? 0) / 2

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                tableView.usesAutomaticRowHeights = false
                tableView.rowHeight = targetRowHeight
                if tableView.numberOfRows > 0 {
                    tableView.noteHeightOfRows(
                        withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows)
                    )
                }
                tableView.needsLayout = true
                tableView.layoutSubtreeIfNeeded()

                guard let centerRow,
                      centerRow >= 0,
                      centerRow < tableView.numberOfRows,
                      let scrollView,
                      let clipView,
                      anchorY > 0 else {
                    return
                }

                let rowRect = tableView.rect(ofRow: centerRow)
                guard rowRect.height > 0 else { return }
                let maxY = max(0, tableView.bounds.height - clipView.bounds.height)
                let targetY = min(max(0, rowRect.midY - anchorY), maxY)
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        private func reassertTargetRowHeight() {
            guard abs(tableView.rowHeight - targetRowHeight) > 0.001 || tableView.usesAutomaticRowHeights else {
                return
            }
            tableView.usesAutomaticRowHeights = false
            tableView.rowHeight = targetRowHeight
            if tableView.numberOfRows > 0 {
                tableView.noteHeightOfRows(
                    withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows)
                )
            }
        }

        private func clampedRowHeight(_ value: CGFloat) -> CGFloat {
            let maximum = baseRowHeight * maximumRowHeightMultiplier
            return min(max(baseRowHeight, value), maximum)
        }

        private func makeColumnContextMenu(for tableColumn: NSTableColumn) -> NSMenu? {
            guard let targetColumn = PaperTableColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }

            let menu = NSMenu(title: targetColumn.displayName(for: language))
            let currentOrder = currentVisibleColumnOrder()
            let targetIndex = currentOrder.firstIndex(of: targetColumn) ?? 0

            let moveLeft = NSMenuItem(
                title: localized(chinese: "左移", english: "Move Left"),
                action: #selector(moveColumnLeft(_:)),
                keyEquivalent: ""
            )
            moveLeft.target = self
            moveLeft.representedObject = targetColumn.rawValue
            moveLeft.isEnabled = targetIndex > 0
            menu.addItem(moveLeft)

            let moveRight = NSMenuItem(
                title: localized(chinese: "右移", english: "Move Right"),
                action: #selector(moveColumnRight(_:)),
                keyEquivalent: ""
            )
            moveRight.target = self
            moveRight.representedObject = targetColumn.rawValue
            moveRight.isEnabled = targetIndex < max(0, currentOrder.count - 1)
            menu.addItem(moveRight)

            if targetColumn == .abstractText
                || targetColumn == .title
                || targetColumn == .impactFactor
                || targetColumn == .addedTime
                || targetColumn == .editedTime
                || targetColumn == .tags {
                menu.addItem(.separator())
                let settingsItem = NSMenuItem(
                    title: localized(chinese: "列设置", english: "Column Settings"),
                    action: #selector(openColumnSettings(_:)),
                    keyEquivalent: ""
                )
                settingsItem.target = self
                settingsItem.representedObject = targetColumn.rawValue
                menu.addItem(settingsItem)
            }

            menu.addItem(.separator())

            let hide = NSMenuItem(
                title: localized(chinese: "隐藏", english: "Hide"),
                action: #selector(hideColumn(_:)),
                keyEquivalent: ""
            )
            hide.target = self
            hide.representedObject = targetColumn.rawValue
            hide.isEnabled = visibleColumns.count > 1
            menu.addItem(hide)

            let hiddenColumns = normalizeColumnOrder(fullColumnOrder).filter { !(columnVisibility[$0] ?? true) }
            if !hiddenColumns.isEmpty {
                let unhide = NSMenuItem(title: localized(chinese: "取消隐藏", english: "Unhide"), action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: unhide.title)
                for column in hiddenColumns {
                    let item = NSMenuItem(
                        title: column.displayName(for: language),
                        action: #selector(unhideColumn(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = column.rawValue
                    submenu.addItem(item)
                }
                unhide.submenu = submenu
                menu.addItem(unhide)
            }

            return menu
        }

        @objc
        private func moveColumnLeft(_ sender: NSMenuItem) {
            moveColumn(sender, delta: -1)
        }

        @objc
        private func moveColumnRight(_ sender: NSMenuItem) {
            moveColumn(sender, delta: 1)
        }

        @objc
        private func openColumnSettings(_ sender: NSMenuItem) {
            guard let targetColumn = representedColumn(from: sender) else { return }
            onOpenColumnSettings?(targetColumn)
        }

        private func moveColumn(_ sender: NSMenuItem, delta: Int) {
            guard let targetColumn = representedColumn(from: sender) else { return }
            var visibleOrder = currentVisibleColumnOrder()
            guard let fromIndex = visibleOrder.firstIndex(of: targetColumn) else { return }
            let toIndex = fromIndex + delta
            guard (0..<visibleOrder.count).contains(toIndex) else { return }

            let item = visibleOrder.remove(at: fromIndex)
            visibleOrder.insert(item, at: toIndex)
            let merged = mergeVisibleOrder(visibleOrder, into: fullColumnOrder)

            if let currentIndex = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == targetColumn.rawValue }) {
                isApplyingColumnOrder = true
                tableView.moveColumn(currentIndex, toColumn: toIndex)
                isApplyingColumnOrder = false
            }

            fullColumnOrder = merged
            onColumnOrderChange?(merged)
        }

        @objc
        private func hideColumn(_ sender: NSMenuItem) {
            guard let targetColumn = representedColumn(from: sender) else { return }
            if let tableColumn = tableView.tableColumns.first(where: { $0.identifier.rawValue == targetColumn.rawValue }) {
                onColumnWidthChange?(targetColumn, tableColumn.width)
            }
            columnVisibility[targetColumn] = false
            onSetColumnVisibility?(targetColumn, false)
        }

        @objc
        private func unhideColumn(_ sender: NSMenuItem) {
            guard let targetColumn = representedColumn(from: sender) else { return }
            columnVisibility[targetColumn] = true
            onSetColumnVisibility?(targetColumn, true)
        }

        private func representedColumn(from item: NSMenuItem) -> PaperTableColumn? {
            guard let rawValue = item.representedObject as? String else { return nil }
            return PaperTableColumn(rawValue: rawValue)
        }

        private func currentVisibleColumnOrder() -> [PaperTableColumn] {
            tableView.tableColumns.compactMap { PaperTableColumn(rawValue: $0.identifier.rawValue) }
        }

        private func normalizeColumnOrder(_ order: [PaperTableColumn]) -> [PaperTableColumn] {
            var normalized: [PaperTableColumn] = []
            for column in order where !normalized.contains(column) {
                normalized.append(column)
            }
            for column in PaperTableColumn.defaultOrder where !normalized.contains(column) {
                normalized.append(column)
            }
            return normalized
        }

        private func mergeVisibleOrder(
            _ visibleOrder: [PaperTableColumn],
            into fullOrder: [PaperTableColumn]
        ) -> [PaperTableColumn] {
            var remainingVisible = visibleOrder
            var merged: [PaperTableColumn] = []

            for column in normalizeColumnOrder(fullOrder) {
                if visibleColumns.contains(column) {
                    if !remainingVisible.isEmpty {
                        merged.append(remainingVisible.removeFirst())
                    }
                } else if !merged.contains(column) {
                    merged.append(column)
                }
            }

            for column in remainingVisible where !merged.contains(column) {
                merged.append(column)
            }

            return normalizeColumnOrder(merged)
        }

        private func localized(chinese: String, english: String) -> String {
            language == .english ? english : chinese
        }
    }
}

private final class PaperAnimatedRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("paper-animated-row")

    var isTranslationActive = false {
        didSet { updateTranslationLayer() }
    }

    var customSelectionColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var isSelected: Bool {
        didSet {
            updateTranslationLayer()
            needsDisplay = true
        }
    }

    override var isEmphasized: Bool {
        didSet {
            needsDisplay = true
        }
    }

    private let translationLayer = CAGradientLayer()
    private var hasInstalledTranslationLayer = false
    private var isTranslationAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        translationLayer.frame = bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isTranslationActive = false
        customSelectionColor = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Bottom separator for every row — drawn in layer, always on top
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.cgContext.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.cgContext.setLineWidth(1.0 / max(window?.backingScaleFactor ?? 2, 1))
        ctx.cgContext.move(to: CGPoint(x: 0, y: bounds.height - 0.5))
        ctx.cgContext.addLine(to: CGPoint(x: bounds.width, y: bounds.height - 0.5))
        ctx.cgContext.strokePath()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Fixed selection highlight: previously configurable via settings, now hardcoded.
        // The NSColor already carries the alpha (18%), so we just fill the rounded rect.
        (customSelectionColor ?? NSColor(red: 220/255, green: 219/255, blue: 220/255, alpha: 0.50)).setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 3, dy: 1.5),
            xRadius: 6,
            yRadius: 6
        ).fill()
    }

    private func updateTranslationLayer() {
        ensureTranslationLayer()
        translationLayer.frame = bounds
        translationLayer.isHidden = !isTranslationActive || isSelected

        if isTranslationActive, !isSelected {
            startTranslationAnimationIfNeeded()
        } else {
            stopTranslationAnimationIfNeeded()
        }
    }

    private func ensureTranslationLayer() {
        guard !hasInstalledTranslationLayer else { return }
        wantsLayer = true
        translationLayer.colors = Self.translationPaletteA
        translationLayer.locations = [-0.1, 0.22, 0.58, 1.1]
        translationLayer.startPoint = CGPoint(x: 0, y: 0.35)
        translationLayer.endPoint = CGPoint(x: 1, y: 0.65)
        translationLayer.opacity = 1
        translationLayer.isHidden = true
        layer?.insertSublayer(translationLayer, at: 0)
        hasInstalledTranslationLayer = true
    }

    private func startTranslationAnimationIfNeeded() {
        guard !isTranslationAnimating else { return }
        isTranslationAnimating = true

        let colorAnimation = CAKeyframeAnimation(keyPath: "colors")
        colorAnimation.values = [
            Self.translationPaletteA,
            Self.translationPaletteB,
            Self.translationPaletteC,
            Self.translationPaletteA
        ]
        colorAnimation.duration = 5.6
        colorAnimation.repeatCount = .infinity
        colorAnimation.calculationMode = .linear
        colorAnimation.isRemovedOnCompletion = false

        let locationAnimation = CAKeyframeAnimation(keyPath: "locations")
        locationAnimation.values = [
            [-0.25, 0.05, 0.42, 0.95],
            [0.02, 0.32, 0.68, 1.20],
            [-0.18, 0.18, 0.56, 1.08],
            [-0.25, 0.05, 0.42, 0.95]
        ]
        locationAnimation.duration = 4.8
        locationAnimation.repeatCount = .infinity
        locationAnimation.calculationMode = .linear
        locationAnimation.isRemovedOnCompletion = false

        translationLayer.add(colorAnimation, forKey: "translation-colors")
        translationLayer.add(locationAnimation, forKey: "translation-locations")
    }

    private func stopTranslationAnimationIfNeeded() {
        guard isTranslationAnimating else { return }
        isTranslationAnimating = false
        translationLayer.removeAnimation(forKey: "translation-colors")
        translationLayer.removeAnimation(forKey: "translation-locations")
    }

    private static let translationPaletteA: [CGColor] = [
        NSColor(red: 0.58, green: 0.78, blue: 1.00, alpha: 0.22).cgColor,
        NSColor(red: 0.75, green: 0.92, blue: 0.80, alpha: 0.20).cgColor,
        NSColor(red: 1.00, green: 0.90, blue: 0.62, alpha: 0.18).cgColor,
        NSColor(red: 1.00, green: 0.72, blue: 0.90, alpha: 0.22).cgColor
    ]

    private static let translationPaletteB: [CGColor] = [
        NSColor(red: 0.78, green: 0.70, blue: 1.00, alpha: 0.22).cgColor,
        NSColor(red: 0.62, green: 0.88, blue: 1.00, alpha: 0.20).cgColor,
        NSColor(red: 0.76, green: 0.94, blue: 0.76, alpha: 0.18).cgColor,
        NSColor(red: 1.00, green: 0.84, blue: 0.70, alpha: 0.22).cgColor
    ]

    private static let translationPaletteC: [CGColor] = [
        NSColor(red: 1.00, green: 0.76, blue: 0.82, alpha: 0.22).cgColor,
        NSColor(red: 0.70, green: 0.86, blue: 1.00, alpha: 0.20).cgColor,
        NSColor(red: 0.86, green: 0.76, blue: 1.00, alpha: 0.18).cgColor,
        NSColor(red: 0.74, green: 0.92, blue: 0.82, alpha: 0.22).cgColor
    ]
}

private final class PaperNSTableView: NSTableView {
    var hoverCellHandler: ((Int, Int) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectClickedRowIfNeeded(with: event)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectClickedRowIfNeeded(with: event)
        super.rightMouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        reportHoverCell(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        reportHoverCell(for: event)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hoverCellHandler?(-1, -1)
        super.mouseExited(with: event)
    }

    private func selectClickedRowIfNeeded(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return }

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
            return
        }

        if !selectedRowIndexes.contains(row) || selectedRowIndexes.count != 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        rowView(atRow: row, makeIfNecessary: false)?.needsDisplay = true
        displayIfNeeded()
    }

    private func reportHoverCell(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoverCellHandler?(row(at: point), column(at: point))
    }

}

private enum DragPreviewImageFactory {
    static func make(title: String, fileURL: URL?, count: Int) -> NSImage {
        let displayTitle = title.count > 80 ? String(title.prefix(80)) + "…" : title
        let badgeText = count > 1 ? "\(count)" : nil
        let icon = previewIcon(for: fileURL)
        let iconSize = NSSize(width: 32, height: 32)
        icon.size = iconSize

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let titleSize = (displayTitle as NSString).size(withAttributes: titleAttributes)
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let badgeSize = badgeText.map { ($0 as NSString).size(withAttributes: badgeAttributes) } ?? .zero

        let padding = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let textSpacing: CGFloat = 8
        let badgeSpacing: CGFloat = badgeText == nil ? 0 : 8
        let badgeDiameter: CGFloat = badgeText == nil ? 0 : max(18, badgeSize.width + 8)
        let width = min(420, padding.left + iconSize.width + textSpacing + titleSize.width + badgeSpacing + badgeDiameter + padding.right)
        let height = max(36, padding.top + max(iconSize.height, titleSize.height, badgeDiameter) + padding.bottom)
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(origin: .zero, size: image.size)
        NSColor.clear.setFill()
        bounds.fill()

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.set()

        let iconRect = NSRect(x: padding.left, y: (height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        icon.draw(in: iconRect)

        NSGraphicsContext.current?.saveGraphicsState()
        NSShadow().set()
        let titleOrigin = NSPoint(x: iconRect.maxX + textSpacing, y: (height - titleSize.height) / 2)
        (displayTitle as NSString).draw(at: titleOrigin, withAttributes: titleAttributes)

        if let badgeText {
            let badgeRect = NSRect(
                x: min(width - padding.right - badgeDiameter, titleOrigin.x + titleSize.width + badgeSpacing),
                y: (height - badgeDiameter) / 2,
                width: badgeDiameter,
                height: badgeDiameter
            )
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            let badgeOrigin = NSPoint(
                x: badgeRect.midX - badgeSize.width / 2,
                y: badgeRect.midY - badgeSize.height / 2
            )
            (badgeText as NSString).draw(at: badgeOrigin, withAttributes: badgeAttributes)
        }
        NSGraphicsContext.current?.restoreGraphicsState()

        return image
    }

    static func makeComponents(title: String, fileURL: URL?, count: Int) -> [NSDraggingImageComponent] {
        let image = make(title: title, fileURL: fileURL, count: count)
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = image
        component.frame = NSRect(origin: .zero, size: image.size)
        return [component]
    }

    private static func previewIcon(for fileURL: URL?) -> NSImage {
        if let fileURL {
            return NSWorkspace.shared.icon(forFile: fileURL.path)
        }
        return NSWorkspace.shared.icon(for: .pdf)
    }
}

private final class LitrixPaperPasteboardItem: NSObject, NSPasteboardWriting {
    private static let paperIDsType = NSPasteboard.PasteboardType("com.rooby.litrix.paper-ids")
    private let payload: PaperDragPayload

    init(payload: PaperDragPayload) {
        self.payload = payload
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [Self.paperIDsType]
        if payload.fileURL != nil {
            types.append(.fileURL)
        }
        types.append(.string)
        return types
    }

    func pasteboardPropertyList(
        forType type: NSPasteboard.PasteboardType
    ) -> Any? {
        if type == Self.paperIDsType {
            return payload.paperIDs.map(\.uuidString).joined(separator: "\n")
        }
        if type == .fileURL, let fileURL = payload.fileURL {
            return fileURL.absoluteString
        }
        if type == .string {
            return payload.paperIDs.map(\.uuidString).joined(separator: "\n")
        }
        return nil
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / CGFloat(255)
        let green = CGFloat((value >> 8) & 0xFF) / CGFloat(255)
        let blue = CGFloat(value & 0xFF) / CGFloat(255)
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}

private final class PaperHostingCellView: NSTableCellView {
    private let hostingView = PaperEventForwardingHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        // Prevent AppKit from auto-toggling text color to white on selection;
        // we manage text appearance ourselves through the custom selection rect.
        get { .normal }
        set { }
    }

    func setRootView(_ view: AnyView) {
        hostingView.rootView = view
    }
}

private final class PaperEventForwardingHostingView: NSHostingView<AnyView> {
    override func mouseDown(with event: NSEvent) {
        guard let tableView = enclosingPaperTableView else {
            super.mouseDown(with: event)
            return
        }
        tableView.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if let tableView = enclosingPaperTableView {
            tableView.mouseMoved(with: event)
            return
        }
        super.mouseMoved(with: event)
    }

    private var enclosingPaperTableView: PaperNSTableView? {
        var current: NSView? = superview
        while let view = current {
            if let tableView = view as? PaperNSTableView {
                return tableView
            }
            current = view.superview
        }
        return nil
    }
}

private final class PaperTableHeaderView: NSTableHeaderView {
    var columnMenuProvider: ((NSTableColumn) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tableView else { return super.menu(for: event) }
        let location = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: location)
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            return super.menu(for: event)
        }
        return columnMenuProvider?(tableView.tableColumns[columnIndex]) ?? super.menu(for: event)
    }
}
