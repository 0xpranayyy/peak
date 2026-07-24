import Foundation

struct MarketTag: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let slug: String?
}

struct PeakEvent: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String?
    let title: String
    let description: String?
    let imageURL: URL?
    let endDate: Date?
    let volume: Double
    let volume24hr: Double
    let liquidity: Double
    let tags: [MarketTag]
    var markets: [Market]

    var primaryMarket: Market? { markets.first }
    var displayProbability: Double? { primaryMarket?.yesPrice }
}

struct Market: Identifiable, Hashable, Sendable {
    let id: String
    let question: String
    let slug: String?
    let conditionId: String?
    let outcomes: [String]
    var outcomePrices: [Double]
    let clobTokenIds: [String]
    let volume: Double
    let volume24hr: Double
    let liquidity: Double
    let endDate: Date?
    let negRisk: Bool
    let active: Bool
    let closed: Bool
    let eventId: String?
    let eventTitle: String?
    let imageURL: URL?

    var yesPrice: Double {
        outcomePrices.first ?? 0.5
    }

    var noPrice: Double {
        if outcomePrices.count > 1 { return outcomePrices[1] }
        return max(0, 1 - yesPrice)
    }

    var yesTokenID: String? { clobTokenIds.first }
    var noTokenID: String? { clobTokenIds.count > 1 ? clobTokenIds[1] : nil }

    var yesLabel: String { outcomes.first ?? "Yes" }
    var noLabel: String { outcomes.count > 1 ? outcomes[1] : "No" }

    mutating func applyLivePrice(tokenID: String, price: Double) {
        guard price > 0, price < 1 else { return }
        if tokenID == yesTokenID {
            if outcomePrices.isEmpty {
                outcomePrices = [price, max(0, 1 - price)]
            } else {
                outcomePrices[0] = price
                if outcomePrices.count > 1 {
                    outcomePrices[1] = max(0, 1 - price)
                }
            }
        } else if tokenID == noTokenID {
            if outcomePrices.count > 1 {
                outcomePrices[1] = price
                outcomePrices[0] = max(0, 1 - price)
            } else {
                outcomePrices = [max(0, 1 - price), price]
            }
        }
    }
}

struct PricePoint: Identifiable, Hashable, Sendable {
    var id: Int { timestamp }
    let timestamp: Int
    let price: Double
}

struct OrderBookLevel: Identifiable, Hashable, Sendable {
    var id: String { "\(side)-\(price)-\(size)" }
    let price: Double
    let size: Double
    let side: Side

    enum Side: String, Sendable {
        case bid, ask
    }
}

struct OrderBook: Hashable, Sendable {
    var bids: [OrderBookLevel]
    var asks: [OrderBookLevel]

    var bestBid: Double? { bids.map(\.price).max() }
    var bestAsk: Double? { asks.map(\.price).min() }
    var midpoint: Double? {
        guard let bid = bestBid, let ask = bestAsk else { return nil }
        return (bid + ask) / 2
    }
}

struct PortfolioPosition: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let outcome: String
    let size: Double
    let avgPrice: Double
    let currentPrice: Double
    let currentValue: Double
    let cashPnl: Double
    let percentPnl: Double
    let curPrice: Double
    let eventSlug: String?
    let conditionId: String?
    let asset: String?
}
