import AppKit
import SwiftUI

struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedField: AdvancedSearchField?
    let placeholder: String
    let allFieldsTitle: String
    let focusRequest: UUID?
    var language: AppLanguage = .english

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.delegate = context.coordinator
        searchField.placeholderString = placeholder
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 15, weight: .regular)
        searchField.focusRingType = .default
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.configureSearchMenu(for: searchField)
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
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
        private weak var hostedSearchField: NSSearchField?

        init(parent: ToolbarSearchField) {
            self.parent = parent
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

            for field in AdvancedSearchField.allCases {
                let item = NSMenuItem(
                    title: field.title,
                    action: #selector(selectSearchFieldFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = field.rawValue
                item.state = parent.selectedField == field ? .on : .off
                menu.addItem(item)
            }

            searchField.searchMenuTemplate = menu
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            if parent.text != searchField.stringValue {
                parent.text = searchField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else {
                return false
            }

            guard let searchField = control as? NSSearchField else {
                return false
            }

            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                if !parent.text.isEmpty {
                    parent.text = ""
                }
                return true
            }

            control.window?.makeFirstResponder(nil)
            return true
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
