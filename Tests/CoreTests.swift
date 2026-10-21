import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}

private func testRecordingIgnoresBlankTextAndDeduplicates() {
    var history = ClipboardHistory(maxRecentItems: 20)
    let firstDate = Date(timeIntervalSince1970: 100)
    let secondDate = Date(timeIntervalSince1970: 200)

    history.record("   ", at: firstDate)
    expect(history.entries.isEmpty, "blank clipboard values should be ignored")

    history.record("Alpha", at: firstDate)
    history.record("Beta", at: secondDate)
    history.record("Alpha", at: secondDate)

    expect(history.entries.map(\.text) == ["Alpha", "Beta"], "a duplicate should move to the top instead of creating a second row")
    expect(history.entries.first?.createdAt == secondDate, "a repeated item should receive the newest timestamp")
}

private func testRecentLimitDoesNotEvictPinnedItems() {
    var history = ClipboardHistory(maxRecentItems: 2)
    history.record("Pinned", at: Date(timeIntervalSince1970: 1))
    let pinnedID = history.entries[0].id
    history.togglePin(id: pinnedID)

    history.record("One", at: Date(timeIntervalSince1970: 2))
    history.record("Two", at: Date(timeIntervalSince1970: 3))
    history.record("Three", at: Date(timeIntervalSince1970: 4))

    expect(history.entries.contains(where: { $0.id == pinnedID && $0.isPinned }), "pinned entries should be protected from eviction")
    expect(history.entries.filter { !$0.isPinned }.map(\.text) == ["Three", "Two"], "only the newest configured number of recent items should remain")
}

private func testSearchIsCaseInsensitiveAndPinFirst() {
    var history = ClipboardHistory(maxRecentItems: 20)
    history.record("Project ALPHA", at: Date(timeIntervalSince1970: 1))
    history.record("beta notes", at: Date(timeIntervalSince1970: 2))
    history.record("alpha checklist", at: Date(timeIntervalSince1970: 3))
    let projectID = history.entries.first(where: { $0.text == "Project ALPHA" })!.id
    history.togglePin(id: projectID)

    let results = history.filteredEntries(matching: "alpha")
    expect(results.map(\.text) == ["Project ALPHA", "alpha checklist"], "search should ignore case and show pinned matches first")
}

private func testSensitiveClipboardSourcesAreSkipped() {
    for type in ClipboardPrivacy.skipTypes {
        expect(
            ClipboardPrivacy.shouldSkip(types: [type], frontmostBundleIdentifier: nil),
            "pasteboard type \(type) should be skipped"
        )
    }

    expect(
        !ClipboardPrivacy.shouldSkip(types: ["public.utf8-plain-text"], frontmostBundleIdentifier: nil),
        "ordinary text should not be skipped"
    )
    expect(
        ClipboardPrivacy.shouldSkip(
            types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
            frontmostBundleIdentifier: nil
        ),
        "ordinary text with a concealed marker should be skipped"
    )
    expect(
        ClipboardPrivacy.shouldSkip(types: [], frontmostBundleIdentifier: "com.apple.Passwords"),
        "Passwords app copies should be skipped"
    )
    expect(
        ClipboardPrivacy.shouldSkip(types: [], frontmostBundleIdentifier: "com.apple.keychainaccess"),
        "Keychain Access copies should be skipped"
    )
    expect(
        !ClipboardPrivacy.shouldSkip(types: [], frontmostBundleIdentifier: "com.apple.TextEdit"),
        "ordinary app copies should not be skipped by bundle ID"
    )
}

private func testClearRecentKeepsPinsAndArchiveRoundTrips() throws {
    var history = ClipboardHistory(maxRecentItems: 20)
    history.record("Keep me", at: Date(timeIntervalSince1970: 1))
    let pinnedID = history.entries[0].id
    history.togglePin(id: pinnedID)
    history.record("Remove me", at: Date(timeIntervalSince1970: 2))

    history.clearRecent()
    expect(history.entries.map(\.text) == ["Keep me"], "clearing recent history should preserve pinned entries")

    let data = try history.encoded()
    let restored = try ClipboardHistory.decode(data: data, maxRecentItems: 20)
    expect(restored.entries == history.entries, "encoded clipboard history should restore exactly")
}

private func testRecentLimitCanBeChangedAndOnlyOfferedChoicesAreKept() {
    var history = ClipboardHistory(maxRecentItems: 100)
    for index in 1...60 {
        history.record("Item \(index)", at: Date(timeIntervalSince1970: TimeInterval(index)))
    }
    let pinnedID = history.entries.last!.id
    history.togglePin(id: pinnedID)
    expect(history.recentEntries.count == 59, "a 100-item shelf keeps all 59 recent items")

    history.setMaxRecentItems(20)
    expect(history.maxRecentItems == 20, "the limit can be lowered")
    expect(history.recentEntries.count == 20, "lowering the limit keeps only the newest 20 recent items")
    expect(history.recentEntries.first?.text == "Item 60", "the newest recent item stays at the top")
    expect(history.pinnedEntries.map(\.id) == [pinnedID], "pinned items are never removed by the limit")

    expect(ClipboardHistory.recentLimitOptions == [20, 50, 100], "the shelf offers 20, 50 and 100")
    expect(ClipboardHistory.validRecentLimit(50) == 50, "an offered stored limit is used")
    expect(ClipboardHistory.validRecentLimit(0) == 20, "a missing stored limit falls back to 20")
    expect(ClipboardHistory.validRecentLimit(7) == 20, "an unknown stored limit falls back to 20")
}

private func testTimeAndSummaryText() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US")
    let now = Date(timeIntervalSince1970: 1_780_000_000) // a fixed afternoon (UTC)
    func copied(_ secondsAgo: TimeInterval) -> String {
        ClipboardTimeText.copied(now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale)
    }
    expect(copied(5) == "Copied just now", "under a minute reads just now")
    expect(copied(-30) == "Copied just now", "a clock that's slightly ahead reads just now")
    expect(copied(60) == "Copied 1 minute ago", "one minute is singular")
    expect(copied(8 * 60) == "Copied 8 minutes ago", "minutes are counted")
    expect(copied(2 * 3600) == "Copied 2 hours ago", "earlier today counts hours")
    expect(copied(26 * 3600) == "Copied yesterday", "the day before reads yesterday")
    expect(copied(5 * 86400).hasPrefix("Copied ") && !copied(5 * 86400).contains("ago"), "older items show their date")

    func pinned(_ secondsAgo: TimeInterval) -> String {
        ClipboardTimeText.pinned(now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale)
    }
    expect(pinned(600) == "Pinned · Today", "pinned today")
    expect(pinned(26 * 3600) == "Pinned · Yesterday", "pinned yesterday")
    expect(pinned(5 * 86400).hasPrefix("Pinned · ") && pinned(5 * 86400) != "Pinned · Today", "older pins show their date")

    expect(ClipboardSummaryText.counts(recent: 4, pinned: 2) == "4 recent · 2 pinned", "footer counts both")
    expect(ClipboardSummaryText.counts(recent: 4, pinned: 0) == "4 recent", "footer leaves out zero pins")
}

private func testUpdateInstallPolicyWaitsOnlyWhileTheShelfIsOpen() {
    expect(UpdateInstallPolicy.canInstallNow(isBusy: false), "an update installs right away when the shelf is closed")
    expect(!UpdateInstallPolicy.canInstallNow(isBusy: true), "an update waits while the shelf is open")
    expect(UpdateInstallPolicy.retryInterval == 15, "the waiting installer checks every 15 seconds")
}

private func testUpdateSettingsAreInInfoPlist() {
    let plistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Info.plist")
    guard let data = try? Data(contentsOf: plistURL),
          let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
        expect(false, "Resources/Info.plist should be a readable property list")
        return
    }

    expect(info["CFBundleIdentifier"] as? String == "local.clipboardshelf", "the bundle identifier must not change")
    expect(
        info["SUFeedURL"] as? String == "https://github.com/9phfr6dsw4-dotcom/clipboard-shelf/releases/latest/download/appcast.xml",
        "updates should come from the latest GitHub release feed"
    )
    expect(info["SUEnableAutomaticChecks"] as? Bool == true, "automatic checks should be on")
    expect(info["SUAutomaticallyUpdate"] as? Bool == true, "automatic installs should be on")
    expect(info["SUScheduledCheckInterval"] as? Int == 3600, "the feed should be checked hourly")
    expect(info["SURequireSignedFeed"] as? Bool == true, "the feed must be signed")
    expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "updates must be verified before they are unpacked")
    expect(info["SUAllowsAutomaticUpdates"] == nil, "SUAllowsAutomaticUpdates must not be set")
    let publicKey = info["SUPublicEDKey"] as? String ?? ""
    expect(Data(base64Encoded: publicKey)?.count == 32, "SUPublicEDKey should be a base64 Ed25519 public key")
    expect(Int(info["CFBundleVersion"] as? String ?? "") != nil, "Sparkle compares whole-number builds")
}

private func testSourceAppIsRememberedAndOldItemsStillLoad() throws {
    var history = ClipboardHistory(maxRecentItems: 20)
    history.record("From Safari", at: Date(timeIntervalSince1970: 1), sourceApp: "com.apple.Safari")
    history.record("From nowhere", at: Date(timeIntervalSince1970: 2))
    expect(history.entries.first(where: { $0.text == "From Safari" })?.sourceApp == "com.apple.Safari", "a copy remembers the app it came from")
    expect(history.entries.first(where: { $0.text == "From nowhere" })?.sourceApp == nil, "a copy with no known source stays without one")

    history.record("From Safari", at: Date(timeIntervalSince1970: 3))
    expect(
        history.entries.first(where: { $0.text == "From Safari" })?.sourceApp == "com.apple.Safari",
        "copying an item again from the shelf keeps the app it first came from"
    )
    history.record("From Safari", at: Date(timeIntervalSince1970: 4), sourceApp: "com.apple.Notes")
    expect(
        history.entries.first(where: { $0.text == "From Safari" })?.sourceApp == "com.apple.Notes",
        "copying the same text from another app credits the newer app"
    )

    let restored = try ClipboardHistory.decode(data: history.encoded(), maxRecentItems: 20)
    expect(restored.entries == history.entries, "the source app survives saving and loading")

    // History saved by an earlier version has no sourceApp at all.
    let oldJSON = """
    [{"id":"7B1E4E0A-3C54-4A52-9B52-0B7A55E4C0A1","text":"Old item","isPinned":true,"createdAt":700000000}]
    """
    let old = try ClipboardHistory.decode(data: Data(oldJSON.utf8), maxRecentItems: 20)
    expect(old.entries.count == 1 && old.entries[0].text == "Old item", "history from an earlier version still loads")
    expect(old.entries[0].isPinned && old.entries[0].sourceApp == nil, "an older item keeps its pin and has no source app")
}

private func testLinksAreRecognised() {
    expect(ClipboardEntry(text: "https://github.com").looksLikeLink, "a web address is a link")
    expect(ClipboardEntry(text: "  http://example.com/a?b=1  ").looksLikeLink, "spaces around a web address are ignored")
    expect(!ClipboardEntry(text: "see https://github.com now").looksLikeLink, "a sentence with a link in it is text")
    expect(!ClipboardEntry(text: "github.com").looksLikeLink, "a bare domain is text")
    expect(!ClipboardEntry(text: "ftp://example.com").looksLikeLink, "only web addresses count as links")
    expect(!ClipboardEntry(text: "Please send the notes.").looksLikeLink, "plain text is not a link")
}

private func testTimeTextNamesTheSourceApp() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let locale = Locale(identifier: "en_US")
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let eightMinutesAgo = now.addingTimeInterval(-8 * 60)
    expect(
        ClipboardTimeText.copied(eightMinutesAgo, now: now, calendar: calendar, locale: locale, app: "Safari") == "Safari · Copied 8 minutes ago",
        "a recent item names its app before the time"
    )
    expect(
        ClipboardTimeText.pinned(now.addingTimeInterval(-600), now: now, calendar: calendar, locale: locale, app: "Mail") == "Pinned · Mail · Today",
        "a pinned item names its app between Pinned and the day"
    )
    expect(
        ClipboardTimeText.pinned(now.addingTimeInterval(-26 * 3600), now: now, calendar: calendar, locale: locale, app: "Mail") == "Pinned · Mail · Yesterday",
        "a pinned item from yesterday names its app too"
    )
}

private func testSkinsAndLookSettings() {
    expect(ShelfSkin.allCases.count == 6, "there are six skins")
    expect(Set(ShelfSkin.allCases.map { $0.rawValue }).count == 6, "every skin has its own name")
    expect(Set(ShelfSkin.allCases.map { $0.title }).count == 6, "every skin has its own title")
    let accents = ShelfSkin.allCases.map { $0.accent }
    expect(accents.indices.allSatisfy { index in !accents[(index + 1)...].contains(accents[index]) }, "every skin has its own accent colour")
    expect(ShelfSkin.from(stored: nil) == .classic, "no stored skin means Classic")
    expect(ShelfSkin.from(stored: "grape") == .grape, "a stored skin is used")
    expect(ShelfSkin.from(stored: "retired-skin") == .classic, "an unknown stored skin falls back to Classic")
    expect(ShelfAppearance.from(stored: nil) == .auto, "no stored appearance means Automatic")
    expect(ShelfAppearance.from(stored: "dark") == .dark, "a stored appearance is used")
    expect(ShelfAppearance.from(stored: "sepia") == .auto, "an unknown appearance falls back to Automatic")
    expect(ShelfRGB(hex: 0xFF0000) == ShelfRGB(hex: 0xFF0000) && ShelfRGB(hex: 0x14B8A6).green > ShelfRGB(hex: 0x14B8A6).red, "hex colours convert to numbers")

    let suite = "local.clipboardshelf.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        expect(false, "a throwaway preference domain should be available")
        return
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    let fresh = ShelfPreferences.load(from: defaults)
    expect(fresh.skin == .classic && fresh.appearance == .auto, "a fresh install starts with Classic and Automatic")
    expect(fresh.showSourceIcons, "source app icons are on by default")
    expect(fresh.appIconFollowsSkin, "the app icon follows the skin by default")
    expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("ClipboardShelf") }, "loading the settings writes nothing")

    var chosen = fresh
    chosen.skin = .rose
    chosen.appearance = .light
    chosen.showSourceIcons = false
    chosen.appIconFollowsSkin = false
    chosen.save(to: defaults)
    expect(ShelfPreferences.load(from: defaults) == chosen, "the chosen look is remembered")

    // Choosing Lagoon in 1.3.0 or later is kept.
    chosen.skin = .lagoon
    chosen.save(to: defaults)
    expect(ShelfPreferences.load(from: defaults).skin == .lagoon, "Lagoon chosen in 1.3.0 is kept")
}

/// 1.2.0 wrote every look setting at once, including Lagoon, its default, and had no version marker.
private func testOldDefaultSkinMovesToClassic() {
    let suite = "local.clipboardshelf.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        expect(false, "a throwaway preference domain should be available")
        return
    }
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("lagoon", forKey: ShelfPreferences.skinKey)
    defaults.set("dark", forKey: ShelfPreferences.appearanceKey)
    defaults.set(true, forKey: ShelfPreferences.sourceIconsKey)
    let moved = ShelfPreferences.load(from: defaults)
    expect(moved.skin == .classic, "1.2.0's saved Lagoon (the old default) moves to Classic")
    expect(moved.appearance == .dark, "the rest of 1.2.0's settings are kept")
    expect(moved.appIconFollowsSkin, "1.2.0 settings have the app icon following the skin")
    expect(defaults.object(forKey: ShelfPreferences.defaultsVersionKey) == nil, "loading old settings writes nothing")

    defaults.set("sunset", forKey: ShelfPreferences.skinKey)
    expect(ShelfPreferences.load(from: defaults).skin == .sunset, "a skin other than Lagoon chosen in 1.2.0 is kept")
}

private func testFinderIconSkin() {
    var preferences = ShelfPreferences()
    expect(preferences.customIconSkin == nil, "Classic, the default, uses the app's own icon, so no custom icon")
    preferences.skin = .lagoon
    expect(preferences.customIconSkin == .lagoon, "Lagoon shows its own icon in Finder")
    preferences.skin = .grape
    preferences.appIconFollowsSkin = false
    expect(preferences.customIconSkin == nil, "with the switch off the app's own icon stays")
}

@main
struct CoreTestRunner {
    static func main() {
        testRecordingIgnoresBlankTextAndDeduplicates()
        testRecentLimitDoesNotEvictPinnedItems()
        testSearchIsCaseInsensitiveAndPinFirst()
        testSensitiveClipboardSourcesAreSkipped()
        testRecentLimitCanBeChangedAndOnlyOfferedChoicesAreKept()
        testTimeAndSummaryText()
        testUpdateInstallPolicyWaitsOnlyWhileTheShelfIsOpen()
        testUpdateSettingsAreInInfoPlist()
        testLinksAreRecognised()
        testTimeTextNamesTheSourceApp()
        testSkinsAndLookSettings()
        testOldDefaultSkinMovesToClassic()
        testFinderIconSkin()
        do {
            try testSourceAppIsRememberedAndOldItemsStillLoad()
        } catch {
            failures += 1
            fputs("FAIL: source app round trip threw \(error)\n", stderr)
        }
        do {
            try testClearRecentKeepsPinsAndArchiveRoundTrips()
        } catch {
            failures += 1
            fputs("FAIL: archive round trip threw \(error)\n", stderr)
        }

        if failures > 0 {
            fputs("\(failures) core test(s) failed.\n", stderr)
            exit(1)
        }
        print("All Clipboard Shelf core tests passed.")
    }
}
