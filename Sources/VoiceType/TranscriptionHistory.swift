import Foundation

struct HistoryItem: Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    var preview: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 42 { return t }
        return String(t.prefix(42)) + "…"
    }

    var timeString: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}

final class TranscriptionHistory {
    static let shared = TranscriptionHistory()
    private let key = "transcriptionHistory"
    private let maxCount = 20

    private(set) var items: [HistoryItem] = [] {
        didSet {
            save()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
            }
        }
    }

    private init() { load() }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // avoid immediate duplicates
        if items.first?.text == trimmed { return }
        let item = HistoryItem(id: UUID(), text: trimmed, date: Date())
        items.insert(item, at: 0)
        if items.count > maxCount { items = Array(items.prefix(maxCount)) }
    }

    func clear() {
        items = []
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
