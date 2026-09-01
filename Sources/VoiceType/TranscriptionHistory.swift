import Foundation

struct HistoryItem: Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    let appName: String?
    let kind: String?

    init(id: UUID = UUID(), text: String, date: Date = Date(), appName: String? = nil, kind: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.appName = appName
        self.kind = kind
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 52 { return trimmed }
        return String(trimmed.prefix(52)) + "…"
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

final class TranscriptionHistory {
    static let shared = TranscriptionHistory()
    private let key = "transcriptionHistory"
    private let maxCount = 500

    private(set) var items: [HistoryItem] = [] {
        didSet {
            save()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    private init() { load() }

    func add(_ text: String, appName: String? = nil, kind: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = HistoryItem(text: trimmed, appName: appName, kind: kind)
        items.insert(item, at: 0)
        if items.count > maxCount { items = Array(items.prefix(maxCount)) }
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() { items = [] }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
            return
        }

        // Migrate the pre-1.1 history shape without losing the user's existing transcripts.
        struct LegacyItem: Codable {
            let id: UUID
            let text: String
            let date: Date
        }
        if let legacy = try? JSONDecoder().decode([LegacyItem].self, from: data) {
            items = legacy.map { HistoryItem(id: $0.id, text: $0.text, date: $0.date) }
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
