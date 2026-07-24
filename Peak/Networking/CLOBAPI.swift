import Foundation

enum CLOBAPI {
    struct PriceHistoryResponse: Decodable {
        let history: [Point]
        struct Point: Decodable {
            let t: Int
            let p: Double
        }
    }

    struct BookDTO: Decodable {
        let bids: [Level]?
        let asks: [Level]?

        struct Level: Decodable {
            let price: FlexibleNumber
            let size: FlexibleNumber
        }
    }

    struct FlexibleNumber: Decodable {
        let value: Double
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
            else if let i = try? c.decode(Int.self) { value = Double(i) }
            else { value = 0 }
        }
    }

    struct PriceResponse: Decodable {
        let price: FlexibleNumber?
    }

    struct MidpointResponse: Decodable {
        let mid: FlexibleNumber?
    }

    struct SpreadResponse: Decodable {
        let spread: FlexibleNumber?
    }

    static func fetchPriceHistory(
        tokenID: String,
        interval: String = "1d",
        fidelity: Int = 60
    ) async throws -> [PricePoint] {
        let url = PeakAPIBase.clob.appendingPathComponent("prices-history")
        let response: PriceHistoryResponse = try await APIClient.shared.get(
            url,
            query: [
                .init(name: "market", value: tokenID),
                .init(name: "interval", value: interval),
                .init(name: "fidelity", value: String(fidelity)),
            ]
        )
        return response.history.map { PricePoint(timestamp: $0.t, price: $0.p) }
    }

    static func fetchBook(tokenID: String) async throws -> OrderBook {
        let url = PeakAPIBase.clob.appendingPathComponent("book")
        let dto: BookDTO = try await APIClient.shared.get(
            url,
            query: [.init(name: "token_id", value: tokenID)]
        )
        let bids = (dto.bids ?? []).map {
            OrderBookLevel(price: $0.price.value, size: $0.size.value, side: .bid)
        }
        .sorted { $0.price > $1.price }
        let asks = (dto.asks ?? []).map {
            OrderBookLevel(price: $0.price.value, size: $0.size.value, side: .ask)
        }
        .sorted { $0.price < $1.price }
        return OrderBook(bids: Array(bids.prefix(12)), asks: Array(asks.prefix(12)))
    }

    static func fetchPrice(tokenID: String, side: String = "buy") async throws -> Double? {
        let url = PeakAPIBase.clob.appendingPathComponent("price")
        let dto: PriceResponse = try await APIClient.shared.get(
            url,
            query: [
                .init(name: "token_id", value: tokenID),
                .init(name: "side", value: side),
            ]
        )
        return dto.price?.value
    }

    /// Batch prices for multiple token IDs. Request body: `{ "token_ids": [...] }` is not used —
    /// CLOB accepts repeated `token_ids` / uses GET `/prices` with JSON map response.
    static func fetchPrices(tokenIDs: [String], side: String = "buy") async throws -> [String: Double] {
        guard !tokenIDs.isEmpty else { return [:] }
        // Polymarket `/prices` expects POST with body in some clients; public GET uses query.
        // Fall back to concurrent single-price fetches for reliability.
        var result: [String: Double] = [:]
        try await withThrowingTaskGroup(of: (String, Double?).self) { group in
            for id in tokenIDs {
                group.addTask {
                    (id, try await fetchPrice(tokenID: id, side: side))
                }
            }
            for try await (id, price) in group {
                if let price { result[id] = price }
            }
        }
        return result
    }

    static func fetchMidpoint(tokenID: String) async throws -> Double? {
        let url = PeakAPIBase.clob.appendingPathComponent("midpoint")
        let dto: MidpointResponse = try await APIClient.shared.get(
            url,
            query: [.init(name: "token_id", value: tokenID)]
        )
        return dto.mid?.value
    }

    static func fetchSpread(tokenID: String) async throws -> Double? {
        let url = PeakAPIBase.clob.appendingPathComponent("spread")
        let dto: SpreadResponse = try await APIClient.shared.get(
            url,
            query: [.init(name: "token_id", value: tokenID)]
        )
        return dto.spread?.value
    }

    struct ClobMarketInfo: Decodable, Sendable {
        let acceptingOrders: Bool?
        let minimumOrderSize: FlexibleNumber?
        let minimumTickSize: FlexibleNumber?
        let conditionId: String?
        let tokens: [Token]?

        struct Token: Decodable, Sendable {
            let token_id: String?
            let outcome: String?
        }
    }

    /// CLOB-level market parameters for a condition id.
    static func fetchClobMarketInfo(conditionID: String) async throws -> ClobMarketInfo {
        let url = PeakAPIBase.clob
            .appendingPathComponent("clob-markets")
            .appendingPathComponent(conditionID)
        return try await APIClient.shared.get(url)
    }
}
