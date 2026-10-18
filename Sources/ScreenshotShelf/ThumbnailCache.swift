import AppKit
import ImageIO

/// Small, size-capped cache of downscaled thumbnails.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 60
        cache.totalCostLimit = 12 * 1024 * 1024   // ~12 MB of decoded pixels
    }

    func image(for url: URL, maxPixelSize: Int = 480) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        return image
    }

    func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func purge() {
        cache.removeAllObjects()
    }
}

/// Lets the clipboard watcher ignore pasteboard changes the app made itself.
@MainActor
enum PasteboardTracker {
    static var ownChangeCount = -1

    static func markOwnWrite() {
        ownChangeCount = NSPasteboard.general.changeCount
    }
}
