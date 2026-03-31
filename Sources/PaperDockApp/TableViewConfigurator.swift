import AppKit
import SwiftUI

@MainActor
struct TableViewConfigurator: NSViewRepresentable {
    let autosaveName: String
    let language: AppLanguage
    let columnVisibility: [PaperTableColumn: Bool]
    let columnWidths: [PaperTableColumn: CGFloat]
    let rowIDs: [UUID]
    let desiredColumnOrder: [PaperTableColumn]
    let preserveRowID: UUID?
    let preserveRequestNonce: UUID
    let rowHeightMultiplier: CGFloat
    let onSelectRows: ([UUID], UUID?) -> Void
    let onDoubleClickRow: (UUID) -> Void
    let onColumnOrderChange: ([PaperTableColumn]) -> Void
    let onColumnWidthChange: (PaperTableColumn, CGFloat) -> Void
    let onSetColumnVisibility: (PaperTableColumn, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.updateCallbacks(
            columnVisibility: columnVisibility,
            columnWidths: columnWidths,
            language: language,
            rowIDs: rowIDs,
            desiredColumnOrder: desiredColumnOrder,
            preserveRowID: preserveRowID,
            preserveRequestNonce: preserveRequestNonce,
            rowHeightMultiplier: rowHeightMultiplier,
            onSelectRows: onSelectRows,
            onDoubleClickRow: onDoubleClickRow,
            onColumnOrderChange: onColumnOrderChange,
            onColumnWidthChange: onColumnWidthChange,
            onSetColumnVisibility: onSetColumnVisibility
        )
        context.coordinator.attachTableViewIfNeeded(from: view, autosaveName: autosaveName)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateCallbacks(
            columnVisibility: columnVisibility,
            columnWidths: columnWidths,
            language: language,
            rowIDs: rowIDs,
            desiredColumnOrder: desiredColumnOrder,
            preserveRowID: preserveRowID,
            preserveRequestNonce: preserveRequestNonce,
            rowHeightMultiplier: rowHeightMultiplier,
            onSelectRows: onSelectRows,
            onDoubleClickRow: onDoubleClickRow,
            onColumnOrderChange: onColumnOrderChange,
            onColumnWidthChange: onColumnWidthChange,
            onSetColumnVisibility: onSetColumnVisibility
        )
        context.coordinator.attachTableViewIfNeeded(from: nsView, autosaveName: autosaveName)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject {
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
        private var rowHeightMultiplier: CGFloat = 1
        private var lastProcessedPreserveNonce: UUID?
        private var pendingPreserveAnchor: RowPreserveAnchor?
        private var pendingPreserveRestoreWorkItem: DispatchWorkItem?
        private var selectionDidChangeObserver: NSObjectProtocol?
        private var clipViewBoundsObserver: NSObjectProtocol?
        private weak var observedClipView: NSClipView?
        private var isApplyingPreserveScroll = false
        private var isApplyingColumnOrder = false
        private var isApplyingColumnWidths = false
        private var shouldApplyDesiredColumnOrder = true
        private var shouldApplyDesiredColumnWidths = true
        private var headerRightClickMonitor: Any?
        private var rowDragSelectionMonitor: Any?
        private var selectionAnchorRow: Int?
        private var pendingAttachRetry = false
        private var unhidePopover: NSPopover?

        private struct RowPreserveAnchor {
            var rowID: UUID
        }

        func updateCallbacks(
            columnVisibility: [PaperTableColumn: Bool],
            columnWidths: [PaperTableColumn: CGFloat],
            language: AppLanguage,
            rowIDs: [UUID],
            desiredColumnOrder: [PaperTableColumn],
            preserveRowID: UUID?,
            preserveRequestNonce: UUID,
            rowHeightMultiplier: CGFloat,
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

            var capturedNewPreserveAnchor = false
            if preserveRequestNonce != lastProcessedPreserveNonce {
                capturePreserveAnchorIfPossible(for: preserveRowID)
                lastProcessedPreserveNonce = preserveRequestNonce
                capturedNewPreserveAnchor = true
            }

            let didRowHeightChange = abs(self.rowHeightMultiplier - rowHeightMultiplier) > 0.001
            self.rowHeightMultiplier = rowHeightMultiplier
            if didRowHeightChange {
                schedulePreserveAnchorRestoreIfNeeded()
            } else if capturedNewPreserveAnchor {
                // One-shot policy: if this request did not actually change row height,
                // discard anchor now so it won't unexpectedly re-apply later.
                pendingPreserveAnchor = nil
            }

            self.onSelectRows = onSelectRows
            self.onDoubleClickRow = onDoubleClickRow
            self.onColumnOrderChange = onColumnOrderChange
            self.onColumnWidthChange = onColumnWidthChange
            self.onSetColumnVisibility = onSetColumnVisibility
        }

        func attachTableViewIfNeeded(from view: NSView, autosaveName: String) {
            guard let found = findTableView(near: view) else {
                scheduleDeferredAttach(from: view, autosaveName: autosaveName)
                return
            }

            pendingAttachRetry = false

            let isNewTable = tableView !== found
            tableView = found

            if isNewTable {
                configureTableView(found, autosaveName: autosaveName)
                shouldApplyDesiredColumnOrder = true
                shouldApplyDesiredColumnWidths = true
            }

            if shouldApplyDesiredColumnOrder {
                applyDesiredColumnOrderIfNeeded()
            }

            if shouldApplyDesiredColumnWidths {
                applyDesiredColumnWidthsIfNeeded()
            }

            installClipViewBoundsObserverIfNeeded(for: found)

            // Avoid high-frequency state sync on every representable update.
            // Column move/resize notifications already persist the latest values.
            if isNewTable {
                syncCurrentColumnStateToSettings()
            }
        }

        func teardown() {
            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidMoveNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: nil)
            removeSelectionDidChangeObserver()
            removeHeaderContextMenuMonitor()
            removeRowDragSelectionMonitor()
            removeClipViewBoundsObserver()
            unhidePopover?.performClose(nil)
            unhidePopover = nil
            pendingPreserveRestoreWorkItem?.cancel()
            pendingPreserveRestoreWorkItem = nil
            pendingPreserveAnchor = nil
            tableView = nil
        }

        private func configureTableView(_ tableView: NSTableView, autosaveName: String) {
            tableView.allowsColumnReordering = true
            tableView.allowsColumnResizing = true
            tableView.allowsMultipleSelection = true
            tableView.allowsEmptySelection = true
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            tableView.usesAutomaticRowHeights = true
            tableView.usesAlternatingRowBackgroundColors = false
            tableView.backgroundColor = .textBackgroundColor
            tableView.selectionHighlightStyle = .regular
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
            tableView.autosaveName = autosaveName
            tableView.autosaveTableColumns = false
            tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
            tableView.setDraggingSourceOperationMask(.copy, forLocal: true)

            if let scrollView = tableView.enclosingScrollView {
                scrollView.drawsBackground = true
                scrollView.backgroundColor = .textBackgroundColor
            }

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

            installHeaderContextMenuMonitor(for: tableView)
            installRowDragSelectionMonitor(for: tableView)
            installSelectionDidChangeObserver(for: tableView)
        }

        private func installHeaderContextMenuMonitor(for tableView: NSTableView) {
            removeHeaderContextMenuMonitor()

            headerRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self,
                      let currentTable = self.tableView,
                      currentTable === tableView,
                      event.window === currentTable.window,
                      let headerView = currentTable.headerView else {
                    return event
                }

                let isSecondaryClick = event.type == .rightMouseDown
                    || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
                guard isSecondaryClick else { return event }

                let pointInHeader = headerView.convert(event.locationInWindow, from: nil)
                guard headerView.bounds.contains(pointInHeader) else { return event }

                let columnIndex = headerView.column(at: pointInHeader)
                guard columnIndex >= 0, columnIndex < currentTable.tableColumns.count else { return event }

                let targetColumn = currentTable.tableColumns[columnIndex]
                guard let menu = self.makeColumnContextMenu(for: targetColumn) else { return event }

                NSMenu.popUpContextMenu(menu, with: event, for: headerView)
                return nil
            }
        }

        private func removeHeaderContextMenuMonitor() {
            if let headerRightClickMonitor {
                NSEvent.removeMonitor(headerRightClickMonitor)
                self.headerRightClickMonitor = nil
            }
        }

        private func installRowDragSelectionMonitor(for tableView: NSTableView) {
            removeRowDragSelectionMonitor()
            selectionAnchorRow = nil

            rowDragSelectionMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                guard let self,
                      let currentTable = self.tableView,
                      currentTable === tableView,
                      event.window === currentTable.window else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                let locationInTable = currentTable.convert(event.locationInWindow, from: nil)
                let isInTableBounds = currentTable.bounds.contains(locationInTable)

                switch event.type {
                case .leftMouseDown:
                    guard modifiers.isEmpty, isInTableBounds else {
                        self.selectionAnchorRow = nil
                        return event
                    }
                    let row = currentTable.row(at: locationInTable)
                    self.selectionAnchorRow = row >= 0 ? row : nil
                case .leftMouseDragged:
                    guard modifiers.isEmpty,
                          let anchorRow = self.selectionAnchorRow,
                          anchorRow >= 0 else {
                        return event
                    }
                    currentTable.selectRowIndexes(IndexSet(integer: anchorRow), byExtendingSelection: false)
                case .leftMouseUp:
                    self.selectionAnchorRow = nil
                default:
                    break
                }

                return event
            }
        }

        private func removeRowDragSelectionMonitor() {
            if let rowDragSelectionMonitor {
                NSEvent.removeMonitor(rowDragSelectionMonitor)
                self.rowDragSelectionMonitor = nil
            }
            selectionAnchorRow = nil
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

            let menu = NSMenu(title: targetColumn.displayName)
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
                Task { @MainActor [weak self] in
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

        private func handleSelectionDidChange(_ sender: NSTableView) {
            let selectedRows = sender.selectedRowIndexes.compactMap { index -> UUID? in
                guard index >= 0, index < rowIDs.count else { return nil }
                return rowIDs[index]
            }
            let primaryID: UUID? = {
                let clickedRow = sender.clickedRow
                if clickedRow >= 0, clickedRow < rowIDs.count {
                    return rowIDs[clickedRow]
                }

                let selectedRow = sender.selectedRow
                guard selectedRow >= 0, selectedRow < rowIDs.count else { return nil }
                return rowIDs[selectedRow]
            }()
            onSelectRows?(selectedRows, primaryID)
        }

        private func capturePreserveAnchorIfPossible(for rowID: UUID?) {
            guard let rowID,
                  let tableView,
                  let row = rowIDs.firstIndex(of: rowID),
                  row >= 0,
                  row < tableView.numberOfRows else {
                pendingPreserveAnchor = nil
                return
            }
            pendingPreserveAnchor = RowPreserveAnchor(
                rowID: rowID
            )
        }

        private func schedulePreserveAnchorRestoreIfNeeded() {
            guard pendingPreserveAnchor != nil else { return }
            pendingPreserveRestoreWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingPreserveRestoreWorkItem = nil
                self.restorePreserveAnchorIfPossible()
            }
            pendingPreserveRestoreWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        private func restorePreserveAnchorIfPossible() {
            guard let anchor = pendingPreserveAnchor else { return }
            guard let tableView,
                  let row = rowIDs.firstIndex(of: anchor.rowID),
                  row >= 0,
                  row < tableView.numberOfRows,
                  let scrollView = tableView.enclosingScrollView else {
                pendingPreserveAnchor = nil
                return
            }

            tableView.layoutSubtreeIfNeeded()
            scrollView.layoutSubtreeIfNeeded()

            let rowRect = tableView.rect(ofRow: row)
            let clipView = scrollView.contentView
            let visibleHeight = clipView.bounds.height
            let fullHeight = tableView.bounds.height

            guard rowRect.height > 0, visibleHeight > 0, fullHeight > 0 else {
                pendingPreserveAnchor = nil
                return
            }

            var targetY = rowRect.midY - (visibleHeight / 2)
            let maxY = max(0, fullHeight - visibleHeight)
            targetY = min(max(0, targetY), maxY)

            var newBounds = clipView.bounds
            newBounds.origin.y = targetY
            isApplyingPreserveScroll = true
            defer { isApplyingPreserveScroll = false }
            clipView.setBoundsOrigin(newBounds.origin)
            scrollView.reflectScrolledClipView(clipView)

            pendingPreserveAnchor = nil
        }

        private func installClipViewBoundsObserverIfNeeded(for tableView: NSTableView) {
            guard let clipView = tableView.enclosingScrollView?.contentView else { return }
            if observedClipView === clipView { return }
            removeClipViewBoundsObserver()
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            clipViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleClipViewBoundsDidChange()
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

        private func handleClipViewBoundsDidChange() {
            guard pendingPreserveAnchor != nil else { return }
            guard !isApplyingPreserveScroll else { return }
            pendingPreserveRestoreWorkItem?.cancel()
            pendingPreserveRestoreWorkItem = nil
            pendingPreserveAnchor = nil
        }

        private func scheduleDeferredAttach(from view: NSView, autosaveName: String) {
            guard !pendingAttachRetry else { return }
            pendingAttachRetry = true

            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.pendingAttachRetry = false
                guard let view else { return }
                self.attachTableViewIfNeeded(from: view, autosaveName: autosaveName)
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
                currentMappedColumnOrder(for: lhs)?.count ?? 0 < currentMappedColumnOrder(for: rhs)?.count ?? 0
            }
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
    let columns: [PaperTableColumn]
    let onApply: ([PaperTableColumn]) -> Void
    @State private var selectedColumns: Set<PaperTableColumn>

    init(
        columns: [PaperTableColumn],
        onApply: @escaping ([PaperTableColumn]) -> Void
    ) {
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
                                column.displayName,
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
