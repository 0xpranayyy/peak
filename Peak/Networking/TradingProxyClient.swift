import Foundation

/// Shared HTTP helper for the Peak trading backend (Privy JWT or legacy APP_TOKEN).
enum TradingProxyClient {
    struct Auth: Sendable {
        let base: URL
        let token: String
        let mode: Mode
    }

    enum Mode: String, Sendable {
        case privy
        case legacy
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    static func auth() async throws -> Auth {
        let snapshot = await MainActor.run { () -> (URL?, String?, Bool) in
            let config = TradingConfigStore.shared
            let privyReady = PrivyAuthService.shared.isAuthenticated
            return (config.baseURL, config.appToken(), privyReady)
        }

        guard let base = snapshot.0 else {
            throw TradingError.notConfigured
        }

        if snapshot.2 {
            let token = try await PrivyAuthService.shared.accessToken()
            return Auth(base: base, token: token, mode: .privy)
        }

        guard let token = snapshot.1, !token.isEmpty else {
            throw TradingError.notConfigured
        }
        return Auth(base: base, token: token, mode: .legacy)
    }

    static func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        let auth = try await auth()
        guard var components = URLComponents(
            url: auth.base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw TradingError.server("Couldn’t connect. Try again.")
        }
        if !query.isEmpty {
            var items = components.queryItems ?? []
            items.append(contentsOf: query)
            components.queryItems = items
        }
        guard let url = components.url else { throw TradingError.server("Couldn’t connect. Try again.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        if auth.mode == .privy {
            request.setValue("privy", forHTTPHeaderField: "X-Peak-Auth")
        }
        request.timeoutInterval = 45
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let friendly = PeakUserCopy.fromError(error, fallback: PeakUserCopy.couldNotConnect)
            throw TradingError.server(friendly)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let message =
                (json["error"] as? String)
                ?? (json["errorMsg"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            let code = json["code"] as? String
            if http.statusCode == 401 || message.lowercased().contains("unauthorized") {
                throw TradingError.notConfigured
            }
            throw TradingError.fromServerMessage(message, code: code)
        }
        return data
    }

    static func jsonObject(path: String, method: String = "GET", jsonBody: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try await request(path: path, method: method, jsonBody: jsonBody)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Establish / refresh Privy trading session on the backend.
    static func syncPrivySession(
        eoa: String,
        path: String? = nil,
        accountWallet: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = ["eoa": eoa]
        if let path { body["path"] = path }
        if let accountWallet { body["accountWallet"] = accountWallet }
        return try await jsonObject(
            path: "auth/session",
            method: "POST",
            jsonBody: body
        )
    }

    static func resolveTradingAccount(
        eoa: String? = nil,
        path: String? = nil,
        accountWallet: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [:]
        if let eoa { body["eoa"] = eoa }
        if let path { body["path"] = path }
        if let accountWallet { body["accountWallet"] = accountWallet }
        return try await jsonObject(
            path: "trading/resolve",
            method: "POST",
            jsonBody: body
        )
    }

    static func setupTrading() async throws -> [String: Any] {
        try await jsonObject(path: "trading/setup", method: "POST", jsonBody: [:])
    }

    /// Import private key or mnemonic via backend (not stored on device).
    /// Do not log `secret`. Cleared by the caller after submit.
    static func importWallet(secret: String) async throws -> [String: Any] {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let body: [String: Any]
        if wordCount >= 12 {
            body = ["mnemonic": trimmed.lowercased()]
        } else {
            body = ["privateKey": trimmed]
        }
        return try await jsonObject(
            path: "auth/import-wallet",
            method: "POST",
            jsonBody: body
        )
    }
}
