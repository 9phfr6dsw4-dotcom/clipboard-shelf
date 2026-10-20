import AppKit
import Observation
import SwiftUI

extension ShelfRGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// The size of the popover, kept as it was in every earlier version.
enum ShelfStyle {
    static let width: CGFloat = 400
    static let height: CGFloat = 600
    /// Dark text and symbols on a pin-coloured button.
    static let pinInk = Color(red: 0.18, green: 0.12, blue: 0.0)
    static let paused = Color(red: 1.0, green: 0.62, blue: 0.04)
}

/// The skin's colours, ready to use.
struct ShelfPalette {
    let accent: Color
    let pin: Color
    let tint: Color

    init(skin: ShelfSkin) {
        accent = skin.accent.color
        pin = skin.pin.color
        tint = skin.tint.color
    }
}

enum ShelfFilter {
    case all
    case pinned
}

/// The app an item was copied from, looked up from its bundle identifier.
struct SourceAppInfo {
    let name: String
    let icon: NSImage
}

/// Finds the name and icon of the app that was in front at the time of a copy. Only the bundle
/// identifier is saved with an item, so an app that has since been removed simply shows no icon.
@MainActor
final class SourceAppResolver {
    static let shared = SourceAppResolver()

    private var found: [String: SourceAppInfo] = [:]
    private var missing = Set<String>()

    func info(for bundleIdentifier: String) -> SourceAppInfo? {
        if let known = found[bundleIdentifier] { return known }
        if missing.contains(bundleIdentifier) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            missing.insert(bundleIdentifier)
            return nil
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let info = SourceAppInfo(name: name, icon: icon)
        found[bundleIdentifier] = info
        return info
    }
}

/// What the shelf shows, and what its controls ask the app to do.
@MainActor
@Observable
final class ShelfModel {
    var history = ClipboardHistory()
    var recordingPaused = false
    var query = ""
    var filter: ShelfFilter = .all
    var preferences = ShelfPreferences()
    /// Whether the shelf is drawing in its dark look right now (decided by the app, from the
    /// Appearance choice and the Mac's own setting).
    var isDark = true

    @ObservationIgnored var onCopy: (ClipboardEntry) -> Void = { _ in }
    @ObservationIgnored var onTogglePin: (ClipboardEntry) -> Void = { _ in }
    @ObservationIgnored var onSetPaused: (Bool) -> Void = { _ in }
    @ObservationIgnored var onClearRecent: () -> Void = {}
    @ObservationIgnored var onShowMenu: () -> Void = {}
    @ObservationIgnored var onCheckForUpdates: () -> Void = {}
    /// Shows a waiting update in the shelf. The update controller is observable, so the row appears
    /// and goes away with it.
    @ObservationIgnored var updates: UpdateController?

    private var matching: [ClipboardEntry] { history.filteredEntries(matching: query) }
    var pinned: [ClipboardEntry] { matching.filter(\.isPinned) }
    var recent: [ClipboardEntry] { filter == .pinned ? [] : matching.filter { !$0.isPinned } }

    var emptyMessage: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matching clipboard items" }
        if filter == .pinned { return "No pinned items yet" }
        return "Copy some text to begin"
    }
}

/// The popover's content: search and the ⋯ menu, All/Pinned with the saving state, the pinned and
/// recent items, and the footer with the pause button.
struct ShelfView: View {
    @Bindable var model: ShelfModel

    var body: some View {
        let palette = ShelfPalette(skin: model.preferences.skin)
        VStack(alignment: .leading, spacing: 0) {
            topRow
                .padding(.bottom, 12)
            controls(palette)
                .padding(.bottom, 6)
            if let version = model.updates?.updateWaiting {
                updateRow(version, palette)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
            list(palette)
            footer(palette)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(width: ShelfStyle.width, height: ShelfStyle.height, alignment: .top)
        .background { skinBackground(palette) }
        .environment(\.colorScheme, model.isDark ? .dark : .light)
    }

    /// A wash of the skin's colour over the popover's own material.
    private func skinBackground(_ palette: ShelfPalette) -> some View {
        ZStack {
            LinearGradient(
                colors: model.isDark
                    ? [palette.tint.opacity(0.55), palette.tint.opacity(0.18)]
                    : [palette.accent.opacity(0.10), palette.accent.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [palette.accent.opacity(model.isDark ? 0.16 : 0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
        }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            searchField
            Button {
                model.onShowMenu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("More options")
            .accessibilityLabel("More options")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary)
            TextField("Search copied text", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focusEffectDisabled()
                .accessibilityLabel("Search clipboard history")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
    }

    private func controls(_ palette: ShelfPalette) -> some View {
        HStack(spacing: 8) {
            FilterPicker(selection: $model.filter, accent: palette.accent)
            Spacer(minLength: 8)
            Circle()
                .fill(model.recordingPaused ? ShelfStyle.paused : palette.accent)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(model.recordingPaused ? "Paused" : "Saving new copies")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func list(_ palette: ShelfPalette) -> some View {
        let pinned = model.pinned
        let recent = model.recent
        if pinned.isEmpty && recent.isEmpty {
            Text(model.emptyMessage)
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                // Redraws now and then so "Copied 8 minutes ago" stays true while the shelf is open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !pinned.isEmpty {
                            SectionTitle(title: "PINNED", count: pinned.count)
                            ForEach(pinned) { entry in
                                row(entry, now: context.date, palette: palette)
                            }
                        }
                        if !recent.isEmpty {
                            SectionTitle(title: "RECENT", count: recent.count)
                                .padding(.top, pinned.isEmpty ? 0 : 8)
                            ForEach(recent) { entry in
                                row(entry, now: context.date, palette: palette)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ entry: ClipboardEntry, now: Date, palette: ShelfPalette) -> some View {
        EntryRow(
            entry: entry,
            now: now,
            palette: palette,
            showSourceIcon: model.preferences.showSourceIcons,
            copy: { model.onCopy(entry) },
            togglePin: { model.onTogglePin(entry) }
        )
    }

    /// Shown only while Sparkle has an update waiting for the user; choosing it opens the install dialog.
    private func updateRow(_ version: String, _ palette: ShelfPalette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Version \(version) is ready")
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Install…") {
                model.onCheckForUpdates()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.accent.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.accent.opacity(0.45), lineWidth: 0.75))
    }

    private func footer(_ palette: ShelfPalette) -> some View {
        let recentCount = model.history.recentEntries.count
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 0.5)
            HStack {
                pausePill
                Spacer(minLength: 8)
                Text(ClipboardSummaryText.counts(recent: recentCount, pinned: model.history.pinnedEntries.count))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Clear recent") {
                    model.onClearRecent()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(recentCount > 0 ? palette.accent : Color.secondary)
                .disabled(recentCount == 0)
                .help("Remove unpinned clipboard items")
            }
            .padding(.horizontal, 4)
            .frame(height: 44)
        }
    }

    private var pausePill: some View {
        Button {
            model.onSetPaused(!model.recordingPaused)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.recordingPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.recordingPaused ? "Resume" : "Pause")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(model.recordingPaused ? "Resume saving new copies" : "Pause saving new copies")
        .accessibilityLabel(model.recordingPaused ? "Recording paused; click to resume" : "Pause clipboard recording")
    }
}

/// One copied item: the app it came from (or a text or link icon), its text and time, a copy
/// button while the pointer is over it, and the pin.
struct EntryRow: View {
    let entry: ClipboardEntry
    let now: Date
    let palette: ShelfPalette
    let showSourceIcon: Bool
    let copy: () -> Void
    let togglePin: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var source: SourceAppInfo? {
        guard showSourceIcon, let identifier = entry.sourceApp else { return nil }
        return SourceAppResolver.shared.info(for: identifier)
    }

    var body: some View {
        let sourceInfo = source
        let subtitle = entry.isPinned
            ? ClipboardTimeText.pinned(entry.createdAt, now: now, app: sourceInfo?.name)
            : ClipboardTimeText.copied(entry.createdAt, now: now, app: sourceInfo?.name)
        let pinKind: SquareButton.Kind = entry.isPinned ? .pinned : (hovering ? .onAccent : .quiet)
        let restingFill = colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.70)
        return HStack(spacing: 11) {
            leadingIcon(sourceInfo)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text.replacingOccurrences(of: "\n", with: "  "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(hovering ? Color.white : Color.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(hovering ? Color.white.opacity(0.82) : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep its space when hidden, so hovering cannot rewrap the snippet or move a pin.
            SquareButton(systemImage: "doc.on.doc", kind: .onAccent, palette: palette, help: "Copy", action: copy)
                .opacity(hovering ? 1 : 0)
                .disabled(!hovering)
                .allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
                .accessibilityLabel("Copy clipboard item")
            SquareButton(
                systemImage: entry.isPinned ? "pin.fill" : "pin",
                kind: pinKind,
                palette: palette,
                help: entry.isPinned ? "Unpin" : "Pin",
                action: togglePin
            )
            .accessibilityLabel(entry.isPinned ? "Unpin clipboard item" : "Pin clipboard item")
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering ? palette.accent : restingFill)
                .shadow(color: hovering ? palette.accent.opacity(0.40) : Color.clear, radius: 7, y: 3)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(perform: copy)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Copy", copy)
        .help("Click to copy")
    }

    @ViewBuilder
    private func leadingIcon(_ sourceInfo: SourceAppInfo?) -> some View {
        if let sourceInfo {
            Image(nsImage: sourceInfo.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        } else {
            Image(systemName: entry.looksLikeLink ? "link" : "text.alignleft")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : palette.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.22) : palette.accent.opacity(0.18))
                )
                .accessibilityHidden(true)
        }
    }
}

/// "PINNED  2", "RECENT  4".
struct SectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .tracking(1.2)
            Text("\(count)")
                .opacity(0.7)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .padding(.leading, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// All / Pinned, with the chosen one filled in the skin's accent.
struct FilterPicker: View {
    @Binding var selection: ShelfFilter
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            segment("All", .all)
            segment("Pinned", .pinned)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
    }

    private func segment(_ title: String, _ value: ShelfFilter) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 64, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The square pin and copy buttons: quiet, gold-coloured for a pinned item, or light on the
/// accent-coloured row under the pointer.
struct SquareButton: View {
    enum Kind {
        case quiet
        case pinned
        case onAccent
    }

    let systemImage: String
    let kind: Kind
    let palette: ShelfPalette
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(glyph)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var glyph: Color {
        switch kind {
        case .quiet: return Color.secondary
        case .pinned: return ShelfStyle.pinInk
        case .onAccent: return Color.white
        }
    }

    private var fill: Color {
        switch kind {
        case .quiet: return Color.clear
        case .pinned: return palette.pin
        case .onAccent: return Color.white.opacity(0.22)
        }
    }
}

/// Hosts the shelf in the menu-bar popover and passes its actions to the app.
@MainActor
final class ClipboardShelfViewController: NSViewController {
    weak var delegate: ClipboardShelfViewControllerDelegate?
    private let model = ShelfModel()

    override func loadView() {
        let hosting = NSHostingView(rootView: ShelfView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: ShelfStyle.width, height: ShelfStyle.height)
        view = hosting
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: ShelfStyle.width, height: ShelfStyle.height)
        model.onCopy = { [weak self] entry in
            guard let self else { return }
            self.delegate?.clipboardShelfViewController(self, copy: entry)
        }
        model.onTogglePin = { [weak self] entry in
            guard let self else { return }
            self.delegate?.clipboardShelfViewController(self, togglePin: entry)
        }
        model.onSetPaused = { [weak self] paused in
            guard let self else { return }
            self.delegate?.clipboardShelfViewController(self, setRecordingPaused: paused)
        }
        model.onClearRecent = { [weak self] in
            guard let self else { return }
            self.delegate?.clipboardShelfViewControllerClearRecent(self)
        }
        model.onShowMenu = { [weak self] in
            self?.showMoreMenu()
        }
        model.onCheckForUpdates = { [weak self] in
            guard let self else { return }
            self.delegate?.clipboardShelfViewControllerCheckForUpdates(self)
        }
    }

    func setUpdates(_ updates: UpdateController) {
        model.updates = updates
    }

    func update(history: ClipboardHistory, recordingPaused: Bool) {
        model.history = history
        model.recordingPaused = recordingPaused
    }

    func update(preferences: ShelfPreferences, isDark: Bool) {
        model.preferences = preferences
        model.isDark = isDark
    }

    func updateRecordingPaused(_ paused: Bool) {
        model.recordingPaused = paused
    }

    /// The ⋯ menu: how many recent items to keep, pause, clear, the look, updates and quit.
    private func showMoreMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let privacy = NSMenuItem(title: "Saved only on this Mac", action: nil, keyEquivalent: "")
        privacy.isEnabled = false
        menu.addItem(privacy)
        menu.addItem(.separator())

        let keepTitle = NSMenuItem(title: "Keep up to", action: nil, keyEquivalent: "")
        keepTitle.isEnabled = false
        menu.addItem(keepTitle)
        for limit in ClipboardHistory.recentLimitOptions {
            let item = NSMenuItem(title: "\(limit) recent items", action: #selector(recentLimitChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = limit
            item.indentationLevel = 1
            item.state = model.history.maxRecentItems == limit ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: model.recordingPaused ? "Resume Saving New Copies" : "Pause Saving New Copies",
            action: #selector(togglePausedChosen),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear Recent…", action: #selector(clearRecentChosen), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !model.history.recentEntries.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())

        menu.addItem(skinMenuItem())
        menu.addItem(appearanceMenuItem())
        let sourceIcons = NSMenuItem(title: "Show Source App Icons", action: #selector(toggleSourceIconsChosen), keyEquivalent: "")
        sourceIcons.target = self
        sourceIcons.state = model.preferences.showSourceIcons ? .on : .off
        menu.addItem(sourceIcons)
        menu.addItem(.separator())

        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesChosen), keyEquivalent: "")
        check.target = self
        check.isEnabled = model.updates?.canCheckForUpdates ?? false
        menu.addItem(check)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Clipboard Shelf", action: #selector(quitChosen), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// "Skin" with one coloured dot per skin.
    private func skinMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Skin", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Skin")
        submenu.autoenablesItems = false
        for skin in ShelfSkin.allCases {
            let choice = NSMenuItem(title: skin.title, action: #selector(skinChosen(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = skin.rawValue
            choice.state = model.preferences.skin == skin ? .on : .off
            let configuration = NSImage.SymbolConfiguration(paletteColors: [skin.accent.nsColor])
            choice.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: skin.title)?
                .withSymbolConfiguration(configuration)
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    /// "Appearance": Automatic, Light or Dark.
    private func appearanceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Appearance")
        submenu.autoenablesItems = false
        for mode in ShelfAppearance.allCases {
            let choice = NSMenuItem(title: mode.title, action: #selector(appearanceChosen(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = mode.rawValue
            choice.state = model.preferences.appearance == mode ? .on : .off
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    @objc private func skinChosen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        delegate?.clipboardShelfViewController(self, setSkin: ShelfSkin.from(stored: name))
    }

    @objc private func appearanceChosen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        delegate?.clipboardShelfViewController(self, setAppearance: ShelfAppearance.from(stored: name))
    }

    @objc private func toggleSourceIconsChosen() {
        delegate?.clipboardShelfViewController(self, setShowSourceIcons: !model.preferences.showSourceIcons)
    }

    @objc private func recentLimitChosen(_ sender: NSMenuItem) {
        delegate?.clipboardShelfViewController(self, setRecentLimit: sender.tag)
    }

    @objc private func togglePausedChosen() {
        delegate?.clipboardShelfViewController(self, setRecordingPaused: !model.recordingPaused)
    }

    @objc private func clearRecentChosen() {
        delegate?.clipboardShelfViewControllerClearRecent(self)
    }

    @objc private func checkForUpdatesChosen() {
        delegate?.clipboardShelfViewControllerCheckForUpdates(self)
    }

    @objc private func quitChosen() {
        delegate?.clipboardShelfViewControllerQuit(self)
    }
}
