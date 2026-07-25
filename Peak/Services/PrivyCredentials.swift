import Foundation

enum PrivyCredentials {
    /// Prefer gitignored `PrivySecrets.local.plist`; Info.plist is fallback only (keep empty in git).
    static var appID: String {
        nonEmpty(localPlist()?["PRIVY_APP_ID"] as? String)
            ?? string(for: "PRIVY_APP_ID")
            ?? ""
    }

    static var appClientID: String {
        nonEmpty(localPlist()?["PRIVY_APP_CLIENT_ID"] as? String)
            ?? string(for: "PRIVY_APP_CLIENT_ID")
            ?? ""
    }

    static var isConfigured: Bool {
        !appID.isEmpty && !appClientID.isEmpty
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private static func string(for key: String) -> String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    private static func localPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "PrivySecrets.local", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }
}
