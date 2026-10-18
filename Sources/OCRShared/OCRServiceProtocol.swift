import Foundation

/// What the main app can ask the text-reading helper to do.
/// Shared by both sides of the XPC connection.
@objc(OCRServiceProtocol)
public protocol OCRServiceProtocol {
    /// Reads the text in the image at `path`. Replies with one string per line.
    func recognizeText(atPath path: String, withReply reply: @escaping ([String]) -> Void)
}

/// The helper's bundle identifier, which is also its XPC service name.
public let ocrServiceName = "local.arpit.screenshotshelf.OCRService"
