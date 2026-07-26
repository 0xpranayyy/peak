import Foundation

/// Sentry DSN, read from the gitignored local plist.
///
/// A DSN is not a secret — they are designed to ship inside client binaries —
/// but it lives alongside the other local config so switching Sentry projects
/// (or turning reporting off) does not require touching tracked files. Same
/// pattern as `PrivyCredentials` and `PEAK_EDGE_URL`.
enum SentryConfig {
    static var dsn: String {
        nonEmpty(localPlist()?["SENTRY_DSN"] as? String)
            ?? string(for: "SENTRY_DSN")
            ?? ""
    }

    static var isConfigured: Bool { !dsn.isEmpty }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("$("), !value.hasPrefix("YOUR_") else {
            return nil
        }
        return value
    }

    private static func string(for key: String) -> String? {
        nonEmpty(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    private static func localPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "PrivySecrets.local", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }
}
