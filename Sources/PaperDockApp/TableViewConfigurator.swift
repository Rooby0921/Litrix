import AppKit
import SwiftUI

@MainActor
struct TableViewConfigurator: NSViewRepresentable {
    let language: AppLanguage
    let columnVisibility: [PaperTableColumn: Bool]
    let columnWidths: [PaperTableColumn: CGFloat]
    let rowIDs: [UUID]
    let desiredColumnOrder: [PaperTableColumn]
    let deterministicRowHeight: CGFloat
    let centerRowID: UUID?
    let centerRequestNonce: UUID
    let reassertRequestNonce: UUID
    let onSelectRows: ([UUID], UUID?) -> Void
    let onDoubleClickRow: (UUID) -> Void
    let onColumnOrderChange: ([PaperTableColumn]) -> Void
    let onColumnWidthChange: (PaperTableColumn, CGFloat) -> Void
    let onSetColumnVisibility: (PaperTableColumn, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = TableConfigurationHostView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.updateCallbacks(
            columnVisibility: columnVisibility,
            columnWidths: columnWidths,
            language: language,
            rowIDs: rowIDs,
            desiredColumnOrder: desiredColumnOrder,
            deterministicRowHeight: deterministicRowHeight,
            centerRowID: centerRowID,
            centerRequestNonce: centerRequestNonce,
            reassertRequestNonce: reassertRequestNonce,
            onSelectRows: onSelectRows,
            onDoubleClickRow: onDoubleClickRow,
            onColumnOrderChange: onColumnOrderChange,
            onColumnWidthChange: onColumnWidthChange,
            onSetColumnVisibility: onSetColumnVisibility
        )
        context.coordinator.attachTableViewIfNeeded(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateCallbacks(
            columnVisibility: columnVisibility,
            columnWidths: columnWidths,
            language: language,
            rowIDs: rowIDs,
            desiredColumnOrder: desiredColumnOrder,
            deterministicRowHeight: deterministicRowHeight,
            centerRowID: centerRowID,
            centerRequestNonce: centerRequestNonce,
            reassertRequestNonce: reassertRequestNonce,
            onSelectRows: onSelectRows,
            onDoubleClickRow: onDoubleClickRow,
            onColumnOrderChange: onColumnOrderChange,
            onColumnWidthChange: onColumnWidthChange,
            onSetColumnVisibility: onSetColumnVisibility
        )
        context.coordinator.attachTableViewIfNeeded(from: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let hostView = nsView as? TableConfigurationHostView {
            hostView.coordinator = nil
        }
        coordinator.teardown()
    }

    @MainActor
    private final class TableConfigurationHostView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attachTableViewIfNeeded(from: self)
            coordinator?.scheduleRowHeightReassertion()
        }

        override func layout() {
            super.layout()
            coordinator?.attachTableViewIfNeeded(from: self)
            coordinator?.reassertTargetRowHeightWithoutScrolling()
        }

        override func viewWillDraw() {
            super.viewWillDraw()
            coordinator?.reassertTargetRowHeightWithoutScrolling()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var hostView: NSView?
        private weak var tableView: NSTableView?
        private var columnVisibility: [PaperTableColumn: Bool] = Dictionary(
            uniqueKeysWithValues: PaperTableColumn.allCases.map { ($0, true) }
        )
        private var language: AppLanguage = .chinese
        private var columnWidths: [PaperTableColumn: CGFloat] = Dictionary(
            uniqueKeysWithValues: PaperTableColumn.allCases.map { ($0, $0.defaultWidth) }
        )
        private var rowIDs: [UUID] = []
        private var desiredColumnOrder: [PaperTableColumn] = PaperTableColumn.defaultOrder
        private var onSelectRows: (([UUID], UUID?) -> Void)?
        private var onDoubleClickRow: ((UUID) -> Void)?
        private var onColumnOrderChange: (([PaperTableColumn]) -> Void)?
        private var onColumnWidthChange: ((PaperTableColumn, CGFloat) -> Void)?
        private var onSetColumnVisibility: ((PaperTableColumn, Bool) -> Void)?
        private var deterministicRowHeight: CGFloat = 24
        private var centerRowID: UUID?
        private var centerRequestNonce = UUID()
        private var lastProcessedCenterRequestNonce: UUID?
        private var reassertRequestNonce = UUID()
        private var lastProcessedReassertRequestNonce: UUID?
        private var selectionDidChangeObserver: NSObjectProtocol?
        private var clipViewBoundsObserver: NSObjectProtocol?
        private weak var observedClipView: NSClipView?
        private var isApplyingColumnOrder = false
        private var isApplyingColumnWidths = false
        private var shouldApplyDesiredColumnOrder = true
        private var shouldApplyDesiredColumnWidths = true
        private var pendingAttachRetry = false
        private var unhidePopover: NSPopover?
        private var rowHeightReassertionGeneration = 0
        private var rowHeightWatchdogTask: Task<Void, Never>?

        func updateCallbacks(
            columnVisibility: [PaperTableColumn: Bool],
            columnWidths: [PaperTableColumn: CGFloat],
            language: AppLanguage,
            rowIDs: [UUID],
            desiredColumnOrder: [PaperTableColumn],
            deterministicRowHeight: CGFloat,
            centerRowID: UUID?,
            centerRequestNonce: UUID,
            reassertRequestNonce: UUID,
            onSelectRows: @escaping ([UUID], UUID?) -> Void,
            onDoubleClickRow: @escaping (UUID) -> Void,
            onColumnOrderChange: @escaping ([PaperTableColumn]) -> Void,
            onColumnWidthChange: @escaping (PaperTableColumn, CGFloat) -> Void,
            onSetColumnVisibility: @escaping (PaperTableColumn, Bool) -> Void
        ) {
            self.columnVisibility = columnVisibility
            self.language = language
            self.rowIDs = rowIDs
            if self.columnWidths != columnWidths {
                self.columnWidths = columnWidths
                shouldApplyDesiredColumnWidths = true
            }
            let normalizedOrder = normalizeColumnOrder(desiredColumnOrder)
            if self.desiredColumnOrder != normalizedOrder {
                self.desiredColumnOrder = normalizedOrder
                shouldApplyDesiredColumnOrder = true
            }

            let normalizedRowHeight = max(24, deterministicRowHeight)
            let didRowHeightChange = abs(self.deterministicRowHeight - normalizedRowHeight) > 0.001
            let shouldHandleReassertRequest: Bool
            if lastProcessedReassertRequestNonce == nil {
                lastProcessedReassertRequestNonce = reassertRequestNonce
                shouldHandleReassertRequest = false
            } else {
                shouldHandleReassertRequest = self.reassertRequestNonce != reassertRequestNonce
                if shouldHandleReassertRequest {
                    lastProcessedReassertRequestNonce = reassertRequestNonce
                }
            }
            self.deterministicRowHeight = normalizedRowHeight
            self.centerRowID = centerRowID
            self.centerRequestNonce = centerRequestNonce
            self.reassertRequestNonce = reassertRequestNonce
            if didRowHeightChange {
                applyTargetRowHeight(preserveScroll: true)
                scheduleRowHeightReassertion()
            } else if shouldHandleReassertRequest {
                scheduleRowHeightReassertion()
            } else {
                reassertTargetRowHeightWithoutScrolling()
            }
            if lastProcessedCenterRequestNonce == nil {
                lastProcessedCenterRequestNonce = centerRequestNonce
            } else {
                scheduleCenterRequestedRowIfNeeded()
            }

            self.onSelectRows = onSelectRows
            self.onDoubleClickRow = onDoubleClickRow
            self.onColumnOrderChange = onColumnOrderChange
            self.onColumnWidthChange = onColumnWidthChange
            self.onSetColumnVisibility = onSetColumnVisibility
        }

        func attachTableViewIfNeeded(from view: NSView) {
            hostView = view
            startRowHeightWatchdogIfNeeded()
            let found = findTableView(near: view)

            guard let found else {
                scheduleDeferredAttach(from: view)
                return
            }

            // macOS 26 regression: _NSScrollingConcurrentMainThreadSynchronizer fires a
            // VBL callback before SwiftUI has populated the table's columns.  When that
            // happens SwiftUITableRowView._separatorRect calls viewAtColumn:0 on a table
            // with _columnCount == 0, which triggers a fatal assertion.  Wait until
            // SwiftUI has added at least one column before configuring the table.
            guard found.numberOfColumns > 0 else {
                scheduleDeferredAttach(from: view)
                return
            }

            pendingAttachRetry = false

            let isNewTable = tableView !== found
            if isNewTable {
                removeSelectionDidChangeObserver()
                removeClipViewBoundsObserver()
            }
            tableView = found

            if isNewTable {
                configureTableView(found)
                shouldApplyDesiredColumnOrder = true
                shouldApplyDesiredColumnWidths = true
            }

            if shouldApplyDesiredColumnOrder {
                applyDesiredColumnOrderIfNeeded()
            }

            if shouldApplyDesiredColumnWidths {
                applyDesiredColumnWidthsIfNeeded()
            }

            // Avoid high-frequency state sync on every representable update.
            // Column move/resize notifications already persist the latest values.
            if isNewTable {
                syncCurrentColumnStateToSettings()
            }

            installClipViewBoundsObserverIfNeeded(for: found)
            reassertTargetRowHeightWithoutScrolling(for: found)
        }

        func teardown() {
            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidMoveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: nil)
            removeSelectionDidChangeObserver()
            removeClipViewBoundsObserver()
            rowHeightWatchdogTask?.cancel()
            rowHeightWatchdogTask = nil
            unhidePopover?.performClose(nil)
            unhidePopover = nil
            hostView = nil
            tableView = nil
        }

        private func configureTableView(_ tableView: NSTableView) {
            tableView.allowsColumnReordering = true
            tableView.allowsColumnResizing = true
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            tableView.setDraggingSourceOperationMask(.copy, forLocal: true)

            for tableColumn in tableView.tableColumns {
                guard let mapped = PaperTableColumn.fromTableHeaderTitle(tableColumn.title) else { continue }
                tableColumn.identifier = NSUserInterfaceItemIdentifier(mapped.rawValue)
            }

            if let headerView = tableView.headerView as? ColumnHeaderMenuHeaderView {
                headerView.columnMenuProvider = { [weak self] tableColumn in
                    self?.makeColumnContextMenu(for: tableColumn)
                }
            } else {
                let headerView = ColumnHeaderMenuHeaderView(frame: tableView.headerView?.frame ?? .zero)
                headerView.columnMenuProvider = { [weak self] tableColumn in
                    self?.makeColumnContextMenu(for: tableColumn)
                }
                tableView.headerView = headerView
            }

            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidMoveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: nil)
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

            installSelectionDidChangeObserver(for: tableView)
            reassertTargetRowHeightWithoutScrolling(for: tableView)

            // Solid horizontal grid lines between rows, matching the NSTableView setup.
            tableView.gridStyleMask = .solidHorizontalGridLineMask
            tableView.gridColor = NSColor.separatorColor
        }

        func reassertTargetRowHeightWithoutScrolling() {
            guard let tableView else { return }
            reassertTargetRowHeightWithoutScrolling(for: tableView)
        }

        func scheduleRowHeightReassertion() {
            rowHeightReassertionGeneration += 1
            let generation = rowHeightReassertionGeneration
            let delays: [DispatchTimeInterval] = [
                .milliseconds(0),
                .milliseconds(16),
                .milliseconds(80),
                .milliseconds(250),
                .milliseconds(1000)
            ]

            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.rowHeightReassertionGeneration == generation else { return }
                    self.reassertTargetRowHeightWithoutScrolling()
                }
            }
        }

        private func reassertTargetRowHeightWithoutScrolling(for tableView: NSTableView) {
            applyTargetRowHeight(for: tableView, preserveScroll: false)
        }

        private func applyTargetRowHeight(preserveScroll: Bool) {
            guard let tableView else { return }
            applyTargetRowHeight(for: tableView, preserveScroll: preserveScroll)
        }

        private func applyTargetRowHeight(for tableView: NSTableView, preserveScroll: Bool) {
            let didDisableAutomaticRowHeights = tableView.usesAutomaticRowHeights
            if tableView.usesAutomaticRowHeights {
                tableView.usesAutomaticRowHeights = false
            }

            let targetRowHeight = max(24, min(320, deterministicRowHeight))
            let oldRowHeight = tableView.rowHeight
            guard abs(oldRowHeight - targetRowHeight) > 0.001 || didDisableAutomaticRowHeights else { return }
            guard !(tableView.inLiveResize || (tableView.window?.inLiveResize ?? false)) else { return }

            guard preserveScroll else {
                tableView.rowHeight = targetRowHeight
                tableView.needsLayout = true
                return
            }

            // Preserve scroll position anchored on selected row (if visible) or topmost visible row
            let scrollView = tableView.enclosingScrollView
            let clipView = scrollView?.contentView
            let oldScrollOriginY = clipView?.bounds.origin.y ?? 0
            let visibleRect = tableView.visibleRect
            let selectedRow = tableView.selectedRow

            let anchorRow: Int
            if selectedRow >= 0 && oldRowHeight > 0 && visibleRect.height > 0 {
                let selTop = CGFloat(selectedRow) * oldRowHeight
                let isVisible = selTop < (oldScrollOriginY + visibleRect.height) && (selTop + oldRowHeight) > oldScrollOriginY
                anchorRow = isVisible ? selectedRow : max(0, tableView.row(at: NSPoint(x: 0, y: visibleRect.minY + 1)))
            } else {
                anchorRow = max(0, tableView.row(at: NSPoint(x: 0, y: visibleRect.minY + 1)))
            }
            let anchorOffset = oldRowHeight > 0 ? CGFloat(anchorRow) * oldRowHeight - oldScrollOriginY : 0

            tableView.rowHeight = targetRowHeight
            tableView.needsLayout = true

            if let clipView, anchorRow >= 0 && oldRowHeight > 0 {
                let newScrollOriginY = CGFloat(anchorRow) * targetRowHeight - anchorOffset
                clipView.scroll(to: NSPoint(x: 0, y: max(0, newScrollOriginY)))
                scrollView?.reflectScrolledClipView(clipView)
            }
        }

        private func scheduleCenterRequestedRowIfNeeded() {
            guard centerRequestNonce != lastProcessedCenterRequestNonce else { return }
            guard centerRowID != nil else {
                lastProcessedCenterRequestNonce = centerRequestNonce
                return
            }
            centerRequestedRowIfPossible(nonce: centerRequestNonce, retriesRemaining: 4)
        }

        private func centerRequestedRowIfPossible(nonce: UUID, retriesRemaining: Int) {
            guard nonce == centerRequestNonce,
                  nonce != lastProcessedCenterRequestNonce else {
                return
            }

            guard let tableView else {
                retryCenterRequestedRowIfNeeded(nonce: nonce, retriesRemaining: retriesRemaining)
                return
            }

            guard let centerRowID,
                  let row = rowIDs.firstIndex(of: centerRowID),
                  row >= 0,
                  row < tableView.numberOfRows else {
                lastProcessedCenterRequestNonce = nonce
                return
            }

            reassertTargetRowHeightWithoutScrolling(for: tableView)
            tableView.layoutSubtreeIfNeeded()
            guard let scrollView = tableView.enclosingScrollView else {
                tableView.scrollRowToVisible(row)
                lastProcessedCenterRequestNonce = nonce
                return
            }

            let rowRect = tableView.rect(ofRow: row)
            let clipView = scrollView.contentView
            let visibleHeight = clipView.bounds.height
            let fullHeight = tableView.bounds.height

            guard rowRect.height > 0, visibleHeight > 0, fullHeight > 0 else {
                retryCenterRequestedRowIfNeeded(nonce: nonce, retriesRemaining: retriesRemaining)
                return
            }

            var targetY = rowRect.midY - (visibleHeight / 2)
            let maxY = max(0, fullHeight - visibleHeight)
            targetY = min(max(0, targetY), maxY)

            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
            lastProcessedCenterRequestNonce = nonce
        }

        private func retryCenterRequestedRowIfNeeded(nonce: UUID, retriesRemaining: Int) {
            guard retriesRemaining > 0 else {
                if nonce == centerRequestNonce {
                    lastProcessedCenterRequestNonce = nonce
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(32)) { [weak self] in
                self?.centerRequestedRowIfPossible(nonce: nonce, retriesRemaining: retriesRemaining - 1)
            }
        }

        @objc
        private func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rowIDs.count else { return }
            onDoubleClickRow?(rowIDs[row])
        }

        @objc
        private func handleColumnDidMoveNotification(_ notification: Notification) {
            handleColumnDidMove()
        }

        @objc
        private func handleColumnDidResizeNotification(_ notification: Notification) {
            if let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn {
                handleColumnDidResize(
                    identifier: tableColumn.identifier.rawValue,
                    title: tableColumn.title,
                    width: tableColumn.width
                )
                return
            }

            guard let tableView else { return }
            for tableColumn in tableView.tableColumns {
                handleColumnDidResize(
                    identifier: tableColumn.identifier.rawValue,
                    title: tableColumn.title,
                    width: tableColumn.width
                )
            }
        }

        private func handleColumnDidMove() {
            guard !isApplyingColumnOrder else { return }

            guard let tableView,
                  let visibleOrder = currentMappedColumnOrder(for: tableView) else {
                return
            }

            let currentOrder = mergeVisibleOrder(visibleOrder, into: desiredColumnOrder)
            guard currentOrder != desiredColumnOrder else { return }
            desiredColumnOrder = currentOrder
            onColumnOrderChange?(currentOrder)
        }

        private func handleColumnDidResize(identifier: String, title: String, width: CGFloat) {
            guard !isApplyingColumnWidths,
                  let mappedColumn = PaperTableColumn(rawValue: identifier)
                    ?? PaperTableColumn.fromTableHeaderTitle(identifier)
                    ?? PaperTableColumn.fromTableHeaderTitle(title) else {
                return
            }

            onColumnWidthChange?(mappedColumn, width)
        }

        private func applyDesiredColumnWidthsIfNeeded() {
            guard let tableView else { return }

            isApplyingColumnWidths = true
            defer {
                isApplyingColumnWidths = false
                shouldApplyDesiredColumnWidths = false
            }

            for tableColumn in tableView.tableColumns {
                guard let mappedColumn = mapColumn(tableColumn) else { continue }
                let targetWidth = max(36, columnWidths[mappedColumn] ?? mappedColumn.defaultWidth)
                guard abs(tableColumn.width - targetWidth) > 0.5 else { continue }
                tableColumn.width = targetWidth
            }
        }

        private func applyDesiredColumnOrderIfNeeded() {
            guard let tableView else { return }

            let targetVisibleOrder = normalizedVisibleColumnOrder()
            guard !targetVisibleOrder.isEmpty else {
                shouldApplyDesiredColumnOrder = false
                return
            }

            let currentOrder = tableView.tableColumns.compactMap { mapColumn($0) }
            guard currentOrder != targetVisibleOrder else {
                shouldApplyDesiredColumnOrder = false
                return
            }

            isApplyingColumnOrder = true
            defer {
                isApplyingColumnOrder = false
                shouldApplyDesiredColumnOrder = false
            }

            for targetIndex in targetVisibleOrder.indices {
                let targetColumn = targetVisibleOrder[targetIndex]
                guard let currentIndex = tableView.tableColumns.firstIndex(where: { mapColumn($0) == targetColumn }) else {
                    continue
                }

                if currentIndex != targetIndex {
                    tableView.moveColumn(currentIndex, toColumn: targetIndex)
                }
            }
        }

        private func mapColumn(_ tableColumn: NSTableColumn) -> PaperTableColumn? {
            let identifier = tableColumn.identifier.rawValue
            if let byIdentifier = PaperTableColumn(rawValue: identifier)
                ?? PaperTableColumn.fromTableHeaderTitle(identifier) {
                return byIdentifier
            }
            return PaperTableColumn.fromTableHeaderTitle(tableColumn.title)
        }

        private func makeColumnContextMenu(for tableColumn: NSTableColumn) -> NSMenu? {
            guard let targetColumn = mapColumn(tableColumn) else { return nil }

            let menu = NSMenu(title: targetColumn.displayName(for: language))
            let currentOrder = normalizedVisibleColumnOrder()
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

            menu.addItem(.separator())

            let hide = NSMenuItem(
                title: localized(chinese: "隐藏", english: "Hide"),
                action: #selector(hideColumn(_:)),
                keyEquivalent: ""
            )
            hide.target = self
            hide.representedObject = targetColumn.rawValue
            let visibleCount = columnVisibility.values.filter { $0 }.count
            hide.isEnabled = (columnVisibility[targetColumn] ?? true) && visibleCount > 1
            menu.addItem(hide)

            let showHidden = NSMenuItem(
                title: localized(chinese: "取消隐藏…", english: "Unhide…"),
                action: #selector(presentUnhidePopover(_:)),
                keyEquivalent: ""
            )
            let hiddenColumns = normalizeColumnOrder(desiredColumnOrder).filter { !(columnVisibility[$0] ?? true) }
            showHidden.target = self
            showHidden.representedObject = hiddenColumns.map(\.rawValue)
            showHidden.isEnabled = !hiddenColumns.isEmpty
            menu.addItem(showHidden)

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

        private func moveColumn(_ sender: NSMenuItem, delta: Int) {
            guard delta != 0,
                  let targetColumn = representedColumn(from: sender) else {
                return
            }

            let visibleOrder = normalizedVisibleColumnOrder()
            guard let fromIndex = visibleOrder.firstIndex(of: targetColumn) else { return }

            let toIndex = fromIndex + delta
            guard (0..<visibleOrder.count).contains(toIndex) else { return }

            var newVisibleOrder = visibleOrder
            let item = newVisibleOrder.remove(at: fromIndex)
            newVisibleOrder.insert(item, at: toIndex)

            let fullOrder = mergeVisibleOrder(newVisibleOrder, into: desiredColumnOrder)
            guard fullOrder != desiredColumnOrder else { return }

            if let tableView,
               let currentIndex = tableView.tableColumns.firstIndex(where: { mapColumn($0) == targetColumn }) {
                isApplyingColumnOrder = true
                tableView.moveColumn(currentIndex, toColumn: toIndex)
                isApplyingColumnOrder = false
            }

            desiredColumnOrder = fullOrder
            onColumnOrderChange?(fullOrder)
        }

        @objc
        private func hideColumn(_ sender: NSMenuItem) {
            guard let targetColumn = representedColumn(from: sender) else { return }

            if let tableView,
               let tableColumn = tableView.tableColumns.first(where: { mapColumn($0) == targetColumn }) {
                onColumnWidthChange?(targetColumn, tableColumn.width)
            }

            columnVisibility[targetColumn] = false
            onSetColumnVisibility?(targetColumn, false)
            shouldApplyDesiredColumnOrder = true
            if let tableView {
                DispatchQueue.main.async { [weak self, weak tableView] in
                    guard let self, let tableView, self.tableView === tableView else { return }
                    self.applyDesiredColumnOrderIfNeeded()
                }
            }
        }

        @objc
        private func presentUnhidePopover(_ sender: NSMenuItem) {
            let hiddenColumns: [PaperTableColumn]
            if let rawValues = sender.representedObject as? [String] {
                hiddenColumns = rawValues.compactMap { PaperTableColumn(rawValue: $0) }
            } else {
                hiddenColumns = normalizeColumnOrder(desiredColumnOrder).filter { !(columnVisibility[$0] ?? true) }
            }
            guard !hiddenColumns.isEmpty else { return }
            showUnhidePopover(hiddenColumns)
        }

        private func showUnhidePopover(_ hiddenColumns: [PaperTableColumn]) {
            guard let tableView,
                  let window = tableView.window,
                  let contentView = window.contentView else {
                return
            }

            unhidePopover?.performClose(nil)

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = NSHostingController(
                rootView: UnhideColumnsPopoverContent(
                    language: language,
                    columns: hiddenColumns,
                    onApply: { [weak self] selected in
                        guard let self else { return }
                        for column in selected {
                            self.setColumnVisibility(column, isVisible: true)
                        }
                        self.unhidePopover?.performClose(nil)
                    }
                )
            )

            let mousePoint = window.mouseLocationOutsideOfEventStream
            let pointInContent = contentView.convert(mousePoint, from: nil)
            let anchorRect = NSRect(x: pointInContent.x, y: pointInContent.y, width: 1, height: 1)
            popover.show(relativeTo: anchorRect, of: contentView, preferredEdge: .maxX)
            unhidePopover = popover
        }

        private func setColumnVisibility(_ column: PaperTableColumn, isVisible: Bool) {
            columnVisibility[column] = isVisible
            onSetColumnVisibility?(column, isVisible)
            if isVisible {
                shouldApplyDesiredColumnOrder = true
            }
        }

        private func representedColumn(from menuItem: NSMenuItem) -> PaperTableColumn? {
            guard let rawValue = menuItem.representedObject as? String else { return nil }
            return PaperTableColumn(rawValue: rawValue)
        }

        private func currentMappedColumnOrder(for tableView: NSTableView) -> [PaperTableColumn]? {
            let mapped = tableView.tableColumns.compactMap { mapColumn($0) }
            return mapped.isEmpty ? nil : mapped
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

        private func normalizedVisibleColumnOrder() -> [PaperTableColumn] {
            normalizeColumnOrder(desiredColumnOrder).filter { columnVisibility[$0] ?? true }
        }

        private func localized(chinese: String, english: String) -> String {
            language == .english ? english : chinese
        }

        private func mergeVisibleOrder(_ visibleOrder: [PaperTableColumn], into fullOrder: [PaperTableColumn]) -> [PaperTableColumn] {
            let normalizedFullOrder = normalizeColumnOrder(fullOrder)
            var remainingVisible = visibleOrder
            var merged: [PaperTableColumn] = []

            for column in normalizedFullOrder {
                if columnVisibility[column] ?? true {
                    if let nextVisible = remainingVisible.first {
                        merged.append(nextVisible)
                        remainingVisible.removeFirst()
                    }
                } else {
                    merged.append(column)
                }
            }

            for column in remainingVisible where !merged.contains(column) {
                merged.append(column)
            }

            return normalizeColumnOrder(merged)
        }

        private func syncCurrentColumnStateToSettings() {
            guard let tableView else { return }

            if let mappedOrder = currentMappedColumnOrder(for: tableView) {
                let mergedOrder = mergeVisibleOrder(mappedOrder, into: desiredColumnOrder)
                if mergedOrder != desiredColumnOrder {
                    desiredColumnOrder = mergedOrder
                    onColumnOrderChange?(mergedOrder)
                }
            }

            for tableColumn in tableView.tableColumns {
                guard let mapped = mapColumn(tableColumn) else { continue }
                onColumnWidthChange?(mapped, tableColumn.width)
            }
        }

        private func installSelectionDidChangeObserver(for tableView: NSTableView) {
            removeSelectionDidChangeObserver()
            selectionDidChangeObserver = NotificationCenter.default.addObserver(
                forName: NSTableView.selectionDidChangeNotification,
                object: tableView,
                queue: .main
            ) { [weak self] notification in
                guard let sender = notification.object as? NSTableView else { return }
                MainActor.assumeIsolated {
                    guard let self, self.tableView === sender else { return }
                    self.handleSelectionDidChange(sender)
                }
            }
        }

        private func removeSelectionDidChangeObserver() {
            if let selectionDidChangeObserver {
                NotificationCenter.default.removeObserver(selectionDidChangeObserver)
                self.selectionDidChangeObserver = nil
            }
        }

        private func installClipViewBoundsObserverIfNeeded(for tableView: NSTableView) {
            guard let clipView = tableView.enclosingScrollView?.contentView else {
                removeClipViewBoundsObserver()
                return
            }
            guard observedClipView !== clipView else { return }

            removeClipViewBoundsObserver()
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            clipViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak tableView] _ in
                MainActor.assumeIsolated {
                    guard let self,
                          let tableView,
                          self.tableView === tableView else {
                        return
                    }
                    self.reassertTargetRowHeightWithoutScrolling(for: tableView)
                }
            }
        }

        private func removeClipViewBoundsObserver() {
            if let clipViewBoundsObserver {
                NotificationCenter.default.removeObserver(clipViewBoundsObserver)
                self.clipViewBoundsObserver = nil
            }
            observedClipView = nil
        }

        private func startRowHeightWatchdogIfNeeded() {
            guard rowHeightWatchdogTask == nil else { return }
            rowHeightWatchdogTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.reassertAttachedTableRowHeight()
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
        }

        private func reassertAttachedTableRowHeight() {
            if let hostView,
               let found = findTableView(near: hostView),
               found.numberOfColumns > 0,
               found !== tableView {
                attachTableViewIfNeeded(from: hostView)
                return
            }

            if let tableView,
               tableView.superview != nil,
               tableView.numberOfColumns > 0 {
                installClipViewBoundsObserverIfNeeded(for: tableView)
                reassertTargetRowHeightWithoutScrolling(for: tableView)
                return
            }

            guard let hostView else { return }
            attachTableViewIfNeeded(from: hostView)
        }

        private func handleSelectionDidChange(_ sender: NSTableView) {
            let selectedRows = sender.selectedRowIndexes.compactMap { index -> UUID? in
                guard index >= 0, index < rowIDs.count else { return nil }
                return rowIDs[index]
            }

            let selectedRowIDSet = Set(selectedRows)

            let primaryID: UUID? = {
                let clickedRow = sender.clickedRow
                if clickedRow >= 0, clickedRow < rowIDs.count {
                    let clickedRowID = rowIDs[clickedRow]
                    if selectedRowIDSet.contains(clickedRowID) {
                        return clickedRowID
                    }
                }

                let selectedRow = sender.selectedRow
                guard selectedRow >= 0, selectedRow < rowIDs.count else { return nil }
                return rowIDs[selectedRow]
            }()
            onSelectRows?(selectedRows, primaryID)
            scheduleRowHeightReassertion()
        }

        private func scheduleDeferredAttach(from view: NSView) {
            guard !pendingAttachRetry else { return }
            pendingAttachRetry = true

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.pendingAttachRetry = false
                guard let view else { return }
                self.attachTableViewIfNeeded(from: view)
            }
        }

        private func findTableView(near view: NSView) -> NSTableView? {
            if let localMatch = bestTableView(in: view) {
                return localMatch
            }

            var ancestor = view.superview
            var previous: NSView = view
            while let current = ancestor {
                let siblingCandidates = current.subviews.filter { $0 !== previous }
                if let siblingMatch = bestTableView(in: siblingCandidates) {
                    return siblingMatch
                }
                if let localMatch = bestTableView(in: current) {
                    return localMatch
                }
                previous = current
                ancestor = current.superview
            }

            if let windowContent = view.window?.contentView {
                return bestTableView(in: windowContent)
            }

            return nil
        }

        private func bestTableView(in root: NSView) -> NSTableView? {
            bestTableView(in: [root])
        }

        private func bestTableView(in roots: [NSView]) -> NSTableView? {
            var candidates: [NSTableView] = []
            for root in roots {
                collectTableViews(from: root, into: &candidates)
            }
            return candidates.max { lhs, rhs in
                candidateRank(for: lhs) < candidateRank(for: rhs)
            }
        }

        private func candidateRank(for tableView: NSTableView) -> (Int, Int, Int, Int) {
            let mappedColumnCount = currentMappedColumnOrder(for: tableView)?.count ?? 0
            let targetRowCount = rowIDs.count
            let rowMatchScore: Int
            if targetRowCount == 0 {
                rowMatchScore = tableView.numberOfRows == 0 ? 10_000 : -tableView.numberOfRows
            } else {
                rowMatchScore = -abs(tableView.numberOfRows - targetRowCount)
            }

            let inWindowScore = tableView.window == nil ? 0 : 1
            let visibleAreaScore = Int((tableView.visibleRect.width * tableView.visibleRect.height).rounded())
            return (rowMatchScore, mappedColumnCount, inWindowScore, visibleAreaScore)
        }

        private func collectTableViews(from view: NSView, into result: inout [NSTableView]) {
            if let tableView = view as? NSTableView {
                result.append(tableView)
            }
            for subview in view.subviews {
                collectTableViews(from: subview, into: &result)
            }
        }
    }
}

private struct UnhideColumnsPopoverContent: View {
    let language: AppLanguage
    let columns: [PaperTableColumn]
    let onApply: ([PaperTableColumn]) -> Void
    @State private var selectedColumns: Set<PaperTableColumn>

    init(
        language: AppLanguage,
        columns: [PaperTableColumn],
        onApply: @escaping ([PaperTableColumn]) -> Void
    ) {
        self.language = language
        self.columns = columns
        self.onApply = onApply
        _selectedColumns = State(initialValue: Set(columns))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unhide")
                .font(.headline)

            if columns.isEmpty {
                Text("No Hidden Columns")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(columns, id: \.self) { column in
                            Toggle(
                                column.displayName(for: language),
                                isOn: Binding(
                                    get: { selectedColumns.contains(column) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedColumns.insert(column)
                                        } else {
                                            selectedColumns.remove(column)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Select All") {
                    selectedColumns = Set(columns)
                }
                .disabled(columns.isEmpty)

                Spacer()

                Button("Unhide Selected") {
                    let ordered = columns.filter { selectedColumns.contains($0) }
                    onApply(ordered)
                }
                .disabled(selectedColumns.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private final class ColumnHeaderMenuHeaderView: NSTableHeaderView {
    var columnMenuProvider: ((NSTableColumn) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tableView else { return super.menu(for: event) }
        let location = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: location)
        guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
            return super.menu(for: event)
        }
        let tableColumn = tableView.tableColumns[columnIndex]
        return columnMenuProvider?(tableColumn) ?? super.menu(for: event)
    }
}
