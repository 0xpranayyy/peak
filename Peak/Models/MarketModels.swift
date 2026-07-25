import Foundation

struct MarketTag: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let label: String
    let slug: String?
}

struct PeakEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let slug: String?
    let title: String
    let description: String?
    let imageURL: URL?
    let startDate: Date?
    let endDate: Date?
    let volume: Double
    let volume24hr: Double
    let liquidity: Double
    let tags: [MarketTag]
    var markets: [Market]

    var primaryMarket: Market? { markets.first }
    var displayProbability: Double? { primaryMarket?.yesPrice }

    /// Prefer CLOB-enriched odds; else Gamma yes when clearly set (hide bare 0 until enrich).
    func resolvedDisplayProbability(enriched: Double?) -> Double? {
        if let enriched, enriched.isFinite, enriched >= 0, enriched <= 1 {
            return enriched
        }
        guard let p = displayProbability, p.isFinite, p > 0, p <= 1 else { return nil }
        return p
    }

    /// List / rail eligibility (not applied on event-detail deep links).
    var isShowcaseEligible: Bool { MarketShowcase.isShowcaseEligible(self) }
}

struct Market: Identifiable, Hashable, Codable, Sendable {
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
    /// Gamma top-of-book hints (optional) — used when CLOB/WS are unavailable.
    var gammaBestBid: Double? = nil
    var gammaBestAsk: Double? = nil

    /// Open for showcase / trading feeds (detail may still load closed markets).
    var isShowcaseEligible: Bool { MarketShowcase.isLive(self) }

    /// Index of the Yes-like outcome (explicit "Yes", else first).
    private var yesOutcomeIndex: Int {
        if let idx = outcomes.firstIndex(where: { $0.caseInsensitiveCompare("Yes") == .orderedSame }) {
            return idx
        }
        return 0
    }

    /// Index of the No-like outcome (explicit "No", else the other binary slot).
    private var noOutcomeIndex: Int {
        if let idx = outcomes.firstIndex(where: { $0.caseInsensitiveCompare("No") == .orderedSame }) {
            return idx
        }
        return yesOutcomeIndex == 0 ? 1 : 0
    }

    var yesPrice: Double {
        let idx = yesOutcomeIndex
        if idx < outcomePrices.count { return outcomePrices[idx] }
        return outcomePrices.first ?? 0.5
    }

    var noPrice: Double {
        let idx = noOutcomeIndex
        if idx < outcomePrices.count { return outcomePrices[idx] }
        return max(0, 1 - yesPrice)
    }

    var yesTokenID: String? {
        let idx = yesOutcomeIndex
        guard idx < clobTokenIds.count else { return clobTokenIds.first }
        return clobTokenIds[idx]
    }

    var noTokenID: String? {
        let idx = noOutcomeIndex
        guard idx < clobTokenIds.count else {
            return clobTokenIds.count > 1 ? clobTokenIds[1] : nil
        }
        return clobTokenIds[idx]
    }

    var yesLabel: String {
        let idx = yesOutcomeIndex
        if idx < outcomes.count { return outcomes[idx] }
        return outcomes.first ?? "Yes"
    }

    var noLabel: String {
        let idx = noOutcomeIndex
        if idx < outcomes.count { return outcomes[idx] }
        return outcomes.count > 1 ? outcomes[1] : "No"
    }

    mutating func applyLivePrice(tokenID: String, price: Double) {
        guard price >= 0, price <= 1 else { return }
        let yesIdx = yesOutcomeIndex
        let noIdx = noOutcomeIndex
        if tokenID == yesTokenID {
            ensureOutcomePriceSlots()
            if yesIdx < outcomePrices.count {
                outcomePrices[yesIdx] = price
            }
            if noIdx < outcomePrices.count {
                outcomePrices[noIdx] = max(0, 1 - price)
            }
        } else if tokenID == noTokenID {
            ensureOutcomePriceSlots()
            if noIdx < outcomePrices.count {
                outcomePrices[noIdx] = price
            }
            if yesIdx < outcomePrices.count {
                outcomePrices[yesIdx] = max(0, 1 - price)
            }
        }
    }

    private mutating func ensureOutcomePriceSlots() {
        let needed = max(2, max(yesOutcomeIndex, noOutcomeIndex) + 1)
        while outcomePrices.count < needed {
            outcomePrices.append(0.5)
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

struct PortfolioActivity: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let outcome: String?
    let type: String
    let side: String?
    let size: Double
    let price: Double
    let usdcSize: Double
    let timestamp: Date?
}
