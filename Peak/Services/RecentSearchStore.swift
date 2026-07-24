import Foundation

/// Persists recent search queries (UserDefaults).
@MainActor
final class RecentSearchStore: ObservableObject {
    static let shared = RecentSearchStore()

    private let key = "peak.search.recent"
    private let limit = 8

    @Published private(set) var queries: [String] = []

    init() {
        queries = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func record(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var next = queries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        next.insert(trimmed, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        queries = next
        UserDefaults.standard.set(queries, forKey: key)
    }

    func remove(_ query: String) {
        queries.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        UserDefaults.standard.set(queries, forKey: key)
    }

    func clear() {
        queries = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
