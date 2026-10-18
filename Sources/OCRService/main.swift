import Foundation
import Vision
import ImageIO
import OCRShared

// Screenshot Shelf's text-reading helper (an XPC service).
//
// macOS starts it when the app asks for text, and it quits a few seconds after
// its last job, so the memory used by text recognition is handed back to the system.

/// Quits the helper once it has been idle for a few seconds.
final class IdleExit {
    static let shared = IdleExit()
    private let queue = DispatchQueue(label: "ScreenshotShelf.OCRService.idle")
    private var activeJobs = 0
    private var pendingExit: DispatchWorkItem?
    private let idleSeconds: Double = 5

    func jobStarted() {
        queue.sync {
            activeJobs += 1
            pendingExit?.cancel()
            pendingExit = nil
        }
    }

    func jobFinished() {
        queue.sync {
            activeJobs -= 1
            if activeJobs == 0 { scheduleExitLocked() }
        }
    }

    func armInitialTimer() {
        queue.sync { scheduleExitLocked() }
    }

    private func scheduleExitLocked() {
        pendingExit?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.activeJobs == 0 else { return }
            exit(0)
        }
        pendingExit = item
        queue.asyncAfter(deadline: .now() + idleSeconds, execute: item)
    }
}

final class OCRService: NSObject, OCRServiceProtocol {
    /// One image at a time keeps memory flat.
    private static let workQueue = DispatchQueue(label: "ScreenshotShelf.OCRService.work", qos: .utility)

    func recognizeText(atPath path: String, withReply reply: @escaping ([String]) -> Void) {
        IdleExit.shared.jobStarted()
        OCRService.workQueue.async {
            let lines = autoreleasepool { OCRService.recognize(path: path) }
            reply(lines)
            IdleExit.shared.jobFinished()
        }
    }

    private static func recognize(path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        // 2400px on the long side is plenty for text and far lighter than a full 5K capture.
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

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: OCRServiceProtocol.self)
        connection.exportedObject = OCRService()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
IdleExit.shared.armInitialTimer()   // quit even if nobody ever sends a job
listener.resume()                   // runs forever (until IdleExit quits the process)
