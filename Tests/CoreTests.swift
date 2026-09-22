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

@main
struct CoreTestRunner {
    static func main() {
        testRecordingIgnoresBlankTextAndDeduplicates()
        testRecentLimitDoesNotEvictPinnedItems()
        testSearchIsCaseInsensitiveAndPinFirst()
        testSensitiveClipboardSourcesAreSkipped()
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
