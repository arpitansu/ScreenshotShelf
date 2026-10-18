import Foundation
import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var createdAt: Date
    var pinned: Bool
    /// Text found in the image. nil = not scanned yet.
    var text: String?
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var toast: String?
    /// How many screenshots are still waiting to have their text read (shown during search).
    @Published private(set) var textToRead = 0
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
            cleanupExpired()
        }
    }

    /// Where shelf screenshots live: ~/Pictures/Screenshot Shelf
    let folder: URL
    private let metadataURL: URL
    private var toastTask: Task<Void, Never>?
    private var isReadingText = false

    init() {
        let fm = FileManager.default
        let pictures = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        folder = pictures.appendingPathComponent("Screenshot Shelf", isDirectory: true)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenshotShelf", isDirectory: true)
        metadataURL = support.appendingPathComponent("items.json")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)

        let saved = UserDefaults.standard.integer(forKey: "retentionDays")
        retentionDays = saved > 0 ? saved : 7
        load()
    }

    // MARK: - Lookups

    func url(for item: ShelfItem) -> URL {
        folder.appendingPathComponent(item.fileName)
    }

    var pinnedItems: [ShelfItem] { items.filter { $0.pinned } }
    var recentItems: [ShelfItem] { items.filter { !$0.pinned } }

    func search(_ query: String) -> [ShelfItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            ($0.text ?? "").localizedCaseInsensitiveContains(q)
                || $0.fileName.localizedCaseInsensitiveContains(q)
        }
    }

    func thumbnail(for item: ShelfItem) -> NSImage? {
        ThumbnailCache.shared.image(for: url(for: item))
    }

    func expiryLabel(for item: ShelfItem) -> String {
        if item.pinned { return "Pinned" }
        let age = Date().timeIntervalSince(item.createdAt) / 86_400
        let left = retentionDays - Int(age.rounded(.down))
        switch left {
        case ...0: return "Deletes today"
        case 1: return "Deletes tomorrow"
        default: return "Deletes in \(left) days"
        }
    }

    func isExpiringSoon(_ item: ShelfItem) -> Bool {
        guard !item.pinned else { return false }
        let age = Date().timeIntervalSince(item.createdAt) / 86_400
        return retentionDays - Int(age.rounded(.down)) <= 2
    }

    // MARK: - Adding

    /// Moves a new screenshot onto the shelf. Returns the new item, or nil if the move failed.
    @discardableResult
    func ingest(_ source: URL) -> ShelfItem? {
        let fm = FileManager.default
        var target = folder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            let base = source.deletingPathExtension().lastPathComponent
            target = folder.appendingPathComponent("\(base) \(n).\(source.pathExtension)")
            n += 1
        }
        do {
            try fm.moveItem(at: source, to: target)
        } catch {
            NSLog("Screenshot Shelf: could not move \(source.path): \(error)")
            return nil
        }
        let item = ShelfItem(id: UUID(), fileName: target.lastPathComponent,
                             createdAt: Date(), pinned: false, text: nil)
        items.insert(item, at: 0)
        save()
        // Text is read later, only when you search or press Copy text.
        return item
    }

    /// Reads the text of every screenshot that hasn't been read yet, one at a time.
    /// Called when you start searching. Each screenshot is only ever read once.
    func readMissingText() {
        guard !isReadingText else { return }
        let pending = items.filter { $0.text == nil }
        guard !pending.isEmpty else { return }
        isReadingText = true
        textToRead = pending.count
        Task {
            for item in pending {
                if let lines = await OCRClient.shared.recognize(url: self.url(for: item)) {
                    self.setText(lines.joined(separator: "\n"), for: item.id)
                }
                self.textToRead = max(0, self.textToRead - 1)
            }
            self.textToRead = 0
            self.isReadingText = false
        }
    }

    private func setText(_ text: String, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].text = text
        save()
    }

    // MARK: - Actions

    /// Copies the file's bytes straight to the clipboard, without decoding the image.
    func copyImage(_ item: ShelfItem) {
        let fileURL = url(for: item)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let type: NSPasteboard.PasteboardType
        switch fileURL.pathExtension.lowercased() {
        case "png": type = .png
        case "tiff", "tif": type = .tiff
        default:
            let uti = UTType(filenameExtension: fileURL.pathExtension)?.identifier ?? "public.png"
            type = NSPasteboard.PasteboardType(uti)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: type)
        PasteboardTracker.markOwnWrite()   // don't save it again in clipboard history
        showToast("Image copied")
    }

    func copyText(_ item: ShelfItem) {
        if let text = item.text {
            writeText(text)
            return
        }
        let fileURL = url(for: item)
        let id = item.id
        showToast("Reading text…")
        Task {
            guard let lines = await OCRClient.shared.recognize(url: fileURL) else {
                self.showToast("Couldn't read text. Try again")
                return
            }
            let text = lines.joined(separator: "\n")
            self.setText(text, for: id)
            self.writeText(text)
        }
    }

    private func writeText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("No text found")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        let lines = trimmed.components(separatedBy: "\n").count
        showToast(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text")
    }

    func togglePin(_ item: ShelfItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        save()
        showToast(items[i].pinned ? "Pinned. It won't auto-delete" : "Unpinned")
    }

    /// Moves the file to the Trash (recoverable), never a permanent delete.
    func delete(_ item: ShelfItem) {
        ThumbnailCache.shared.remove(url(for: item))
        try? FileManager.default.trashItem(at: url(for: item), resultingItemURL: nil)
        items.removeAll { $0.id == item.id }
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(url(for: item))
    }

    func revealFolder() {
        NSWorkspace.shared.open(folder)
    }

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        NSItemProvider(contentsOf: url(for: item)) ?? NSItemProvider()
    }

    func cleanupExpired() {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        let expired = items.filter { !$0.pinned && $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        for item in expired {
            ThumbnailCache.shared.remove(url(for: item))
            try? FileManager.default.trashItem(at: url(for: item), resultingItemURL: nil)
        }
        let ids = Set(expired.map(\.id))
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let saved = try? decoder.decode([ShelfItem].self, from: data) else { return }
        items = saved.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(items) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }
}
