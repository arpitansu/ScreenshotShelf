import SwiftUI
import AppKit

@main
struct ScreenshotShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Screenshot Shelf", systemImage: "rectangle.on.rectangle") {
            LibraryView(store: appDelegate.store,
                        clips: appDelegate.clips,
                        onShowShelf: { appDelegate.shelf.show() })
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var store = ShelfStore()
    lazy var clips: ClipStore = {
        let clips = ClipStore()
        clips.toastHost = store
        return clips
    }()
    lazy var shelf = ShelfPanelController(store: store, clips: clips)

    private var watcher: ScreenshotWatcher?
    private var hotKey: HotKey?
    private var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let watcher = ScreenshotWatcher()
        watcher.onNewScreenshot = { [weak self] url in
            guard let self else { return }
            if self.store.ingest(url) != nil {
                self.shelf.show(tab: .shots)
            }
        }
        watcher.start()
        self.watcher = watcher

        clips.startWatching()

        // Control + Command + V: open clipboard history from anywhere.
        hotKey = HotKey { [weak self] in
            self?.shelf.toggleClipboard()
        }

        store.cleanupExpired()
        clips.cleanupExpired(retentionDays: store.retentionDays)
        store.backfillText()

        let timer = Timer(timeInterval: 3600, target: self,
                          selector: #selector(hourlyCleanup),
                          userInfo: nil, repeats: true)
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    @objc private func hourlyCleanup() {
        store.cleanupExpired()
        clips.cleanupExpired(retentionDays: store.retentionDays)
    }
}
