import Foundation

struct TraderSummary: Identifiable, Hashable, Sendable {
    var id: String { address.lowercased() }
    let address: String
    let displayName: String
    let rank: String?
    let volume: Double?
    let pnl: Double?
    let profileImageURL: URL?
    let xUsername: String?
    let verified: Bool
}

struct TraderProfile: Hashable, Sendable {
    let address: String
    let name: String?
    let pseudonym: String?
    let bio: String?
    let profileImageURL: URL?
    let xUsername: String?
    let verified: Bool

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let pseudonym, !pseudonym.isEmpty { return pseudonym }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

enum LeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "DAY"
    case week = "WEEK"
    case month = "MONTH"
    case all = "ALL"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .all: return "All"
        }
    }
}

enum SocialAPI {
    struct LeaderboardDTO: Decodable {
        let rank: String?
        let proxyWallet: String?
        let userName: String?
        let vol: Double?
        let pnl: Double?
        let profileImage: String?
        let xUsername: String?
        let verifiedBadge: Bool?

        func asTrader() -> TraderSummary? {
            guard let address = proxyWallet, address.hasPrefix("0x") else { return nil }
            return TraderSummary(
                address: address.lowercased(),
                displayName: (userName?.isEmpty == false ? userName! : "\(address.prefix(6))…\(address.suffix(4))"),
                rank: rank,
                volume: vol,
                pnl: pnl,
                profileImageURL: profileImage.flatMap(URL.init(string:)),
                xUsername: xUsername,
                verified: verifiedBadge ?? false
            )
        }
    }

    struct ProfileDTO: Decodable {
        let name: String?
        let pseudonym: String?
        let bio: String?
        let profileImage: String?
        let profileImageOptimized: String?
        let xUsername: String?
        let verifiedBadge: Bool?
        let proxyWallet: String?
        let address: String?
    }

    static func fetchLeaderboard(
        period: LeaderboardPeriod = .day,
        orderBy: String = "PNL",
        limit: Int = 25
    ) async throws -> [TraderSummary] {
        let url = PeakAPIBase.data
            .appendingPathComponent("v1")
            .appendingPathComponent("leaderboard")
        let rows: [LeaderboardDTO] = try await APIClient.shared.get(
            url,
            query: [
                .init(name: "category", value: "OVERALL"),
                .init(name: "timePeriod", value: period.rawValue),
                .init(name: "orderBy", value: orderBy),
                .init(name: "limit", value: String(min(50, max(1, limit)))),
            ]
        )
        return rows.compactMap { $0.asTrader() }
    }

    static func fetchProfile(address: String) async throws -> TraderProfile {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let url = PeakAPIBase.gamma.appendingPathComponent("public-profile")
        do {
            let dto: ProfileDTO = try await APIClient.shared.get(
                url,
                query: [.init(name: "address", value: normalized)]
            )
            return TraderProfile(
                address: dto.proxyWallet ?? dto.address ?? normalized,
                name: dto.name,
                pseudonym: dto.pseudonym,
                bio: dto.bio,
                profileImageURL: (dto.profileImageOptimized ?? dto.profileImage).flatMap(URL.init(string:)),
                xUsername: dto.xUsername,
                verified: dto.verifiedBadge ?? false
            )
        } catch {
            // Profile endpoint may 404 for unknown wallets — still allow following by address.
            return TraderProfile(
                address: normalized,
                name: nil,
                pseudonym: nil,
                bio: nil,
                profileImageURL: nil,
                xUsername: nil,
                verified: false
            )
        }
    }
}
