import Foundation
import OCRShared

/// Talks to the text-reading helper (an XPC service bundled inside the app).
///
/// The main app never loads Apple's text-recognition engine itself. The helper
/// does the work and quits when idle, so that memory goes back to the system.
@MainActor
final class OCRClient {
    static let shared = OCRClient()

    private var connection: NSXPCConnection?

    private init() {}

    private func makeConnectionIfNeeded() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(serviceName: ocrServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: OCRServiceProtocol.self)
        // The helper quitting while idle is normal: the next request relaunches it.
        connection.invalidationHandler = {
            Task { @MainActor in OCRClient.shared.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    /// Returns the lines of text in the image, or nil if the helper couldn't be reached.
    func recognize(url: URL) async -> [String]? {
        let connection = makeConnectionIfNeeded()
        return await withCheckedContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                NSLog("Screenshot Shelf: text reader unavailable: \(error)")
                continuation.resume(returning: nil)
            }
            guard let service = proxy as? OCRServiceProtocol else {
                continuation.resume(returning: nil)
                return
            }
            service.recognizeText(atPath: url.path) { lines in
                continuation.resume(returning: lines)
            }
        }
    }
}
