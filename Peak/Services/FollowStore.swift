import Foundation

/// Local list of followed Polymarket wallet addresses.
@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    private let key = "peak.social.followedWallets"

    @Published private(set) var addresses: [String] = []

    init() {
        addresses = (UserDefaults.standard.stringArray(forKey: key) ?? []).map { $0.lowercased() }
    }

    func contains(_ address: String) -> Bool {
        addresses.contains(normalize(address))
    }

    func toggle(_ address: String) {
        if contains(address) {
            unfollow(address)
        } else {
            follow(address)
        }
    }

    func follow(_ address: String) {
        let value = normalize(address)
        guard value.hasPrefix("0x"), value.count == 42 else { return }
        guard !contains(value) else { return }
        addresses.insert(value, at: 0)
        persist()
    }

    func unfollow(_ address: String) {
        let value = normalize(address)
        addresses.removeAll { $0 == value }
        persist()
    }

    private func normalize(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persist() {
        UserDefaults.standard.set(addresses, forKey: key)
    }
}
