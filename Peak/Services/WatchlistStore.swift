import Foundation

/// Local watchlist of event IDs (UserDefaults).
@MainActor
final class WatchlistStore: ObservableObject {
    static let shared = WatchlistStore()

    private let key = "peak.watchlist.eventIDs"

    @Published private(set) var eventIDs: [String] = []

    init() {
        eventIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func contains(_ eventID: String) -> Bool {
        eventIDs.contains(eventID)
    }

    func toggle(_ eventID: String) {
        if contains(eventID) {
            remove(eventID)
        } else {
            add(eventID)
        }
    }

    func add(_ eventID: String) {
        guard !contains(eventID) else { return }
        eventIDs.insert(eventID, at: 0)
        persist()
    }

    func remove(_ eventID: String) {
        eventIDs.removeAll { $0 == eventID }
        persist()
    }

    func move(from offsets: IndexSet, to offset: Int) {
        eventIDs.move(fromOffsets: offsets, toOffset: offset)
        persist()
    }

    func replaceAll(_ ids: [String]) {
        eventIDs = ids
        persist()
    }

    func clearAll() {
        eventIDs = []
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(eventIDs, forKey: key)
    }
}
