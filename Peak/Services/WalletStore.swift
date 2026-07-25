import Foundation
import Security

/// Persists a read-only wallet address in the Keychain for portfolio lookups.
@MainActor
final class WalletStore: ObservableObject {
    static let shared = WalletStore()

    private let service = "com.pranay.peak.wallet"
    private let account = "portfolio-wallet"

    @Published private(set) var address: String?

    init() {
        address = Self.load(service: service, account: account)
    }

    func save(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        // Setup/import saves the same address repeatedly — skip Keychain + @Published churn.
        if address?.lowercased() == trimmed.lowercased() {
            return
        }
        Self.save(trimmed, service: service, account: account)
        address = trimmed
    }

    func clear() {
        Self.delete(service: service, account: account)
        address = nil
    }

    var isValid: Bool {
        Self.isValidAddress(address)
    }

    static func isValidAddress(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("0x"), lower.count == 42 else { return false }
        let hex = lower.dropFirst(2)
        return hex.allSatisfy { $0.isHexDigit }
    }

    // MARK: - Keychain

    private static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
