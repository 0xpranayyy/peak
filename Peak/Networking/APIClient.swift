import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        #if DEBUG
        switch self {
        case .invalidURL: return "Invalid URL."
        case .badStatus(let code): return "Server returned status \(code)."
        case .decoding(let error): return "Couldn’t decode response: \(error.localizedDescription)"
        case .emptyResponse: return "Empty response."
        }
        #else
        return "Couldn’t load. Try again."
        #endif
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Generous defaults — Gamma event payloads are large and Phase 6’s 12s cut caused false timeouts.
    static let defaultRequestTimeout: TimeInterval = 40
    static let defaultResourceTimeout: TimeInterval = 90

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Self.defaultRequestTimeout
            config.timeoutIntervalForResource = Self.defaultResourceTimeout
            // Wait briefly for cellular/Wi‑Fi handoff instead of failing instantly.
            config.waitsForConnectivity = true
            // Keep headroom low so Markets bootstrap isn’t starved by digest/enrich storms.
            config.httpMaximumConnectionsPerHost = 6
            config.requestCachePolicy = .useProtocolCachePolicy
            config.urlCache = URLCache(
                memoryCapacity: 25 * 1024 * 1024,
                diskCapacity: 120 * 1024 * 1024,
                diskPath: "peak-url-cache"
            )
            self.session = URLSession(configuration: config)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter.peakFractional.date(from: raw)
                ?? ISO8601DateFormatter.peak.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
        }
        self.decoder = decoder
    }

    func get<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.defaultRequestTimeout,
        as type: T.Type = T.self
    ) async throws -> T {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.cachePolicy = .useProtocolCachePolicy

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func getData(
        _ url: URL,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.defaultRequestTimeout
    ) async throws -> Data {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.cachePolicy = .useProtocolCachePolicy
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    /// Bypass HTTP cache for pull-to-refresh / forced updates.
    func getFresh<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.defaultRequestTimeout,
        as type: T.Type = T.self
    ) async throws -> T {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Retry transient transport failures (timeout / DNS / connect) with exponential backoff.
    func getRetrying<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.defaultRequestTimeout,
        attempts: Int = 3,
        forceFresh: Bool = false,
        as type: T.Type = T.self
    ) async throws -> T {
        var lastError: Error?
        let tries = max(1, attempts)
        for attempt in 0..<tries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 0.45 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
            do {
                if forceFresh {
                    return try await getFresh(url, query: query, timeout: timeout, as: type)
                }
                return try await get(url, query: query, timeout: timeout, as: type)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if !Self.isTransientTransport(error) || attempt == tries - 1 {
                    throw error
                }
            }
        }
        throw lastError ?? APIError.emptyResponse
    }

    func getDataRetrying(
        _ url: URL,
        query: [URLQueryItem] = [],
        timeout: TimeInterval = APIClient.defaultRequestTimeout,
        attempts: Int = 3
    ) async throws -> Data {
        var lastError: Error?
        let tries = max(1, attempts)
        for attempt in 0..<tries {
            if attempt > 0 {
                let delay = UInt64(pow(2.0, Double(attempt - 1)) * 0.45 * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
            do {
                return try await getData(url, query: query, timeout: timeout)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if !Self.isTransientTransport(error) || attempt == tries - 1 {
                    throw error
                }
            }
        }
        throw lastError ?? APIError.emptyResponse
    }

    nonisolated static func isTransientTransport(_ error: Error) -> Bool {
        let code: URLError.Code?
        if let urlError = error as? URLError {
            code = urlError.code
        } else {
            let ns = error as NSError
            guard ns.domain == NSURLErrorDomain else { return false }
            code = URLError.Code(rawValue: ns.code)
        }
        guard let code else { return false }
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func makeURL(_ url: URL, query: [URLQueryItem]) throws -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            var items = comps?.queryItems ?? []
            items.append(contentsOf: query)
            comps?.queryItems = items
        }
        guard let final = comps?.url else { throw APIError.invalidURL }
        return final
    }
}

extension ISO8601DateFormatter {
    static let peak: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let peakFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum PeakAPIBase {
    static let gammaDirect = URL(string: "https://gamma-api.polymarket.com")!
    static let clobDirect = URL(string: "https://clob.polymarket.com")!
    static let dataDirect = URL(string: "https://data-api.polymarket.com")!
    static let leaderboardDirect = URL(string: "https://lb-api.polymarket.com")!
    static let marketWebSocketDirect = URL(string: "wss://ws-subscriptions-clob.polymarket.com/ws/market")!

    /// Peak edge proxy (`worker/`) from Info.plist `PEAK_EDGE_URL`.
    ///
    /// Some ISPs — every Indian one we've tested — block `*.polymarket.com` at
    /// both the DNS layer and the TLS layer (SNI-based DPI kills the handshake).
    /// A device that names polymarket.com in an SNI simply cannot connect, so
    /// when this is set we route every read through it and never touch the
    /// Polymarket hosts directly. Unset (dev on an open network) keeps direct.
    static let edgeRoot: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PEAK_EDGE_URL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasPrefix("https://"),
              !trimmed.hasPrefix("$("),
              let base = URL(string: trimmed) else { return nil }
        return base
    }()

    /// True when reads go through the edge — callers must not attempt a direct
    /// host first, since a blocked handshake burns the full timeout every time.
    static var isEdgeRouted: Bool { edgeRoot != nil }

    /// Legacy Gamma read proxy on the Peak backend (`/gamma`). Superseded by
    /// `edgeRoot`; still used as the fallback when no edge is configured.
    static var gammaProxyRoot: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PEAK_BACKEND_URL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasPrefix("https://"),
              let base = URL(string: trimmed) else { return nil }
        return base.appendingPathComponent("gamma")
    }

    static var gamma: URL { edgeRoot?.appendingPathComponent("gamma") ?? gammaDirect }
    static var clob: URL { edgeRoot?.appendingPathComponent("clob") ?? clobDirect }
    static var data: URL { edgeRoot?.appendingPathComponent("data") ?? dataDirect }
    static var leaderboard: URL { edgeRoot?.appendingPathComponent("lb") ?? leaderboardDirect }

    /// `https://edge.example.com` → `wss://edge.example.com/ws/market`.
    static var marketWebSocket: URL {
        guard let edgeRoot,
              var comps = URLComponents(url: edgeRoot, resolvingAgainstBaseURL: false) else {
            return marketWebSocketDirect
        }
        comps.scheme = "wss"
        comps.path = (comps.path.isEmpty ? "" : comps.path) + "/ws/market"
        return comps.url ?? marketWebSocketDirect
    }
}
