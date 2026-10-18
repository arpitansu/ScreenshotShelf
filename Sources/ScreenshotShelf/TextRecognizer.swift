import Foundation
import Vision
import ImageIO

/// On-device text recognition (Apple Vision). Nothing leaves the Mac.
/// Runs one image at a time so memory stays flat even when many need scanning.
enum TextRecognizer {
    private static let queue = DispatchQueue(label: "ScreenshotShelf.ocr", qos: .utility)

    static func recognize(url: URL) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                let lines = autoreleasepool { recognizeSync(url: url) }
                continuation.resume(returning: lines)
            }
        }
    }

    private static func recognizeSync(url: URL) -> [String] {
        // Decode at most 2400px on the long side: plenty for text, far less memory than a 5K Retina capture.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return []
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
