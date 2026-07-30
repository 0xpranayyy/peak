import Foundation

/// Read-only client for Polymarket's public trader leaderboard.
///
/// Routed through the edge proxy (`PeakAPIBase.leaderboard` → `/lb/*`), which
/// forwards to `lb-api.polymarket.com/{profit,volume}?window=…` — the exact
/// host and shape behind polymarket.com/leaderboard, so the numbers match the
/// official site. In direct mode (no edge) the same paths resolve against the
/// lb-api root.
enum LeaderboardAPI {
    enum Metric: String, CaseIterable, Identifiable {
        case profit
        case volume
        var id: String { rawValue }
        var title: String { self == .profit ? "Profit" : "Volume" }
    }

    /// The API accepts `1d` / `7d` / `30d` / `all` — word forms (`month`) 400.
    enum Window: String, CaseIterable, Identifiable {
        case day = "1d"
        case week = "7d"
        case month = "30d"
        case all = "all"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return "1D"
            case .week: return "1W"
            case .month: return "1M"
            case .all: return "All"
            }
        }
    }

    /// `.month` + `.profit` is Polymarket's own default board.
    static func fetch(
        metric: Metric,
        window: Window,
        limit: Int = 50
    ) async throws -> [LeaderboardEntry] {
        let url = PeakAPIBase.leaderboard.appendingPathComponent(metric.rawValue)
        var entries: [LeaderboardEntry] = try await APIClient.shared.get(
            url,
            query: [
                URLQueryItem(name: "window", value: window.rawValue),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        // The payload is pre-sorted but carries no rank field.
        for i in entries.indices { entries[i].rank = i + 1 }
        return entries
    }
}
