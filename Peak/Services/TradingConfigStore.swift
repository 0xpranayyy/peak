import Foundation
import Security

/// Backend URL + optional legacy APP_TOKEN. Prefer Privy access tokens for auth.
@MainActor
final class TradingConfigStore: ObservableObject {
    static let shared = TradingConfigStore()

    private let baseURLKey = "peak.trading.baseURL"
    private let tokenAccount = "peak.trading.appToken"

    @Published private(set) var baseURLString: String = ""
    @Published private(set) var hasToken: Bool = false

    /// Legacy personal-proxy mode (static APP_TOKEN).
    var isLegacyConfigured: Bool {
        guard let url = URL(string: baseURLString), url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        return hasToken
    }

    /// Any usable backend URL (Privy or legacy).
    var hasBackendURL: Bool {
        guard let url = URL(string: baseURLString), url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        return true
    }

    /// Back-compat for existing UI — true when legacy proxy is fully set.
    var isConfigured: Bool { isLegacyConfigured }

    var baseURL: URL? {
        guard hasBackendURL else { return nil }
        return URL(string: baseURLString)
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
        let resolved = Self.resolveBackendURL(stored: stored)
        if resolved != stored {
            if resolved.isEmpty {
                UserDefaults.standard.removeObject(forKey: baseURLKey)
            } else {
                UserDefaults.standard.set(resolved, forKey: baseURLKey)
            }
        }
        baseURLString = resolved
        hasToken = loadToken() != nil
    }

    /// Prefer Info.plist `PEAK_BACKEND_URL`, then DEBUG localhost. Used after login when unset.
    func ensureBackendURLIfNeeded() {
        if hasBackendURL { return }
        let resolved = Self.resolvedDefaultURL()
        guard !resolved.isEmpty else { return }
        saveBackendURL(resolved)
    }

    /// Bundled HTTPS backend from Info.plist `PEAK_BACKEND_URL` (Debug + Release).
    ///
    /// `nonisolated` so the pure predicates below (`isPinnedBackendHost`) can read
    /// it without an actor hop. Reading `Bundle.main`'s info dictionary is a
    /// thread-safe lookup of immutable bundle data.
    nonisolated private static func bundledBackendURL() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PEAK_BACKEND_URL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasPrefix("https://"),
              !isLocalhost(trimmed),
              URL(string: trimmed) != nil else { return nil }
        return trimmed
    }

    private static func debugLocalFallbackURL() -> String {
        "http://127.0.0.1:8080"
    }

    /// Default when nothing useful is saved: plist HTTPS, else DEBUG localhost.
    private static func resolvedDefaultURL() -> String {
        if let bundled = bundledBackendURL() {
            return bundled
        }
        #if DEBUG
        return debugLocalFallbackURL()
        #else
        return ""
        #endif
    }

    /// Precedence: keep intentional non-local overrides; upgrade empty/loopback to plist; DEBUG-only local fallback.
    private static func resolveBackendURL(stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bundled = bundledBackendURL()

        if trimmed.isEmpty {
            return resolvedDefaultURL()
        }

        // Stale simulator/device localhost from earlier testing → production when bundled.
        if isLocalhost(trimmed), let bundled {
            return bundled
        }

        // A previously saved backend host that we've since moved off. Without this
        // an existing install keeps the old URL forever, because it is a perfectly
        // valid non-local HTTPS string and passes every check below.
        if isSupersededBackendHost(trimmed), let bundled {
            return bundled
        }

        #if !DEBUG
        if !isReleaseAllowedBackendURL(trimmed) || !isPinnedBackendHost(trimmed) {
            return bundled ?? ""
        }
        #endif

        guard let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else {
            return resolvedDefaultURL()
        }
        return trimmed
    }

    /// Pure string predicate — nonisolated so it doesn't require actor hops, and
    /// internal (not private) so PeakTests can regression-test it directly.
    nonisolated static func isLocalhost(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else {
            let lower = url.lowercased()
            return lower.contains("127.0.0.1") || lower.contains("localhost")
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Backend hosts we've migrated away from and must not keep using.
    ///
    /// `*.up.railway.app` does not resolve on Indian ISP resolvers, so a saved
    /// value pointing there makes every trading call fail with "Couldn't
    /// connect" while the server itself is healthy. Traffic now goes through
    /// the Cloudflare-fronted `api.` host instead.
    nonisolated static func isSupersededBackendHost(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host.hasSuffix(".up.railway.app")
    }

    /// Release additionally pins to Peak's own hosts.
    ///
    /// `isReleaseAllowedBackendURL` only proves a URL is HTTPS and non-local — any
    /// attacker-controlled HTTPS host passes it. Since this value decides where an
    /// imported private key is POSTed, defence-in-depth says pin it. Anything that
    /// can write our UserDefaults could otherwise redirect key submission.
    nonisolated static func isPinnedBackendHost(_ url: String) -> Bool {
        guard let host = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() else { return false }
        if let bundled = bundledBackendURL(),
           let bundledHost = URL(string: bundled)?.host?.lowercased(),
           host == bundledHost {
            return true
        }
        return host == "peakapp.site" || host.hasSuffix(".peakapp.site")
    }

    /// Release accepts only non-local HTTPS backends.
    /// Pure string predicate — nonisolated so it doesn't require actor hops, and
    /// internal (not private) so PeakTests can regression-test it directly.
    nonisolated static func isReleaseAllowedBackendURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://"), !isLocalhost(trimmed) else { return false }
        return URL(string: trimmed) != nil
    }

    func appToken() -> String? {
        loadToken()
    }

    func save(baseURL: String, appToken: String) {
        let trimmedURL = sanitizeBackendURL(baseURL)
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

    func saveBackendURL(_ baseURL: String) {
        let trimmedURL = sanitizeBackendURL(baseURL)
        baseURLString = trimmedURL
        UserDefaults.standard.set(trimmedURL, forKey: baseURLKey)
        objectWillChange.send()
    }

    /// Release requires HTTPS and rejects localhost; DEBUG may use LAN HTTP.
    private func sanitizeBackendURL(_ baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        #if !DEBUG
        if !Self.isReleaseAllowedBackendURL(trimmed) {
            return Self.bundledBackendURL() ?? ""
        }
        #endif
        return trimmed
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        deleteToken()
        hasToken = false
        // Re-apply bundled / DEBUG default so the app keeps working.
        let resolved = Self.resolvedDefaultURL()
        baseURLString = resolved
        if !resolved.isEmpty {
            UserDefaults.standard.set(resolved, forKey: baseURLKey)
        }
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
