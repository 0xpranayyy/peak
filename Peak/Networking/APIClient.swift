import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case badStatus(Int)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .badStatus(let code): return "Server returned status \(code)."
        case .decoding(let error): return "Couldn’t decode response: \(error.localizedDescription)"
        case .emptyResponse: return "Empty response."
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
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
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            var items = comps?.queryItems ?? []
            items.append(contentsOf: query)
            comps?.queryItems = items
        }
        guard let final = comps?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

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
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            var items = comps?.queryItems ?? []
            items.append(contentsOf: query)
            comps?.queryItems = items
        }
        guard let final = comps?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: final)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return data
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
