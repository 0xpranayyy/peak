import Foundation
import Security

/// Config for the Peak trading proxy. Secrets stay in Keychain; private keys never enter the app.
@MainActor
final class TradingConfigStore: ObservableObject {
    static let shared = TradingConfigStore()

    private let baseURLKey = "peak.trading.baseURL"
    private let tokenAccount = "peak.trading.appToken"

    @Published private(set) var baseURLString: String = ""
    @Published private(set) var hasToken: Bool = false

    var isConfigured: Bool {
        guard let url = URL(string: baseURLString), url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        return hasToken
    }

    var baseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: baseURLString)
    }

    init() {
        baseURLString = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
        hasToken = loadToken() != nil
    }

    func appToken() -> String? {
        loadToken()
    }

    func save(baseURL: String, appToken: String) {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        baseURLString = trimmedURL
        UserDefaults.standard.set(trimmedURL, forKey: baseURLKey)
        if trimmedToken.isEmpty {
            deleteToken()
            hasToken = false
        } else {
            saveToken(trimmedToken)
            hasToken = true
        }
        objectWillChange.send()
    }

    func clear() {
        baseURLString = ""
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        deleteToken()
        hasToken = false
        objectWillChange.send()
    }

    // MARK: - Keychain

    private func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrService as String: "com.pranay.peak.trading",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrService as String: "com.pranay.peak.trading",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrService as String: "com.pranay.peak.trading",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
