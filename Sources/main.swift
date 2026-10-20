import AppKit
import Foundation

@MainActor
protocol ClipboardShelfViewControllerDelegate: AnyObject {
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, copy entry: ClipboardEntry)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, togglePin entry: ClipboardEntry)
    func clipboardShelfViewControllerClearRecent(_ controller: ClipboardShelfViewController)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setRecordingPaused paused: Bool)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setRecentLimit limit: Int)
    func clipboardShelfViewControllerQuit(_ controller: ClipboardShelfViewController)
    func clipboardShelfViewControllerCheckForUpdates(_ controller: ClipboardShelfViewController)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setSkin skin: ShelfSkin)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setAppearance appearance: ShelfAppearance)
    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setShowSourceIcons show: Bool)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardShelfViewControllerDelegate {
    private let defaultsKey = "ClipboardShelfHistoryV1"
    private let pausedKey = "ClipboardShelfRecordingPausedV1"
    private let recentLimitKey = "ClipboardShelfRecentLimitV1"
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var shelfController: ClipboardShelfViewController!
    private var history = ClipboardHistory(maxRecentItems: ClipboardHistory.defaultRecentLimit)
    private var monitorTimer: Timer?
    private var pasteboardChangeCount = 0
    private var isRecordingPaused = false
    private var updates: UpdateController!
    private var preferences = ShelfPreferences.load()

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        history = ClipboardHistory(maxRecentItems: storedRecentLimit)
        loadHistory()
        isRecordingPaused = UserDefaults.standard.bool(forKey: pausedKey)

        shelfController = ClipboardShelfViewController()
        popover = NSPopover()
        shelfController.delegate = self
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
        updates = UpdateController { [weak self] in self?.popover.isShown ?? false }
        shelfController.setUpdates(updates)
        popover.behavior = .transient
        popover.animates = true
        applyPreferences()
        popover.contentSize = NSSize(width: ShelfStyle.width, height: ShelfStyle.height)
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

        updates.start()
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

    /// Whether the shelf draws dark: the Appearance choice, or the Mac's own setting when Automatic.
    private var shelfIsDark: Bool {
        switch preferences.appearance {
        case .dark:
            return true
        case .light:
            return false
        case .auto:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    /// Pushes the skin, the light or dark look and the source-icon switch to the shelf and popover.
    private func applyPreferences() {
        let dark = shelfIsDark
        popover.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        shelfController.update(preferences: preferences, isDark: dark)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
        applyPreferences()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount

        guard !isRecordingPaused else { return }

        let types = Set(pasteboard.types?.map { $0.rawValue } ?? [])
        // The app in front when the copy is noticed is taken as its source (checked twice a second).
        let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if ClipboardPrivacy.shouldSkip(
            types: types,
            frontmostBundleIdentifier: frontmostBundleIdentifier
        ) {
            pasteboardChangeCount = pasteboard.changeCount
            return
        }

        guard let text = pasteboard.string(forType: .string) else { return }

        history.record(text, sourceApp: frontmostBundleIdentifier)
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
        NSApp.activate()
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

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setRecentLimit limit: Int) {
        let limit = ClipboardHistory.validRecentLimit(limit)
        UserDefaults.standard.set(limit, forKey: recentLimitKey)
        history.setMaxRecentItems(limit)
        saveHistory()
        shelfController.update(history: history, recordingPaused: isRecordingPaused)
    }

    func clipboardShelfViewControllerQuit(_ controller: ClipboardShelfViewController) {
        NSApp.terminate(nil)
    }

    func clipboardShelfViewControllerCheckForUpdates(_ controller: ClipboardShelfViewController) {
        popover.performClose(nil)
        updates.checkForUpdates()
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setSkin skin: ShelfSkin) {
        preferences.skin = skin
        preferences.save()
        applyPreferences()
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setAppearance appearance: ShelfAppearance) {
        preferences.appearance = appearance
        preferences.save()
        applyPreferences()
    }

    func clipboardShelfViewController(_ controller: ClipboardShelfViewController, setShowSourceIcons show: Bool) {
        preferences.showSourceIcons = show
        preferences.save()
        applyPreferences()
    }

    /// How many recent items to keep: 20, 50 or 100 (chosen in the ⋯ menu).
    private var storedRecentLimit: Int {
        ClipboardHistory.validRecentLimit(UserDefaults.standard.integer(forKey: recentLimitKey))
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let restored = try? ClipboardHistory.decode(data: data, maxRecentItems: storedRecentLimit) else {
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
    guard let frameworks = Bundle.main.privateFrameworksURL,
          FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("Sparkle.framework").path) else {
        fputs("Self-test failed: Sparkle framework\n", stderr)
        return 1
    }
    guard Bundle.main.url(forResource: "Assets", withExtension: "car") != nil,
          Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon" else {
        fputs("Self-test failed: macOS 26 app icon (Assets.car)\n", stderr)
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
    guard ShelfSkin.allCases.count == 6, ShelfSkin.from(stored: "nonsense") == .lagoon,
          ShelfPreferences().showSourceIcons else {
        fputs("Self-test failed: skins and look defaults\n", stderr)
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
