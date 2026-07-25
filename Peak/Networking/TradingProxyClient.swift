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
            CrashReporting.capture(error, context: ["path": path, "method": method])
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
            if http.statusCode >= 500 {
                // 4xx here is expected business validation (insufficient funds, market closed, …);
                // a 5xx means the backend itself broke — worth surfacing.
                CrashReporting.capture(
                    TradingError.fromServerMessage(message, code: code),
                    context: ["path": path, "method": method, "status": String(http.statusCode)]
                )
            }
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

    /// HTTP failure that still carries a JSON body (flags like `syncReady` / `builderConfigured`).
    struct HTTPBodyError: Error, LocalizedError {
        let status: Int
        let tradingError: TradingError
        let body: [String: Any]

        var errorDescription: String? { tradingError.errorDescription }
    }

    static func setupTrading() async throws -> [String: Any] {
        try await jsonObjectKeepingBody(path: "trading/setup", method: "POST", jsonBody: [:])
    }

    /// POST/GET that returns JSON on success, or `HTTPBodyError` (with body) on failure.
    static func jsonObjectKeepingBody(
        path: String,
        method: String = "POST",
        jsonBody: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let auth = try await auth()
        let requestURL = auth.base.appendingPathComponent(path)

        var request = URLRequest(url: requestURL)
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
            CrashReporting.capture(error, context: ["path": path, "method": method])
            let friendly = PeakUserCopy.fromError(error, fallback: PeakUserCopy.couldNotConnect)
            throw TradingError.server(friendly)
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message =
                (json["error"] as? String)
                ?? (json["errorMsg"] as? String)
                ?? (json["message"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            let code = json["code"] as? String
            if http.statusCode >= 500 {
                CrashReporting.capture(
                    TradingError.fromServerMessage(message, code: code),
                    context: ["path": path, "method": method, "status": String(http.statusCode)]
                )
            }
            if http.statusCode == 401 || message.lowercased().contains("unauthorized") {
                throw TradingError.notConfigured
            }
            throw HTTPBodyError(
                status: http.statusCode,
                tradingError: TradingError.fromServerMessage(message, code: code),
                body: json
            )
        }
        return json
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

    /// Unauthenticated: derive address from key/seed (for SIWE before Peak login).
    static func resolveSecretAddress(secret: String) async throws -> String {
        let body = Self.secretBody(secret)
        let json = try await publicJSONObject(path: "auth/resolve-secret", method: "POST", jsonBody: body)
        guard let address = json["address"] as? String, Self.isHexAddress(address) else {
            throw TradingError.server("Couldn’t read that wallet. Check the key or seed.")
        }
        return address
    }

    /// Unauthenticated: sign a SIWE message with the imported key (one-shot on server).
    static func signSiwe(secret: String, message: String) async throws -> (address: String, signature: String) {
        var body = Self.secretBody(secret)
        body["message"] = message
        let json = try await publicJSONObject(path: "auth/sign-siwe", method: "POST", jsonBody: body)
        guard
            let address = json["address"] as? String,
            let signature = json["signature"] as? String,
            Self.isHexAddress(address),
            !signature.isEmpty
        else {
            throw TradingError.server("Couldn’t sign in with that wallet. Try again.")
        }
        return (address, signature)
    }

    private static func isHexAddress(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 42, trimmed.lowercased().hasPrefix("0x") else { return false }
        return trimmed.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    private static func secretBody(_ secret: String) -> [String: Any] {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        if wordCount >= 12 {
            return ["mnemonic": trimmed.lowercased()]
        }
        return ["privateKey": trimmed]
    }

    /// POST/GET without Bearer auth (import bootstrap only).
    private static func publicJSONObject(
        path: String,
        method: String,
        jsonBody: [String: Any]
    ) async throws -> [String: Any] {
        let base = await MainActor.run { TradingConfigStore.shared.baseURL }
        guard let base else { throw TradingError.notConfigured }
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradingError.server("Couldn’t connect. Try again.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if !(200..<300).contains(http.statusCode) {
            let message = (json["error"] as? String)
                ?? String(data: data, encoding: .utf8)
                ?? "Request failed"
            throw TradingError.fromServerMessage(message, code: json["code"] as? String)
        }
        return json
    }
}
