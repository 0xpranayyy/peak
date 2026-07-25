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

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 12
            config.timeoutIntervalForResource = 20
            config.waitsForConnectivity = false
            config.httpMaximumConnectionsPerHost = 8
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
        as type: T.Type = T.self
    ) async throws -> T {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
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

    func getData(_ url: URL, query: [URLQueryItem] = []) async throws -> Data {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
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
        as type: T.Type = T.self
    ) async throws -> T {
        let final = try Self.makeURL(url, query: query)
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
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
    static let gamma = URL(string: "https://gamma-api.polymarket.com")!
    static let clob = URL(string: "https://clob.polymarket.com")!
    static let data = URL(string: "https://data-api.polymarket.com")!
}
