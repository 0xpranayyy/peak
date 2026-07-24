import Foundation

/// Phase-2 trading surface.
protocol TradingService: Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult
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
}

/// Posts orders to the Peak Node proxy (`backend/`). Private keys never leave the proxy.
struct RemoteTradingService: TradingService, @unchecked Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double,
        negRisk: Bool?,
        orderType: String
    ) async throws -> TradeResult {
        let snapshot = await MainActor.run { () -> (URL?, String?) in
            let config = TradingConfigStore.shared
            return (config.baseURL, config.appToken())
        }
        guard let base = snapshot.0, let token = snapshot.1, !token.isEmpty else {
            throw TradingError.notConfigured
        }
        guard !tokenID.isEmpty, size > 0, price > 0, price < 1 else {
            throw TradingError.invalidAmount
        }

        var request = URLRequest(url: base.appendingPathComponent("orders"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            throw TradingError.server(message)
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let orderID =
            (root["orderID"] as? String)
            ?? (root["id"] as? String)
            ?? ""
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
}
