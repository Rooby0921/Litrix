import AppKit
import Quartz

@MainActor
final class QuickLookPreviewManager: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookPreviewManager()

    private var previewURL: URL?

    func togglePreview(url: URL) {
        if isPreviewing(url: url) {
            closePreview()
        } else {
            preview(url: url)
        }
    }

    func preview(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func closePreview() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
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
}
