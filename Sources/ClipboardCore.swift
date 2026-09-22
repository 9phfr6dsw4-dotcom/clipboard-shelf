import Foundation

struct ClipboardEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var isPinned: Bool
    var createdAt: Date

    init(id: UUID = UUID(), text: String, isPinned: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

struct ClipboardHistory: Equatable {
    private(set) var entries: [ClipboardEntry]
    private let maxRecentItems: Int

    init(entries: [ClipboardEntry] = [], maxRecentItems: Int = 20) {
        self.maxRecentItems = max(1, maxRecentItems)
        self.entries = entries
        normalize()
    }

    mutating func record(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let index = entries.firstIndex(where: { $0.text == text }) {
            var existing = entries.remove(at: index)
            existing.createdAt = date
            entries.append(existing)
        } else {
            entries.append(ClipboardEntry(text: text, createdAt: date))
        }
        normalize()
    }

    mutating func togglePin(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        normalize()
    }

    mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    mutating func clearRecent() {
        entries.removeAll { !$0.isPinned }
        normalize()
    }

    func filteredEntries(matching query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(entries)
    }

    static func decode(data: Data, maxRecentItems: Int = 20) throws -> ClipboardHistory {
        let decoded = try JSONDecoder().decode([ClipboardEntry].self, from: data)
        return ClipboardHistory(entries: decoded, maxRecentItems: maxRecentItems)
    }

    private mutating func normalize() {
        var seenTexts = Set<String>()
        entries = entries.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned && !rhs.element.isPinned
                }
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt > rhs.element.createdAt
                }
                return lhs.offset > rhs.offset
            }
            .map(\.element)
            .filter { seenTexts.insert($0.text).inserted }

        let pinned = entries.filter(\.isPinned)
        let recent = entries.filter { !$0.isPinned }.prefix(maxRecentItems)
        entries = pinned + recent
    }
}
