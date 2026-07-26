import Foundation

/// Whether trading is permitted from the user's region.
///
/// Polymarket geoblocks restricted regions and rejects their orders outright,
/// so without this a user can fill in an amount, tap Buy, wait, and only then
/// be told it was never possible. Polymarket's own developer guidance is to
/// check up front.
///
/// Resolved by the Peak edge Worker (`/geo`) rather than in-app: Polymarket's
/// geoblock endpoint is itself unreachable from the regions that need this
/// check, and the API backend only ever sees its own datacenter IP. Cloudflare
/// terminates the user's connection, so it is the only hop that knows the real
/// client country.
@MainActor
final class TradingRegionStore: ObservableObject {
    static let shared = TradingRegionStore()

    enum Status: String, Codable, Sendable {
        case unknown
        case allowed
        /// Existing positions may be closed, but no new ones opened.
        case closeOnly = "close_only"
        case blocked
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var country: String?

    /// Open new positions.
    var canTrade: Bool { status == .allowed || status == .unknown }
    /// Close existing positions (permitted in close-only regions).
    var canClose: Bool { status != .blocked }

    /// Consumer-facing explanation, or nil when trading is unrestricted.
    var restrictionMessage: String? {
        switch status {
        case .allowed, .unknown:
            return nil
        case .closeOnly:
            return "New positions aren’t available in your region. You can still close positions you already hold."
        case .blocked:
            return "Trading isn’t available in your region. You can still browse markets and track prices."
        }
    }

    private var didLoad = false

    func refreshIfNeeded() async {
        guard !didLoad else { return }
        await refresh()
    }

    func refresh() async {
        guard let edge = PeakAPIBase.edgeRoot else {
            // No edge configured (development): leave unknown so trading stays
            // enabled and the server remains the authority.
            return
        }
        var request = URLRequest(url: edge.appendingPathComponent("geo"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            country = root["country"] as? String
            if let raw = root["status"] as? String, let parsed = Status(rawValue: raw) {
                status = parsed
            }
            didLoad = true
        } catch {
            // Fail open: a flaky lookup must not block a permitted user. The
            // order itself is still checked server-side by CLOB.
        }
    }
}
