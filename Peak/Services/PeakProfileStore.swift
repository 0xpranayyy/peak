import Foundation

/// Public identity resolved from Polymarket Gamma (and later Peak overrides).
struct PeakUserProfile: Equatable, Codable, Sendable {
    var address: String
    var name: String?
    var pseudonym: String?
    var profileImageURL: URL?
    var displayUsernamePublic: Bool
    var verifiedBadge: Bool
    var bio: String?
    var xUsername: String?
    var proxyWallet: String?

    var hasIdentity: Bool {
        name != nil || pseudonym != nil || profileImageURL != nil
    }

    /// Prefer public username, then pseudonym, then truncated wallet.
    var displayName: String {
        if displayUsernamePublic, let name, !name.isEmpty {
            return name
        }
        if let pseudonym, !pseudonym.isEmpty {
            return pseudonym
        }
        if let name, !name.isEmpty {
            return name
        }
        return Self.shortAddress(address)
    }

    var truncatedAddress: String {
        Self.shortAddress(address)
    }

    static func shortAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    static func fromServer(_ dict: [String: Any]?, address: String) -> PeakUserProfile? {
        guard let dict else { return nil }
        let name = string(dict["name"])
        let pseudonym = string(dict["pseudonym"])
        let imageRaw = string(dict["profileImage"])
        let imageURL = imageRaw.flatMap(URL.init(string:))
        let proxy = string(dict["proxyWallet"])
        let bio = string(dict["bio"])
        let xUsername = string(dict["xUsername"])
        let displayPublic = (dict["displayUsernamePublic"] as? Bool) ?? true
        let verified = (dict["verifiedBadge"] as? Bool) ?? false

        let profile = PeakUserProfile(
            address: address,
            name: name,
            pseudonym: pseudonym,
            profileImageURL: imageURL,
            displayUsernamePublic: displayPublic,
            verifiedBadge: verified,
            bio: bio,
            xUsername: xUsername,
            proxyWallet: proxy
        )
        return profile.hasIdentity ? profile : nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Loads + caches Polymarket public profile for the signed-in / viewed wallet.
@MainActor
final class PeakProfileStore: ObservableObject {
    static let shared = PeakProfileStore()

    @Published private(set) var profile: PeakUserProfile?
    @Published private(set) var isLoading = false

    private let cacheKey = "peak.profile.cache.v1"
    private var lastFetchKey: String?
    private var inFlight: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(PeakUserProfile.self, from: data) {
            profile = cached
        }
    }

    /// Best label for UI: profile display name, else truncated wallet / email fallback.
    func displayName(fallbackAddress: String?, email: String? = nil) -> String {
        if let profile, profile.hasIdentity {
            return profile.displayName
        }
        if let email, !email.isEmpty {
            return email
        }
        if let fallbackAddress, WalletStore.isValidAddress(fallbackAddress) {
            return PeakUserProfile.shortAddress(fallbackAddress)
        }
        return "Account"
    }

    func clear() {
        inFlight?.cancel()
        inFlight = nil
        lastFetchKey = nil
        profile = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    /// Apply profile payload from `/auth/session` (or similar) without waiting on Gamma.
    func apply(serverProfile: Any?, address: String?) {
        guard let address, WalletStore.isValidAddress(address) else { return }
        let dict = serverProfile as? [String: Any]
        if let next = PeakUserProfile.fromServer(dict, address: address) {
            profile = next
            persist(next)
        }
    }

    /// Resolve identity for signer and optional proxy / funder wallets.
    func refresh(primary: String?, secondary: String? = nil, force: Bool = false) {
        var candidates: [String] = []
        for raw in [primary, secondary] {
            guard let raw, WalletStore.isValidAddress(raw) else { continue }
            let key = raw.lowercased()
            if !candidates.contains(where: { $0.lowercased() == key }) {
                candidates.append(raw)
            }
        }
        guard !candidates.isEmpty else { return }

        let fetchKey = candidates.map { $0.lowercased() }.joined(separator: "|")
        if !force, fetchKey == lastFetchKey, profile != nil { return }

        inFlight?.cancel()
        inFlight = Task { [weak self] in
            guard let self else { return }
            await self.load(candidates: candidates, fetchKey: fetchKey)
        }
    }

    private func load(candidates: [String], fetchKey: String) async {
        isLoading = true
        defer { isLoading = false }

        for address in candidates {
            if Task.isCancelled { return }
            do {
                if let next = try await GammaAPI.fetchPublicProfile(address: address), next.hasIdentity {
                    profile = next
                    persist(next)
                    lastFetchKey = fetchKey
                    return
                }
            } catch {
                // Try next candidate; keep any cached profile.
            }
        }
        lastFetchKey = fetchKey
    }

    private func persist(_ profile: PeakUserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
