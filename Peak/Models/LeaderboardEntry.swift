import Foundation

/// One trader on Polymarket's public leaderboard.
///
/// From `lb-api.polymarket.com` — the exact host behind
/// polymarket.com/leaderboard — so the ranking and figures match the official
/// site line-for-line. Peak mirrors it, never computes it. Read-only: no
/// wallet, no trading, nothing to sign.
///
/// `amount` is whichever metric the board was fetched for — profit (may be
/// negative in principle) or volume. The API returns rows already sorted; it
/// carries no `rank` field, so rank is assigned from list order after fetch.
struct LeaderboardEntry: Decodable, Identifiable, Hashable {
    var rank: Int = 0
    let proxyWallet: String
    let amount: Double
    let pseudonym: String
    let name: String
    let profileImage: String

    var id: String { proxyWallet }

    private enum CodingKeys: String, CodingKey {
        case proxyWallet, amount, pseudonym, name, profileImage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient: one malformed field must not drop the whole row. `rank` is
        // intentionally not decoded — it's set from list order after fetch.
        proxyWallet = (try? c.decode(String.self, forKey: .proxyWallet)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        pseudonym = (try? c.decode(String.self, forKey: .pseudonym)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        profileImage = (try? c.decode(String.self, forKey: .profileImage)) ?? ""
    }

    /// Real handle when there is one, otherwise a tidy short wallet.
    ///
    /// Traders who never set a name get `<wallet>-<timestamp>` as their
    /// pseudonym; those start with `0x`, so show the short wallet instead of a
    /// 60-character machine string.
    var displayName: String {
        let candidate = pseudonym.isEmpty ? name : pseudonym
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.lowercased().hasPrefix("0x") {
            return shortWallet
        }
        return trimmed
    }

    var shortWallet: String {
        guard proxyWallet.count > 10 else { return proxyWallet }
        return "\(proxyWallet.prefix(6))…\(proxyWallet.suffix(4))"
    }

    var profileImageURL: URL? {
        profileImage.isEmpty ? nil : URL(string: profileImage)
    }

    /// Monogram for the fallback avatar.
    var monogram: String {
        guard let first = displayName.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }
}
