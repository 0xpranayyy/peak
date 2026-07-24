import Foundation

/// Phase-2 trading surface. v1 is intentionally a no-op stub — Peak is read-only.
protocol TradingService: Sendable {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double
    ) async throws -> TradeResult
}

enum TradeSide: String, Sendable {
    case buy
    case sell
}

struct TradeResult: Sendable {
    let orderID: String
    let status: String
}

enum TradingError: LocalizedError, Sendable {
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Trading isn’t available in Peak v1. Order placement ships in Phase 2."
        }
    }
}

struct StubTradingService: TradingService {
    func placeOrder(
        tokenID: String,
        side: TradeSide,
        price: Double,
        size: Double
    ) async throws -> TradeResult {
        throw TradingError.notAvailable
    }
}
