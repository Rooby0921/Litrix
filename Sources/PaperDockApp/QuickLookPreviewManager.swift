import AppKit
import Quartz

@MainActor
final class QuickLookPreviewManager: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewManager()

    private var previewURL: URL?
    private var lastToggleTime: TimeInterval = 0

    func togglePreview(url: URL) {
        guard shouldAcceptToggle() else { return }
        if isPreviewing(url: url) {
            closePreview()
        } else {
            preview(url: url)
        }
    }

    func preview(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        let standardizedURL = url.standardizedFileURL
        let isSameItem = previewURL?.standardizedFileURL == standardizedURL
        previewURL = url
        panel.dataSource = self
        if !panel.isVisible || !isSameItem {
            panel.reloadData()
            panel.currentPreviewItemIndex = 0
        }
        panel.orderFront(nil)
    }

    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        previewURL = nil
    }

    func isPreviewing(url: URL) -> Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible,
              let previewURL else {
            return false
        }
        return previewURL.standardizedFileURL == url.standardizedFileURL
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    private func shouldAcceptToggle() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastToggleTime = now }
        return now - lastToggleTime > 0.12
    }
}
