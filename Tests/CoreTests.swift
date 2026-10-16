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

@main
struct CoreTestRunner {
    static func main() {
        testRecordingIgnoresBlankTextAndDeduplicates()
        testRecentLimitDoesNotEvictPinnedItems()
        testSearchIsCaseInsensitiveAndPinFirst()
        testSensitiveClipboardSourcesAreSkipped()
        testRecentLimitCanBeChangedAndOnlyOfferedChoicesAreKept()
        testTimeAndSummaryText()
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
