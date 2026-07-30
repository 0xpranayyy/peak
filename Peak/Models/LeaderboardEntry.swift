import Foundation

/// One trader on Polymarket's public leaderboard.
///
/// This is Polymarket's own computed ranking, read through data-api — Peak
/// mirrors it, never calculates it, so the numbers always match what
/// polymarket.com shows. Read-only: no wallet, no trading, nothing to sign.
struct LeaderboardEntry: Decodable, Identifiable, Hashable {
    let rank: Int
    let proxyWallet: String
    let userName: String
    let xUsername: String
    let verifiedBadge: Bool
    let vol: Double
    let pnl: Double
    let profileImage: String

    var id: String { proxyWallet }

    private enum CodingKeys: String, CodingKey {
        case rank, proxyWallet, userName, xUsername, verifiedBadge, vol, pnl, profileImage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The API returns rank as a string ("1", "2", …). Decode leniently in
        // case that ever changes to a number, and fall back to 0 rather than
        // throwing — one odd row must not fail the whole list.
        if let s = try? c.decode(String.self, forKey: .rank), let n = Int(s) {
            rank = n
        } else {
            rank = (try? c.decode(Int.self, forKey: .rank)) ?? 0
        }
        proxyWallet = (try? c.decode(String.self, forKey: .proxyWallet)) ?? ""
        userName = (try? c.decode(String.self, forKey: .userName)) ?? ""
        xUsername = (try? c.decode(String.self, forKey: .xUsername)) ?? ""
        verifiedBadge = (try? c.decode(Bool.self, forKey: .verifiedBadge)) ?? false
        vol = (try? c.decode(Double.self, forKey: .vol)) ?? 0
        pnl = (try? c.decode(Double.self, forKey: .pnl)) ?? 0
        profileImage = (try? c.decode(String.self, forKey: .profileImage)) ?? ""
    }

    /// Username when it's a real handle, otherwise a shortened wallet.
    ///
    /// Polymarket uses `<wallet>-<timestamp>` as the placeholder username for
    /// traders who never set one; those start with `0x`, so show the tidy
    /// short wallet instead of a 60-character machine string.
    var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespaces)
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

    /// Monogram for the fallback avatar when there's no profile image.
    var monogram: String {
        let name = displayName
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }
}
