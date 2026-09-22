import AppKit
import Foundation

@MainActor
protocol ClipboardShelfViewControllerDelegate: AnyObject {
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, copy entry: ClipboardEntry)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, togglePin entry: ClipboardEntry)
    func clipboardShelfViewControllerClearRecent(_ controller: ClipboardShelfViewController)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setRecordingPaused paused: Bool)
    func clipboardShelfViewControllerQuit(_ controller: ClipboardShelfViewController)
}

@MainActor
final class ClipboardEntryCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ClipboardEntryCellView")

    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    let pinButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9

        primaryLabel.translatesAutoresizingMaskIntoConstraints = false
        primaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.maximumNumberOfLines = 2
        primaryLabel.cell?.wraps = true
        primaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 10.5)
        secondaryLabel.textColor = .secondaryLabelColor
        secondaryLabel.lineBreakMode = .byTruncatingTail

        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.isBordered = false
        pinButton.bezelStyle = .inline
        pinButton.imagePosition = .imageOnly
        pinButton.toolTip = "Pin or unpin this clipboard item"
        pinButton.setAccessibilityLabel("Pin clipboard item")

        addSubview(primaryLabel)
        addSubview(secondaryLabel)
        addSubview(pinButton)

        NSLayoutConstraint.activate([
            primaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            primaryLabel.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -8),
            primaryLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            secondaryLabel.leadingAnchor.constraint(equalTo: primaryLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: primaryLabel.trailingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: primaryLabel.bottomAnchor, constant: 4),
            secondaryLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 25),
            pinButton.heightAnchor.constraint(equalToConstant: 25)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with entry: ClipboardEntry, row: Int, target: AnyObject, pinAction: Selector) {
        primaryLabel.stringValue = entry.text.replacingOccurrences(of: "\n", with: "  ")
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(entry.createdAt) ? .none : .short
        let time = formatter.string(from: entry.createdAt)
        secondaryLabel.stringValue = entry.isPinned ? "Pinned • \(time)" : "Copied \(time)"

        pinButton.tag = row
        pinButton.target = target
        pinButton.action = pinAction
        pinButton.image = NSImage(
            systemSymbolName: entry.isPinned ? "pin.fill" : "pin",
            accessibilityDescription: entry.isPinned ? "Unpin" : "Pin"
        )
        pinButton.contentTintColor = entry.isPinned ? .systemOrange : .secondaryLabelColor
        pinButton.setAccessibilityLabel(entry.isPinned ? "Unpin clipboard item" : "Pin clipboard item")
    }
}

@MainActor
final class ClipboardShelfViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    weak var delegate: ClipboardShelfViewControllerDelegate?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Copy some text to begin")
    private let pauseButton = NSButton(checkboxWithTitle: "Pause recording", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear Recent", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private var history = ClipboardHistory()
    private var displayedEntries: [ClipboardEntry] = []
    private var isRecordingPaused = false

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        view = background
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 430, height: 500)

        let titleLabel = NSTextField(labelWithString: "Clipboard Shelf")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let privacyLabel = NSTextField(labelWithString: "Saved only on this Mac")
        privacyLabel.font = .systemFont(ofSize: 10.5)
        privacyLabel.textColor = .secondaryLabelColor
        privacyLabel.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search copied text"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel("Search clipboard history")

        pauseButton.controlSize = .small
        pauseButton.target = self
        pauseButton.action = #selector(pauseRecordingClicked)
        pauseButton.setAccessibilityLabel("Pause clipboard recording")
        pauseButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .inline
        clearButton.controlSize = .small
        clearButton.target = self
        clearButton.action = #selector(clearRecentClicked)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.toolTip = "Remove unpinned clipboard items"

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ClipboardItems"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 66
        tableView.intercellSpacing = NSSize(width: 0, height: 5)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableRowClicked)
        tableView.doubleAction = #selector(tableRowClicked)
        tableView.setAccessibilityLabel("Clipboard history")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 10.5)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        quitButton.bezelStyle = .inline
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        for subview in [titleLabel, privacyLabel, pauseButton, searchField, clearButton, scrollView, emptyLabel, countLabel, quitButton] {
            view.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),

            privacyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            privacyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            pauseButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pauseButton.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: 8),

            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: pauseButton.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -9),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            countLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -13),

            quitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            quitButton.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor)
        ])

        refreshDisplayedEntries()
    }

    func update(history: ClipboardHistory, recordingPaused: Bool) {
        self.history = history
        updateRecordingPaused(recordingPaused)
        refreshDisplayedEntries()
    }

    func updateRecordingPaused(_ paused: Bool) {
        isRecordingPaused = paused
        pauseButton.state = paused ? .on : .off
        pauseButton.title = paused ? "Recording paused — click to resume" : "Pause recording"
        pauseButton.contentTintColor = paused ? .systemOrange : .controlAccentColor
        pauseButton.setAccessibilityLabel(paused ? "Recording paused; click to resume" : "Pause clipboard recording")
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: ClipboardEntryCellView.identifier, owner: self) as? ClipboardEntryCellView)
            ?? ClipboardEntryCellView(frame: .zero)
        cell.identifier = ClipboardEntryCellView.identifier
        cell.configure(with: displayedEntries[row], row: row, target: self, pinAction: #selector(pinClicked(_:)))
        return cell
    }

    func controlTextDidChange(_ notification: Notification) {
        refreshDisplayedEntries()
    }

    @objc private func tableRowClicked() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard displayedEntries.indices.contains(row) else { return }
        delegate?.clipboardShelfViewController(self, copy: displayedEntries[row])
    }

    @objc private func pinClicked(_ sender: NSButton) {
        guard displayedEntries.indices.contains(sender.tag) else { return }
        delegate?.clipboardShelfViewController(self, togglePin: displayedEntries[sender.tag])
    }

    @objc private func pauseRecordingClicked() {
        delegate?.clipboardShelfViewController(self, setRecordingPaused: pauseButton.state == .on)
    }

    @objc private func clearRecentClicked() {
        delegate?.clipboardShelfViewControllerClearRecent(self)
    }

    @objc private func quitClicked() {
        delegate?.clipboardShelfViewControllerQuit(self)
    }

    private func refreshDisplayedEntries() {
        guard isViewLoaded else { return }
        displayedEntries = history.filteredEntries(matching: searchField.stringValue)
        tableView.reloadData()
        emptyLabel.stringValue = searchField.stringValue.isEmpty ? "Copy some text to begin" : "No matching clipboard items"
        emptyLabel.isHidden = !displayedEntries.isEmpty

        let pinnedCount = history.entries.filter(\.isPinned).count
        let recentCount = history.entries.count - pinnedCount
        var parts = ["\(recentCount) recent"]
        if pinnedCount > 0 { parts.append("\(pinnedCount) pinned") }
        countLabel.stringValue = parts.joined(separator: " • ")
        clearButton.isEnabled = recentCount > 0
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardShelfViewControllerDelegate {
    private let defaultsKey = "ClipboardShelfHistoryV1"
    private let pausedKey = "ClipboardShelfRecordingPausedV1"
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var shelfController: ClipboardShelfViewController!
    private var history = ClipboardHistory(maxRecentItems: 20)
    private var monitorTimer: Timer?
    private var pasteboardChangeCount = 0
    private var isRecordingPaused = false

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadHistory()
        isRecordingPaused = UserDefaults.standard.bool(forKey: pausedKey)

        shelfController = ClipboardShelfViewController()
        popover = NSPopover()
        shelfController.delegate = self
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 430, height: 500)
        popover.contentViewController = shelfController

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItemAppearance()

        let pasteboard = NSPasteboard.general
        pasteboardChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.5, target: self, selector: #selector(checkPasteboard), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitorTimer?.invalidate()
        saveHistory()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        let imageName = isRecordingPaused ? "pause.circle.fill" : "clipboard"
        let description = isRecordingPaused ? "Clipboard Shelf — recording paused" : "Clipboard Shelf"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.toolTip = description
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount

        guard !isRecordingPaused else { return }

        let types = Set(pasteboard.types?.map { $0.rawValue } ?? [])
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if ClipboardPrivacy.shouldSkip(
            types: types,
            frontmostBundleIdentifier: frontmostBundleIdentifier
        ) {
            pasteboardChangeCount = pasteboard.changeCount
            return
        }

        guard let text = pasteboard.string(forType: .string) else { return }

        history.record(text)
        saveHistory()
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, copy entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount

        history.record(entry.text)
        saveHistory()
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
        popover.performClose(nil)
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, togglePin entry: ClipboardEntry) {
        history.togglePin(id: entry.id)
        saveHistory()
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
    }

    func clipboardShelfViewControllerClearRecent(_ controller: ClipboardShelfViewController) {
        guard history.entries.contains(where: { !$0.isPinned }) else { return }

        let alert = NSAlert()
        alert.messageText = "Clear recent clipboard items?"
        alert.informativeText = "Pinned items will stay on your shelf."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear Recent")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        history.clearRecent()
        saveHistory()
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setRecordingPaused paused: Bool) {
        isRecordingPaused = paused
        UserDefaults.standard.set(paused, forKey: pausedKey)
        updateStatusItemAppearance()
        shelfController.updateRecordingPaused(paused)
    }

    func clipboardShelfViewControllerQuit(_ controller: ClipboardShelfViewController) {
        NSApp.terminate(nil)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let restored = try? ClipboardHistory.decode(data: data, maxRecentItems: 20) else {
            return
        }
        history = restored
    }

    private func saveHistory() {
        guard let data = try? history.encoded() else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

private func runSelfTest() -> Int32 {
    var history = ClipboardHistory(maxRecentItems: 2)
    history.record("One")
    history.record("Two")
    history.record("Three")
    guard history.entries.map(\.text) == ["Three", "Two"] else {
        fputs("Self-test failed: clipboard history limit\n", stderr)
        return 1
    }
    guard Bundle.main.bundleIdentifier == "local.clipboardshelf" else {
        fputs("Self-test failed: bundle identifier\n", stderr)
        return 1
    }
    guard Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil else {
        fputs("Self-test failed: app icon resource\n", stderr)
        return 1
    }
    guard ClipboardPrivacy.shouldSkip(
        types: ["org.nspasteboard.ConcealedType"],
        frontmostBundleIdentifier: nil
    ) else {
        fputs("Self-test failed: concealed pasteboard type\n", stderr)
        return 1
    }
    guard ClipboardPrivacy.shouldSkip(
        types: [],
        frontmostBundleIdentifier: "com.apple.Passwords"
    ) && ClipboardPrivacy.shouldSkip(
        types: [],
        frontmostBundleIdentifier: "com.apple.keychainaccess"
    ) else {
        fputs("Self-test failed: password app bundle identifiers\n", stderr)
        return 1
    }
    print("Clipboard Shelf bundle self-test passed.")
    return 0
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
