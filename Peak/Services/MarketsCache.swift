import Foundation

/// In-memory + disk cache for Markets first paint (stale-while-revalidate).
actor MarketsCache {
    static let shared = MarketsCache()

    struct Page: Sendable {
        let events: [PeakEvent]
        let savedAt: Date
        let canLoadMore: Bool

        var age: TimeInterval { Date().timeIntervalSince(savedAt) }
        var isFresh: Bool { age < 90 }
    }

    private var memory: [String: Page] = [:]
    private let folder: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = base.appendingPathComponent("PeakMarketsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func key(sort: MarketSort, categorySlug: String?) -> String {
        "\(sort.rawValue)|\(categorySlug ?? "all")"
    }

    func page(for key: String) -> Page? {
        if let mem = memory[key] {
            return Self.sanitized(mem)
        }
        guard let disk = loadDisk(key: key) else { return nil }
        let clean = Self.sanitized(disk)
        memory[key] = clean
        return clean
    }

    func store(_ events: [PeakEvent], canLoadMore: Bool, for key: String) {
        let page = Page(events: MarketShowcase.filter(events), savedAt: Date(), canLoadMore: canLoadMore)
        memory[key] = page
        saveDisk(page, key: key)
    }

    func warmTrending() async {
        let key = Self.key(sort: .trending, categorySlug: nil)
        if let existing = page(for: key), existing.isFresh { return }
        do {
            let result = try await GammaAPI.fetchEventsPage(limit: 24, offset: 0, sort: .trending, tagSlug: nil)
            store(result.events, canLoadMore: result.canLoadMore, for: key)
        } catch {
            // Warming is best-effort.
        }
    }

    private static func sanitized(_ page: Page) -> Page {
        let events = MarketShowcase.filter(page.events)
        guard events.count != page.events.count else { return page }
        return Page(events: events, savedAt: page.savedAt, canLoadMore: page.canLoadMore)
    }

    private func diskURL(key: String) -> URL {
        let safe = key.replacingOccurrences(of: "|", with: "_")
        return folder.appendingPathComponent("\(safe).json")
    }

    private func loadDisk(key: String) -> Page? {
        let url = diskURL(key: key)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DiskPayload.self, from: data) else {
            return nil
        }
        // Drop very old disk pages (> 24h).
        guard Date().timeIntervalSince(decoded.savedAt) < 86_400 else { return nil }
        return Page(events: decoded.events, savedAt: decoded.savedAt, canLoadMore: decoded.canLoadMore)
    }

    private func saveDisk(_ page: Page, key: String) {
        let payload = DiskPayload(events: page.events, savedAt: page.savedAt, canLoadMore: page.canLoadMore)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: diskURL(key: key), options: .atomic)
    }

    private struct DiskPayload: Codable {
        let events: [PeakEvent]
        let savedAt: Date
        let canLoadMore: Bool
    }
}
