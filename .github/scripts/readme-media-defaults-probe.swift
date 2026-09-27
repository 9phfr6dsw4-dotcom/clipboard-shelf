// CI-only probe for the Clipboard Shelf demo fixture. verify-clipboard-demo-isolation.sh
// bundles it with the app's identifier (local.clipboardshelf) and launches it through
// LaunchServices exactly as the capture launches the app. It reads the two defaults keys
// the way the app does and writes one summary line (counts plus a digest, never clipboard
// text) to the path given as its first argument. It has no UI and never touches the pasteboard.
import CryptoKit
import Foundation

struct ClipboardEntry: Decodable {
    let id: UUID
    let text: String
    let isPinned: Bool
    let createdAt: Date
}

// Must match clipboardDemoSummary in render-readme-media.swift.
func clipboardDemoSummary(paused: Bool, entries: [(text: String, isPinned: Bool)]) -> String {
    let lines = entries.map { "\($0.isPinned ? 1 : 0)\t\($0.text)" }.sorted().joined(separator: "\n")
    let digest = SHA256.hash(data: Data(lines.utf8)).map { String(format: "%02x", $0) }.joined()
    return "paused=\(paused) entries=\(entries.count) pinned=\(entries.filter(\.isPinned).count) sha256=\(digest)"
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { exit(2) }
let defaults = UserDefaults.standard
let paused = defaults.bool(forKey: "ClipboardShelfRecordingPausedV1")
var summary: String
if let data = defaults.data(forKey: "ClipboardShelfHistoryV1") {
    if let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
        summary = clipboardDemoSummary(paused: paused, entries: entries.map { ($0.text, $0.isPinned) })
    } else {
        summary = "paused=\(paused) history=undecodable"
    }
} else {
    summary = "paused=\(paused) history=absent"
}
try (summary + "\n").write(toFile: arguments[1], atomically: true, encoding: .utf8)
