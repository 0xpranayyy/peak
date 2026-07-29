import Foundation

/// Referral code, cosmetic points balance, and the invite-link handoff.
///
/// Points here have no redeemable value — see the Terms. This is purely a
/// client for the three /referral/* endpoints; all the actual rules (no
/// self-referral, no double-redeem, awarding only on a real first trade)
/// live server-side in referralStore.mjs, which is the one place they can
/// be enforced honestly.
@MainActor
final class ReferralStore: ObservableObject {
    static let shared = ReferralStore()

    @Published private(set) var code: String?
    @Published private(set) var balance: Int = 0
    @Published private(set) var history: [Entry] = []

    struct Entry: Identifiable, Equatable {
        var id: String { "\(createdAt.timeIntervalSince1970)-\(reason)-\(delta)" }
        let delta: Int
        let reason: String
        let createdAt: Date
    }

    /// A tappable invite link may open the app before the user has signed
    /// in — onboarding, a fresh install, anything. The code has to survive
    /// that gap, so it's held here rather than redeemed on the spot.
    private let pendingCodeKey = "peak.referral.pendingCode"
    private var pendingCode: String? {
        get { UserDefaults.standard.string(forKey: pendingCodeKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingCodeKey) }
    }

    /// `true` once redemption has been resolved one way or another this
    /// launch, so a Settings screen can show something more useful than a
    /// perpetual spinner while a code is still pending sign-in.
    @Published private(set) var pendingRedeemCode: String?

    init() {
        pendingRedeemCode = pendingCode
    }

    /// Whether `url` was a Peak invite link — true regardless of whether
    /// redemption goes on to succeed. Call from `.onOpenURL`.
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard url.host == "peakapp.site" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "invite", !parts[1].isEmpty else { return false }
        pendingCode = parts[1]
        pendingRedeemCode = parts[1]
        Task { await redeemPendingIfPossible() }
        return true
    }

    /// Safe to call anytime — a no-op with nothing pending. Called after the
    /// link opens the app, and again once sign-in completes, since those are
    /// the two moments redemption can newly become possible.
    func redeemPendingIfPossible() async {
        guard let code = pendingCode else { return }
        switch await redeem(code: code) {
        case .success:
            pendingCode = nil
            pendingRedeemCode = nil
            await refreshPoints()
        case .rejected:
            // A definitive no — the code is wrong, already used, or theirs.
            // Retrying changes nothing, so stop holding onto it.
            pendingCode = nil
            pendingRedeemCode = nil
        case .notSignedIn, .networkFailure:
            // Keep it. redeemPendingIfPossible() runs again once auth is
            // ready or the app is reopened.
            break
        }
    }

    enum RedeemOutcome {
        case success
        case rejected(message: String)
        case notSignedIn
        case networkFailure
    }

    /// Explicit redemption for a manually-typed code (as opposed to one
    /// carried by a link) — same server call, but the caller gets the
    /// specific outcome to show the user directly.
    @discardableResult
    func redeem(code: String) async -> RedeemOutcome {
        do {
            let auth = try await TradingProxyClient.auth()
            var request = URLRequest(url: auth.base.appendingPathComponent("referral/redeem"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if auth.mode == .privy { request.setValue("privy", forHTTPHeaderField: "X-Peak-Auth") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkFailure }

            if (200..<300).contains(http.statusCode) { return .success }
            if http.statusCode == 401 { return .notSignedIn }
            if http.statusCode == 400 {
                let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
                let message = (json["error"] as? String) ?? "That code didn't work. Check it and try again."
                return .rejected(message: message)
            }
            return .networkFailure
        } catch {
            return .networkFailure
        }
    }

    func fetchCode() async {
        guard let json = try? await get("referral/code") else { return }
        code = json["code"] as? String
    }

    func refreshPoints() async {
        guard let json = try? await get("referral/points") else { return }
        balance = json["balance"] as? Int ?? 0
        let rows = json["history"] as? [[String: Any]] ?? []
        history = rows.compactMap { row in
            guard
                let delta = row["delta"] as? Int,
                let reason = row["reason"] as? String,
                let createdAtMs = row["created_at"] as? Double
            else { return nil }
            return Entry(delta: delta, reason: reason, createdAt: Date(timeIntervalSince1970: createdAtMs / 1000))
        }
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let auth = try await TradingProxyClient.auth()
        var request = URLRequest(url: auth.base.appendingPathComponent(path))
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if auth.mode == .privy { request.setValue("privy", forHTTPHeaderField: "X-Peak-Auth") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
