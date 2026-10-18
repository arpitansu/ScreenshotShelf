import Foundation
import AppKit

/// Waits for new screenshots in the folder macOS saves them to (Desktop by default).
///
/// It does not poll. macOS wakes it only when that folder's contents change,
/// so it costs nothing while you're not taking screenshots.
@MainActor
final class ScreenshotWatcher {
    var onNewScreenshot: ((URL) -> Void)?

    let directory: URL
    private var seen = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var recheckScheduled = false
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    init() {
        directory = ScreenshotWatcher.screenshotDirectory()
    }

    static func screenshotDirectory() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// - Parameter catchUpSince: screenshots taken after this moment that are still in
    ///   the folder were missed while the app was closed, so they're picked up now.
    ///   Anything older is left alone. Pass nil (first launch) to leave everything alone.
    func start(catchUpSince: Date? = nil) {
        var missed: [URL] = []
        for url in imageFiles() {
            seen.insert(url.lastPathComponent)
            if let since = catchUpSince,
               ScreenshotWatcher.isScreenCapture(url),
               let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created >= since {
                missed.append(url)
            }
        }

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Screenshot Shelf: can't watch \(directory.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .link],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source

        // Hand over the screenshots taken while the app was closed, oldest first.
        let sorted = missed.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for url in sorted { onNewScreenshot?(url) }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func imageFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Runs only when the folder changed.
    private func scan() {
        var waitingForTag = false

        for url in imageFiles() {
            let name = url.lastPathComponent
            if seen.contains(name) { continue }

            if ScreenshotWatcher.isScreenCapture(url) {
                seen.insert(name)
                onNewScreenshot?(url)
            } else {
                // macOS may tag the file a moment after it appears.
                // Give it a few seconds, then treat it as an ordinary image.
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                if Date().timeIntervalSince(created) > 5 {
                    seen.insert(name)
                } else {
                    waitingForTag = true
                }
            }
        }

        if waitingForTag { scheduleRecheck() }
    }

    /// One follow-up look a second later, only when a brand-new file is still untagged.
    private func scheduleRecheck() {
        guard !recheckScheduled else { return }
        recheckScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.recheckScheduled = false
            self.scan()
        }
    }

    /// macOS tags every screenshot with this extended attribute.
    static func isScreenCapture(_ url: URL) -> Bool {
        let size = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        }
        return size > 0
    }
}
