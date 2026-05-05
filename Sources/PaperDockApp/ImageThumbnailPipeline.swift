import AppKit
import ImageIO
import SwiftUI

actor ImageThumbnailPipeline {
    static let shared = ImageThumbnailPipeline()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [NSString: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 512
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL, maxPixel: CGFloat) async -> NSImage? {
        let pixel = max(32, Int(maxPixel.rounded()))
        let key = cacheKey(for: url, pixel: pixel)

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let normalizedURL = url.standardizedFileURL
        let task = Task.detached(priority: .utility) {
            Self.decodeThumbnail(from: normalizedURL, maxPixel: pixel)
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil

        if let image {
            let cost = max(1, Int(image.size.width * image.size.height * 4))
            cache.setObject(image, forKey: key, cost: cost)
        }

        return image
    }

    func prefetch(urls: [URL], maxPixel: CGFloat, limit: Int = 24) async {
        guard limit > 0 else { return }
        let targets = Array(urls.prefix(limit))
        for url in targets {
            if Task.isCancelled { break }
            _ = await image(for: url, maxPixel: maxPixel)
        }
    }

    private func cacheKey(for url: URL, pixel: Int) -> NSString {
        "\(url.standardizedFileURL.path)#\(pixel)" as NSString
    }

    nonisolated private static func decodeThumbnail(from url: URL, maxPixel: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return NSImage(contentsOf: url)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

struct ThumbnailImageView: View {
    let url: URL
    let maxPixel: CGFloat
    var placeholderOpacity: Double = 0.16
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                switch contentMode {
                case .fit:
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                default:
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(placeholderOpacity))
            }
        }
        .task(id: taskKey) {
            image = await ImageThumbnailPipeline.shared.image(for: url, maxPixel: maxPixel)
        }
    }

    private var taskKey: String {
        "\(url.standardizedFileURL.path)#\(Int(maxPixel.rounded()))"
    }
}
