import Foundation

/// Shared HTTP helper for the Peak trading proxy.
enum TradingProxyClient {
    struct Auth: Sendable {
        let base: URL
        let token: String
    }

    static func auth() async throws -> Auth {
        let snapshot = await MainActor.run { () -> (URL?, String?) in
            let config = TradingConfigStore.shared
            return (config.baseURL, config.appToken())
        }
        guard let base = snapshot.0, let token = snapshot.1, !token.isEmpty else {
            throw TradingError.notConfigured
        }
        return Auth(base: base, token: token)
    }

    static func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        let auth = try await auth()
        var comps = URLComponents(url: auth.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            comps?.queryItems = (comps?.queryItems ?? []) + query
        }
        guard let url = comps?.url else { throw TradingError.server("Invalid proxy URL") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw TradingError.server(message)
        }
        return data
    }

    static func jsonObject(path: String, method: String = "GET", jsonBody: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try await request(path: path, method: method, jsonBody: jsonBody)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
