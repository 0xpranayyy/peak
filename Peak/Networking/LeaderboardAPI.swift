import Foundation

/// Read-only client for Polymarket's public trader leaderboard.
///
/// Routed through the same edge proxy as market data (`PeakAPIBase.data`),
/// which forwards `/data/v1/leaderboard` to `data-api.polymarket.com`. In
/// direct mode (no edge configured) `PeakAPIBase.data` is the data-api root,
/// so the same path resolves correctly either way.
///
/// The ranking is Polymarket's own — currently all-time by profit, the same
/// default their site shows. A `window`/`type` toggle isn't exposed yet: the
/// exact parameter names for switching couldn't be confirmed against the
/// (intermittently unreachable) docs, and shipping a toggle that silently
/// returned identical data would be worse than a single honest view.
enum LeaderboardAPI {
    static func fetch(limit: Int = 100) async throws -> [LeaderboardEntry] {
        let url = PeakAPIBase.data
            .appendingPathComponent("v1")
            .appendingPathComponent("leaderboard")
        return try await APIClient.shared.get(
            url,
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }
}
