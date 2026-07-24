import Foundation

struct OpenOrder: Identifiable, Hashable, Sendable {
    let id: String
    let tokenID: String
    let market: String?
    let side: String
    let price: Double
    let originalSize: Double
    let sizeMatched: Double
    let status: String?

    var remaining: Double { max(0, originalSize - sizeMatched) }
}

struct TradingPortfolioSnapshot: Sendable {
    let funder: String?
    let cash: Double?
    let totalValue: Double?
    let positions: [PortfolioPosition]
    let activity: [PortfolioActivity]
    let openOrders: [OpenOrder]
}

struct DepositAddressResult: @unchecked Sendable {
    let address: String?
    let raw: [String: Any]
}

/// Phase 2+ trading surface (proxy-backed).
protocol TradingService: Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult

    func fetchOpenOrders() async throws -> [OpenOrder]
    func cancelOrder(id: String) async throws
    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot
    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult
}

enum TradeSide: String, Sendable {
    case buy
    case sell
}

struct TradeResult: Sendable {
    let orderID: String
    let status: String
    let success: Bool
}

enum TradingError: LocalizedError, Sendable {
    case notConfigured
    case notAvailable
    case invalidAmount
    case missingToken
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set up the trading proxy in Portfolio → Trading to place orders."
        case .notAvailable:
            return "Trading isn’t available."
        case .invalidAmount:
            return "Enter a valid USD amount and price."
        case .missingToken:
            return "This market is missing a CLOB token id."
        case .server(let message):
            return message
        }
    }
}

struct StubTradingService: TradingService {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult {
        throw TradingError.notConfigured
    }

    func fetchOpenOrders() async throws -> [OpenOrder] { throw TradingError.notConfigured }
    func cancelOrder(id: String) async throws { throw TradingError.notConfigured }
    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot { throw TradingError.notConfigured }
    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult {
        throw TradingError.notConfigured
    }
}

/// Posts to the Peak Node proxy (`backend/`). Private keys never leave the proxy.
struct RemoteTradingService: TradingService, @unchecked Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult {
        guard !tokenID.isEmpty, size > 0, price > 0, price < 1 else {
            throw TradingError.invalidAmount
        }

        var body: [String: Any] = [
            "tokenID": tokenID,
            "price": (price * 1000).rounded() / 1000,
            "size": (size * 100).rounded() / 100,
            "side": side == .buy ? "BUY" : "SELL",
            "orderType": orderType,
        ]
        if let negRisk {
            body["negRisk"] = negRisk
        }

        let root = try await TradingProxyClient.jsonObject(path: "orders", method: "POST", jsonBody: body)
        let orderID = (root["orderID"] as? String) ?? (root["id"] as? String) ?? ""
        let status = (root["status"] as? String) ?? "submitted"
        let success = (root["success"] as? Bool) ?? !status.lowercased().contains("error")
        if let error = root["error"] as? String, !error.isEmpty, orderID.isEmpty {
            throw TradingError.server(error)
        }
        return TradeResult(
            orderID: orderID.isEmpty ? status : orderID,
            status: status,
            success: success
        )
    }

    func fetchOpenOrders() async throws -> [OpenOrder] {
        let data = try await TradingProxyClient.request(path: "orders")
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let rows = root["open"] as? [[String: Any]] ?? []
        return rows.compactMap(Self.mapOpenOrder)
    }

    func cancelOrder(id: String) async throws {
        _ = try await TradingProxyClient.request(path: "orders/\(id)", method: "DELETE")
    }

    func fetchTradingPortfolio() async throws -> TradingPortfolioSnapshot {
        async let portfolioData = TradingProxyClient.request(path: "portfolio")
        async let activityData = TradingProxyClient.request(
            path: "activity",
            query: [.init(name: "limit", value: "20")]
        )
        async let ordersData = TradingProxyClient.request(path: "orders")

        let portfolioRoot = (try? JSONSerialization.jsonObject(with: try await portfolioData) as? [String: Any]) ?? [:]
        let activityRows = (try? JSONSerialization.jsonObject(with: try await activityData) as? [[String: Any]]) ?? []
        let ordersRoot = (try? JSONSerialization.jsonObject(with: try await ordersData) as? [String: Any]) ?? [:]

        let positionRows = portfolioRoot["positions"] as? [[String: Any]] ?? []
        let positions: [PortfolioPosition] = positionRows.compactMap { row in
            guard let data = try? JSONSerialization.data(withJSONObject: row),
                  let dto = try? JSONDecoder().decode(DataAPI.PositionDTO.self, from: data) else {
                return nil
            }
            return dto.asPosition()
        }

        let activity: [PortfolioActivity] = activityRows.compactMap { row in
            guard let data = try? JSONSerialization.data(withJSONObject: row),
                  let dto = try? JSONDecoder().decode(DataAPI.ActivityDTO.self, from: data) else {
                return nil
            }
            return dto.asActivity()
        }

        let open = (ordersRoot["open"] as? [[String: Any]] ?? []).compactMap(Self.mapOpenOrder)

        var cash: Double?
        if let balance = portfolioRoot["balance"] as? [String: Any] {
            cash = Self.double(balance["balance"]).map { raw in
                raw > 100_000 ? raw / 1_000_000 : raw
            }
        }

        var totalValue: Double?
        if let value = portfolioRoot["value"] as? [String: Any] {
            totalValue = Self.double(value["value"])
        } else if let arr = portfolioRoot["value"] as? [[String: Any]], let first = arr.first {
            totalValue = Self.double(first["value"])
        }

        return TradingPortfolioSnapshot(
            funder: portfolioRoot["funder"] as? String,
            cash: cash,
            totalValue: totalValue,
            positions: positions,
            activity: activity,
            openOrders: open
        )
    }

    func requestDepositAddress(chain: String, token: String) async throws -> DepositAddressResult {
        let root = try await TradingProxyClient.jsonObject(
            path: "deposit-address",
            method: "POST",
            jsonBody: [
                "chain": chain,
                "token": token,
            ]
        )
        let address =
            (root["address"] as? String)
            ?? (root["depositAddress"] as? String)
            ?? ((root["address"] as? [String: Any])?["address"] as? String)
        return DepositAddressResult(address: address, raw: root)
    }

    private static func mapOpenOrder(_ row: [String: Any]) -> OpenOrder? {
        let id = (row["id"] as? String) ?? (row["orderID"] as? String) ?? (row["order_id"] as? String)
        guard let id else { return nil }
        return OpenOrder(
            id: id,
            tokenID: (row["asset_id"] as? String) ?? (row["tokenID"] as? String) ?? "",
            market: row["market"] as? String,
            side: ((row["side"] as? String) ?? "BUY").uppercased(),
            price: double(row["price"]) ?? 0,
            originalSize: double(row["original_size"]) ?? double(row["size"]) ?? 0,
            sizeMatched: double(row["size_matched"]) ?? double(row["matched"]) ?? 0,
            status: row["status"] as? String
        )
    }

    private static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
