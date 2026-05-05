import AppKit
import SwiftUI

struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedField: AdvancedSearchField?
    let placeholder: String
    let allFieldsTitle: String
    let focusRequest: UUID?
    let isSearching: Bool
    var language: AppLanguage = .english

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> LoadingSearchField {
        let searchField = LoadingSearchField(frame: .zero)
        searchField.delegate = context.coordinator
        searchField.placeholderString = placeholder
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 15, weight: .regular)
        searchField.focusRingType = .default
        // Send search on Enter only (not incremental) to avoid excessive
        // filtering while typing; ContentView triggers async search on commit.
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.cell?.lineBreakMode = .byClipping
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.commitSearchFromControl(_:))
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.configureSearchMenu(for: searchField)
        searchField.setSearching(isSearching)
        return searchField
    }

    func updateNSView(_ nsView: LoadingSearchField, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.committedText != text {
            nsView.stringValue = text
            context.coordinator.committedText = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        nsView.setSearching(isSearching)
        context.coordinator.configureSearchMenu(for: nsView)

        guard let focusRequest, context.coordinator.lastFocusRequest != focusRequest else {
            return
        }

        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async {
            guard nsView.window != nil else { return }
            nsView.selectText(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        var lastFocusRequest: UUID?
        var committedText: String
        var isEditing = false
        private weak var hostedSearchField: NSSearchField?

        init(parent: ToolbarSearchField) {
            self.parent = parent
            self.committedText = parent.text
        }

        func configureSearchMenu(for searchField: NSSearchField) {
            hostedSearchField = searchField

            let menu = NSMenu(title: parent.language == .english ? "Search Fields" : "搜索字段")

            let allItem = NSMenuItem(
                title: parent.allFieldsTitle,
                action: #selector(selectSearchFieldFromMenu(_:)),
                keyEquivalent: ""
            )
            allItem.target = self
            allItem.representedObject = ""
            allItem.state = parent.selectedField == nil ? .on : .off
            menu.addItem(allItem)
            menu.addItem(.separator())

            for group in Self.searchFieldGroups {
                let groupItem = NSMenuItem(title: group.title(for: parent.language), action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: group.title(for: parent.language))
                for field in group.fields {
                    let item = NSMenuItem(
                        title: field.title(for: parent.language),
                        action: #selector(selectSearchFieldFromMenu(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = field.rawValue
                    item.state = parent.selectedField == field ? .on : .off
                    submenu.addItem(item)
                }
                groupItem.submenu = submenu
                menu.addItem(groupItem)
            }

            searchField.searchMenuTemplate = menu
        }

        private struct SearchFieldGroup {
            let key: String
            let fields: [AdvancedSearchField]

            func title(for language: AppLanguage) -> String {
                switch key {
                case "basic": return language == .english ? "Basic Info" : "基本信息"
                case "content": return language == .english ? "Content" : "内容"
                case "details": return language == .english ? "Details" : "详情"
                case "properties": return language == .english ? "Properties" : "属性"
                case "sample": return language == .english ? "Sample" : "样本"
                case "other": return language == .english ? "Other" : "其他"
                default: return key
                }
            }
        }

        // Grouped submenu: organizes 30+ search fields into logical sections
        // (Basic Info, Content, Details, etc.) instead of one flat list.
        private static let searchFieldGroups: [SearchFieldGroup] = [
            SearchFieldGroup(key: "basic", fields: [.title, .englishTitle, .authors, .authorsEnglish, .source, .year, .doi]),
            SearchFieldGroup(key: "content", fields: [.abstractText, .chineseAbstract, .fullText, .keywords]),
            SearchFieldGroup(key: "details", fields: [.notes, .rqs, .conclusion, .results, .methodology]),
            SearchFieldGroup(key: "properties", fields: [.volume, .issue, .pages, .paperType, .category, .impactFactor]),
            SearchFieldGroup(key: "sample", fields: [.samples, .participantType, .variables, .dataCollection, .dataAnalysis]),
            SearchFieldGroup(key: "other", fields: [.theoreticalFoundation, .educationalLevel, .country, .limitations, .webPageURL, .tags, .collections, .attachmentStatus]),
        ]

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? LoadingSearchField,
                  !searchField.stringValue.isEmpty else { return }
            searchField.ensureCancelButtonVisible()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard let searchField = control as? NSSearchField else {
                    return false
                }
                commitSearch(searchField.stringValue)
                control.window?.makeFirstResponder(nil)
                return true
            }

            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
                return false
            }

            guard let searchField = control as? NSSearchField else {
                return false
            }

            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                commitSearch("")
                return true
            }

            control.window?.makeFirstResponder(nil)
            return true
        }

        @objc
        func commitSearchFromControl(_ sender: NSSearchField) {
            commitSearch(sender.stringValue)
        }

        private func commitSearch(_ value: String) {
            committedText = value
            if parent.text != value {
                parent.text = value
            }
        }

        @objc
        private func selectSearchFieldFromMenu(_ sender: NSMenuItem) {
            let raw = (sender.representedObject as? String) ?? ""
            let nextField = AdvancedSearchField(rawValue: raw)
            if parent.selectedField != nextField {
                parent.selectedField = nextField
            }

            if let hostedSearchField {
                configureSearchMenu(for: hostedSearchField)
            }
        }
    }
}

final class LoadingSearchField: NSSearchField {
    private let progressIndicator = NSProgressIndicator(frame: .zero)
    private var isShowingSearchProgress = false
    private var originalCancelButtonCell: NSButtonCell?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureProgressIndicator()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureProgressIndicator()
    }

    func setSearching(_ searching: Bool) {
        guard searching != isShowingSearchProgress else {
            if !searching, !stringValue.isEmpty {
                ensureCancelButtonVisible()
            }
            return
        }
        isShowingSearchProgress = searching

        if searching {
            if originalCancelButtonCell == nil {
                originalCancelButtonCell = (cell as? NSSearchFieldCell)?.cancelButtonCell
            }
            // Replace the native cancel (×) button with an invisible cell
            // so the progress spinner doesn't fight for the same right-side slot.
            replaceCancelButtonCell(with: NullButtonCell())
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        } else {
            if let original = originalCancelButtonCell {
                replaceCancelButtonCell(with: original)
            }
            originalCancelButtonCell = nil
            progressIndicator.stopAnimation(nil)
            progressIndicator.isHidden = true
            if !stringValue.isEmpty {
                ensureCancelButtonVisible()
            }
        }

        needsLayout = true
        needsDisplay = true
    }

    func ensureCancelButtonVisible() {
        guard let searchCell = cell as? NSSearchFieldCell else { return }
        searchCell.cancelButtonCell?.isEnabled = true
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 14
        progressIndicator.frame = NSRect(
            x: bounds.maxX - size - 6,
            y: bounds.midY - size / 2,
            width: size,
            height: size
        )
    }

    private func replaceCancelButtonCell(with newCell: NSButtonCell) {
        guard let searchFieldCell = cell as? NSSearchFieldCell else { return }
        searchFieldCell.cancelButtonCell = newCell
    }

    private func configureProgressIndicator() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = true
        progressIndicator.alphaValue = 0.85
        addSubview(progressIndicator)
    }
}

/// A button cell that draws nothing and ignores clicks — used to hide the cancel button during search.
private final class NullButtonCell: NSButtonCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {}
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView, untilMouseUp: Bool) -> Bool { false }
}
