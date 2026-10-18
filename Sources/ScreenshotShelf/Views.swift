import SwiftUI
import AppKit

// MARK: - Helpers

enum Format {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Fills a fixed-height box with the image, cropped, without affecting layout.
struct ThumbnailView: View {
    let image: NSImage?
    let height: CGFloat

    var body: some View {
        Color.white.opacity(0.08)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        // The cropped-off part of the image is invisible but would
                        // still catch clicks meant for buttons around it.
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .contentShape(Rectangle())   // clickable area = exactly the visible box
    }
}

struct PillButton: View {
    let title: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(prominent ? Color.accentColor : Color.white.opacity(0.18)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.18)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
    }
}

/// Icon button that reads well on both the dark shelf and the light menu window.
struct SubtleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Two-tab switcher built from plain buttons, so it responds on the first click
/// even when the shelf isn't the focused window.
struct TabSwitcher: View {
    @Binding var selection: ShelfTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ShelfTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == tab ? Color.white.opacity(0.18) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

// MARK: - Floating shelf

/// Carries the shelf's laid-out size up to the panel, which sizes the window to match.
struct ShelfSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var clips: ClipStore
    @ObservedObject var ui: ShelfUIState
    var onHide: () -> Void
    var onSizeChange: (CGSize) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TabSwitcher(selection: $ui.tab)

                Button(action: onHide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close shelf (Esc)")
                .accessibilityLabel("Close shelf")
            }

            if let toast = store.toast {
                ToastView(text: toast)
            }

            switch ui.tab {
            case .shots: shotsList
            case .clips: clipsList
            }
        }
        .padding(12)
        .frame(width: 284)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.11).opacity(0.95)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .fixedSize()   // always its natural size, whatever the window currently is
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ShelfSizeKey.self, value: geo.size)
            })
        .onPreferenceChange(ShelfSizeKey.self) { size in onSizeChange(size) }
        .environment(\.colorScheme, .dark)
        .onExitCommand(perform: onHide)
        .onChange(of: ui.focusRequest) { _ in focusSearchSoon() }
        .onAppear { if ui.tab == .clips { focusSearchSoon() } }
    }

    @ViewBuilder
    private var shotsList: some View {
        if store.items.isEmpty {
            Text("No screenshots yet. Press ⇧⌘4.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            ForEach(Array(store.items.prefix(4))) { item in
                ShelfCard(store: store, item: item)
            }
            if store.items.count > 4 {
                Text("+\(store.items.count - 4) more in the menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var clipsList: some View {
        TextField("Search clipboard", text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit {
                if let first = clips.search(query).first { copyAndClose(first) }
            }

        let results = Array(clips.search(query).prefix(8))
        if clips.clips.isEmpty {
            Text("Copy something and it shows up here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else if results.isEmpty {
            Text("Nothing matches “\(query)”.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 6) {
                ForEach(results) { clip in
                    ClipRow(clips: clips, clip: clip) { copyAndClose(clip) }
                }
            }
        }

        Text("⌃⌘V opens this anywhere · Return copies the top one")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    private func copyAndClose(_ clip: ClipItem) {
        clips.copy(clip)
        query = ""
        onHide()
    }

    private func focusSearchSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            searchFocused = true
        }
    }
}

struct ShelfCard: View {
    @ObservedObject var store: ShelfStore
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                ThumbnailView(image: store.thumbnail(for: item), height: 124)
                if hovering {
                    HStack(spacing: 6) {
                        PillButton(title: "Copy", prominent: true) { store.copyImage(item) }
                        PillButton(title: "Copy text") { store.copyText(item) }
                        IconButton(systemName: item.pinned ? "pin.fill" : "pin",
                                   label: item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                        IconButton(systemName: "trash", label: "Move to Trash") { store.delete(item) }
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.75))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text(Format.relative(item.createdAt))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.expiryLabel(for: item))
                    .foregroundStyle(store.isExpiringSoon(item) ? Color.orange : Color.secondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { store.open(item) }
        .onDrag { store.dragProvider(for: item) }
        .help("Drag into any app · double-click to open")
    }
}

/// One clipboard entry. Click to copy it again.
struct ClipRow: View {
    @ObservedObject var clips: ClipStore
    let clip: ClipItem
    var onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if clip.kind == .image {
                ThumbnailView(image: clips.thumbnail(for: clip), height: 40)
                    .frame(width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("Image · \(Format.relative(clip.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Text(clip.preview)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hovering {
                SubtleIconButton(systemName: clip.pinned ? "pin.fill" : "pin",
                                 label: clip.pinned ? "Unpin" : "Pin") { clips.togglePin(clip) }
                SubtleIconButton(systemName: "xmark", label: "Remove") { clips.delete(clip) }
            } else if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.12 : 0.06)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onPick)
        .help("Click to copy")
    }
}

// MARK: - Menu bar library

struct LibraryView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var clips: ClipStore
    var onShowShelf: () -> Void
    @State private var tab: ShelfTab = .shots
    @State private var query = ""

    private let retentionOptions = [1, 3, 7, 14, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $tab) {
                ForEach(ShelfTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(tab == .shots ? "Search text inside screenshots" : "Search clipboard",
                      text: $query)
                .textFieldStyle(.roundedBorder)

            if let toast = store.toast {
                Text(toast)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            ScrollView {
                Group {
                    switch tab {
                    case .shots: screenshotsContent
                    case .clips: clipsContent
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 420)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-delete unpinned after")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Screenshots go to the Trash, so you can still recover them")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Auto-delete after", selection: $store.retentionDays) {
                    ForEach(retentionOptions, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                .labelsHidden()
                .frame(width: 96)
            }

            HStack {
                Button("Show shelf", action: onShowShelf)
                if tab == .shots {
                    Button("Open folder") { store.revealFolder() }
                } else {
                    Button("Clear unpinned") { clips.clearUnpinned() }
                        .disabled(clips.clips.allSatisfy(\.pinned))
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 440)
        .onChange(of: store.retentionDays) { days in clips.cleanupExpired(retentionDays: days) }
        .onChange(of: tab) { _ in query = "" }
    }

    @ViewBuilder
    private var screenshotsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.items.isEmpty {
                emptyState(icon: "rectangle.on.rectangle",
                           title: "No screenshots yet",
                           detail: "Press ⇧⌘4 or ⇧⌘3. New screenshots land here instead of piling up on your Desktop.")
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let results = store.search(query)
                if results.isEmpty {
                    noMatches
                } else {
                    section("Results", results, columns: 2)
                }
            } else {
                if !store.pinnedItems.isEmpty {
                    section("Pinned · kept forever", store.pinnedItems, columns: 3)
                }
                if !store.recentItems.isEmpty {
                    section("Recent", store.recentItems, columns: 2)
                }
            }
        }
    }

    @ViewBuilder
    private var clipsContent: some View {
        if clips.clips.isEmpty {
            emptyState(icon: "doc.on.clipboard",
                       title: "Nothing copied yet",
                       detail: "Everything you copy is saved here. Press ⌃⌘V anywhere to pick from it. Passwords from password managers are skipped.")
        } else {
            let results = clips.search(query)
            if results.isEmpty {
                noMatches
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(results) { clip in
                        ClipRow(clips: clips, clip: clip) { clips.copy(clip) }
                    }
                }
            }
        }
    }

    private var noMatches: some View {
        Text("Nothing matches “\(query)”.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func section(_ title: String, _ items: [ShelfItem], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
                      spacing: 12) {
                ForEach(items) { item in
                    LibraryTile(store: store, item: item, height: columns == 3 ? 80 : 110)
                }
            }
        }
    }
}

struct LibraryTile: View {
    @ObservedObject var store: ShelfStore
    let item: ShelfItem
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ThumbnailView(image: store.thumbnail(for: item), height: height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            HStack {
                Text(Format.relative(item.createdAt))
                Spacer()
                if !item.pinned {
                    Text(store.expiryLabel(for: item))
                        .foregroundStyle(store.isExpiringSoon(item) ? Color.orange : Color.secondary)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.open(item) }
        .onDrag { store.dragProvider(for: item) }
        .contextMenu {
            Button("Copy image") { store.copyImage(item) }
            Button("Copy text") { store.copyText(item) }
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Divider()
            Button("Move to Trash") { store.delete(item) }
        }
        .help("Click to open · drag into any app · right-click for more")
    }
}
