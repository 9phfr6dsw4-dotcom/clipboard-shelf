import AppKit
import Observation
import SwiftUI

/// A quiet petrol-teal surface with the proportions of the design reference.
enum ShelfStyle {
    static let width: CGFloat = 400
    static let height: CGFloat = 600

    static let panelTop = Color(red: 0.035, green: 0.190, blue: 0.245)
    static let panelBottom = Color(red: 0.016, green: 0.110, blue: 0.153)
    static let mint = Color(red: 0.384, green: 0.890, blue: 0.788)
    static let gold = Color(red: 0.965, green: 0.694, blue: 0.204)
    static let paused = Color(red: 0.980, green: 0.620, blue: 0.250)
    /// Dark text and symbols on mint or gold.
    static let ink = Color(red: 0.047, green: 0.133, blue: 0.153)
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.48)
    static let stroke = Color.white.opacity(0.12)
    static let cardFill = Color.white.opacity(0.028)
}

enum ShelfFilter {
    case all
    case pinned
}

/// What the shelf shows, and what its controls ask the app to do.
@MainActor
@Observable
final class ShelfModel {
    var history = ClipboardHistory()
    var recordingPaused = false
    var query = ""
    var filter: ShelfFilter = .all

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

/// The popover's content: header, search, All/Pinned with the saving switch, the pinned and
/// recent items, and the footer.
struct ShelfView: View {
    @Bindable var model: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            searchField
                .padding(.bottom, 10)
            controls
                .padding(.bottom, 14)
            if let version = model.updates?.updateWaiting {
                updateRow(version)
                    .padding(.bottom, 14)
            }
            list
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: ShelfStyle.width, height: ShelfStyle.height, alignment: .top)
        .background {
            LinearGradient(
                colors: [ShelfStyle.panelTop, ShelfStyle.panelBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [ShelfStyle.mint.opacity(0.045), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 360
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard Shelf")
                    .font(.system(size: 18.5, weight: .semibold))
                    .foregroundStyle(ShelfStyle.primaryText)
                Text("Saved only on this Mac")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ShelfStyle.secondaryText)
            }
            Spacer(minLength: 8)
            CircleButton(systemImage: "ellipsis", help: "More options") { model.onShowMenu() }
                .accessibilityLabel("More options")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ShelfStyle.secondaryText)
            TextField("Search copied text", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(ShelfStyle.primaryText)
                .focusEffectDisabled()
                .accessibilityLabel("Search clipboard history")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ShelfStyle.secondaryText)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShelfStyle.stroke, lineWidth: 0.75))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            FilterPicker(selection: $model.filter)
            Spacer(minLength: 8)
            Circle()
                .fill(model.recordingPaused ? ShelfStyle.paused : ShelfStyle.mint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(model.recordingPaused ? "Paused" : "Saving new copies")
                .font(.system(size: 12))
                .foregroundStyle(ShelfStyle.secondaryText)
                .lineLimit(1)
            CircleButton(
                systemImage: model.recordingPaused ? "play.fill" : "pause.fill",
                help: model.recordingPaused ? "Resume saving new copies" : "Pause saving new copies"
            ) {
                model.onSetPaused(!model.recordingPaused)
            }
            .accessibilityLabel(model.recordingPaused ? "Recording paused; click to resume" : "Pause clipboard recording")
        }
    }

    @ViewBuilder
    private var list: some View {
        let pinned = model.pinned
        let recent = model.recent
        if pinned.isEmpty && recent.isEmpty {
            Text(model.emptyMessage)
                .font(.system(size: 14))
                .foregroundStyle(ShelfStyle.tertiaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                // Redraws now and then so "Copied 8 minutes ago" stays true while the shelf is open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !pinned.isEmpty {
                            SectionTitle(title: "PINNED", count: pinned.count)
                            ForEach(pinned) { entry in
                                row(entry, now: context.date)
                            }
                        }
                        if !recent.isEmpty {
                            SectionTitle(title: "RECENT", count: recent.count)
                                .padding(.top, pinned.isEmpty ? 0 : 8)
                            ForEach(recent) { entry in
                                row(entry, now: context.date)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ entry: ClipboardEntry, now: Date) -> some View {
        EntryRow(
            entry: entry,
            now: now,
            copy: { model.onCopy(entry) },
            togglePin: { model.onTogglePin(entry) }
        )
    }

    /// Shown only while Sparkle has an update waiting for the user; choosing it opens the install dialog.
    private func updateRow(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(ShelfStyle.mint)
                .accessibilityHidden(true)
            Text("Version \(version) is ready")
                .font(.system(size: 12.5))
                .foregroundStyle(ShelfStyle.primaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Install…") {
                model.onCheckForUpdates()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(ShelfStyle.mint)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(ShelfStyle.mint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShelfStyle.mint.opacity(0.4), lineWidth: 0.75))
    }

    private var footer: some View {
        let recentCount = model.history.recentEntries.count
        return VStack(spacing: 9) {
            Rectangle()
                .fill(ShelfStyle.stroke)
                .frame(height: 0.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClipboardSummaryText.counts(recent: recentCount, pinned: model.history.pinnedEntries.count))
                        .font(.system(size: 12))
                        .foregroundStyle(ShelfStyle.secondaryText)
                    Text("Click an item to copy it")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ShelfStyle.tertiaryText)
                }
                Spacer()
                Button("Clear recent") {
                    model.onClearRecent()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(recentCount > 0 ? ShelfStyle.mint : ShelfStyle.tertiaryText)
                .disabled(recentCount == 0)
                .help("Remove unpinned clipboard items")
            }
        }
    }
}

/// One copied item: its text and time, a copy button while the pointer is over it, and the pin.
struct EntryRow: View {
    let entry: ClipboardEntry
    let now: Date
    let copy: () -> Void
    let togglePin: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text.replacingOccurrences(of: "\n", with: "  "))
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(ShelfStyle.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(entry.isPinned
                     ? ClipboardTimeText.pinned(entry.createdAt, now: now)
                     : ClipboardTimeText.copied(entry.createdAt, now: now))
                    .font(.system(size: 11.5))
                    .foregroundStyle(ShelfStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep its space when hidden, so hovering cannot rewrap the snippet or move a pin.
            SquareButton(systemImage: "doc.on.doc", kind: .outline, help: "Copy", action: copy)
                .opacity(hovering ? 1 : 0)
                .disabled(!hovering)
                .allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
                .accessibilityLabel("Copy clipboard item")
            SquareButton(
                systemImage: entry.isPinned ? "pin.fill" : "pin",
                kind: entry.isPinned ? .gold : .outline,
                help: entry.isPinned ? "Unpin" : "Pin",
                action: togglePin
            )
            .accessibilityLabel(entry.isPinned ? "Unpin clipboard item" : "Pin clipboard item")
        }
        .padding(.leading, 13)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? ShelfStyle.mint.opacity(0.10) : ShelfStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(hovering ? ShelfStyle.mint.opacity(0.55) : ShelfStyle.stroke, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture(perform: copy)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Copy", copy)
        .help("Click to copy")
    }
}

/// "PINNED  2", "RECENT  4".
struct SectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .tracking(1.3)
            Text("\(count)")
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(ShelfStyle.secondaryText)
        .padding(.leading, 4)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// All / Pinned, with the chosen one filled in mint.
struct FilterPicker: View {
    @Binding var selection: ShelfFilter

    var body: some View {
        HStack(spacing: 0) {
            segment("All", .all)
            segment("Pinned", .pinned)
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ShelfStyle.stroke, lineWidth: 0.75))
    }

    private func segment(_ title: String, _ value: ShelfFilter) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? ShelfStyle.ink : ShelfStyle.primaryText)
                .frame(width: 60, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? ShelfStyle.mint : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The round ⋯ and pause buttons.
struct CircleButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ShelfStyle.primaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.035)))
                .overlay(Circle().strokeBorder(ShelfStyle.stroke, lineWidth: 0.75))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The square pin and copy buttons: outlined, or gold for a pinned item.
struct SquareButton: View {
    enum Kind {
        case outline
        case gold
    }

    let systemImage: String
    let kind: Kind
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(kind == .gold ? ShelfStyle.ink : ShelfStyle.primaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(kind == .gold ? ShelfStyle.gold : Color.white.opacity(0.025))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(kind == .gold ? Color.clear : Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
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

    func updateRecordingPaused(_ paused: Bool) {
        model.recordingPaused = paused
    }

    /// The ⋯ menu: how many recent items to keep, pause, clear and quit.
    private func showMoreMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

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
