import AppKit
import SwiftUI

enum ShelfTab: String, CaseIterable, Identifiable {
    case shots = "Screenshots"
    case clips = "Clipboard"
    var id: String { rawValue }
}

/// Small piece of state shared between the panel controller and its SwiftUI view.
@MainActor
final class ShelfUIState: ObservableObject {
    @Published var tab: ShelfTab = .shots
    @Published var focusRequest = 0
    /// Opened with ⌃⌘V as a quick picker: closes after you pick something, or when
    /// you click elsewhere. Opened any other way, it stays put until you close it.
    @Published var isPopup = false
}

/// A borderless floating panel that can still take clicks and typing
/// without pulling focus away from the app you're in.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosting view that acts on the very first click, even when the shelf
/// isn't the focused window (otherwise that click is swallowed).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The floating shelf on the right edge of the screen.
@MainActor
final class ShelfPanelController: NSObject {
    private let store: ShelfStore
    private let clips: ClipStore
    private let ui = ShelfUIState()
    private let panel: KeyablePanel
    /// Only exists while the shelf is on screen; dropped on hide to free memory.
    private var hosting: FirstMouseHostingView<ShelfView>?
    /// Bumped on every show/hide so a delayed teardown never removes a fresh shelf.
    private var generation = 0
    /// Last size the shelf reported; starts as a sensible guess.
    private var contentSize = NSSize(width: 284, height: 220)

    var isVisible: Bool { panel.isVisible }

    init(store: ShelfStore, clips: ClipStore) {
        self.store = store
        self.clips = clips
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 284, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification, object: panel)
    }

    /// Shows the shelf. Screenshots tab pops up quietly; Clipboard tab takes typing focus.
    func show(tab: ShelfTab = .shots, popup: Bool = false) {
        generation += 1
        ui.tab = tab
        ui.isPopup = popup
        if hosting == nil {
            let view = ShelfView(
                store: store,
                clips: clips,
                ui: ui,
                onHide: { [weak self] in self?.hide() },
                onSizeChange: { [weak self] size in
                    Task { @MainActor in self?.contentDidResize(size) }
                })
            let hostingView = FirstMouseHostingView(rootView: view)
            // The panel sizes itself from what the shelf reports (see relayout).
            // Without this, the view and the window keep resizing each other
            // and clicks land in the wrong place.
            hostingView.sizingOptions = []
            hostingView.autoresizingMask = [.width, .height]
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            hosting = hostingView
            panel.contentView = hostingView
        }
        relayout()
        if tab == .clips {
            panel.makeKeyAndOrderFront(nil)
            ui.focusRequest += 1
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// For the keyboard shortcut: open the clipboard, or close it if it's already open.
    func toggleClipboard() {
        if panel.isVisible && ui.tab == .clips && ui.isPopup {
            hide()
        } else {
            show(tab: .clips, popup: true)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // Free the SwiftUI views and thumbnails a moment later, after the click
        // that closed the shelf has finished, and only if it wasn't reopened.
        generation += 1
        let hiddenGeneration = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self.generation == hiddenGeneration, !self.panel.isVisible else { return }
            self.panel.contentView = nil
            self.hosting = nil
            ThumbnailCache.shared.purge()
        }
    }

    @objc private func panelResignedKey() {
        // Only the ⌃⌘V picker closes when you click elsewhere. A shelf opened from the
        // menu bar (or by a new screenshot) stays open; other windows coming and going,
        // like the menu bar window closing, must not close it.
        if ui.isPopup { hide() }
    }

    private func contentDidResize(_ size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }   // ignore empty first passes
        contentSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        relayout()
    }

    /// Sets the panel's size and position in one step from the shelf's reported size,
    /// so what you see and where you can click always match.
    private func relayout() {
        guard let hosting else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        var size = contentSize
        size.height = min(size.height, visible.height - 24)

        let frame = NSRect(x: visible.maxX - size.width - 12,
                           y: visible.maxY - size.height - 12,
                           width: size.width,
                           height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true, animate: false)
        }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
    }
}
