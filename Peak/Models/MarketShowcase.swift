import Foundation

/// Polymarket-style discovery: live markets only, ranked for showcase feeds.
///
/// **Server ranking (Gamma `/events`):** always `active=true&closed=false&archived=false`, then:
/// - Trending → `order=volume24hr&ascending=false` (24h notional volume; primary Polymarket showcase sort)
/// - Volume → `order=volume&ascending=false` (lifetime)
/// - New → `order=startDate&ascending=false`
/// - Ending → `order=endDate&ascending=true`
/// - Liquidity → `order=liquidity&ascending=false`
///
/// **Client safety net:** drop closed / inactive / past-`endDate` (plus grace) / non-tradable rows
/// even if Gamma returns them. List feeds must exclude; `fetchEvent(id:)` stays unfiltered for deep links.
enum MarketShowcase {
    /// Settlement / timezone lag before treating a past `endDate` as expired.
    static let endDateGrace: TimeInterval = 6 * 60 * 60

    // MARK: - Eligibility

    /// Open for trading: active, not closed, not past end (with grace), has prices or CLOB tokens.
    static func isLive(_ market: Market, now: Date = .now) -> Bool {
        guard market.active, !market.closed else { return false }
        if isPastEnd(market.endDate, now: now) { return false }
        let hasTokens = market.clobTokenIds.contains { !$0.isEmpty }
        let hasOpenPrices = market.outcomePrices.contains { $0 > 0 && $0 < 1 }
        return hasTokens || hasOpenPrices
    }

    /// Eligible for Markets / Search / For You / cache — at least one live market, event not expired.
    static func isShowcaseEligible(_ event: PeakEvent, now: Date = .now) -> Bool {
        if isPastEnd(event.endDate, now: now) { return false }
        return event.markets.contains { isLive($0, now: now) }
    }

    static func filter(_ events: [PeakEvent], now: Date = .now) -> [PeakEvent] {
        events.filter { isShowcaseEligible($0, now: now) }
    }

    static func filter(_ markets: [Market], now: Date = .now) -> [Market] {
        markets.filter { isLive($0, now: now) }
    }

    // MARK: - Ranking

    /// Trending among eligible: 24h volume, then liquidity (matches Polymarket showcase intent).
    static func rankTrending(_ events: [PeakEvent], now: Date = .now) -> [PeakEvent] {
        filter(events, now: now).sorted(by: trendingLessThan)
    }

    static func rank(_ events: [PeakEvent], sort: MarketSort, now: Date = .now) -> [PeakEvent] {
        let eligible = filter(events, now: now)
        switch sort {
        case .trending:
            return eligible.sorted(by: trendingLessThan)
        case .volume:
            return eligible.sorted { $0.volume > $1.volume }
        case .newest:
            return eligible.sorted { lhs, rhs in
                switch (lhs.startDate, rhs.startDate) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.volume24hr > rhs.volume24hr
                }
            }
        case .endingSoon:
            return eligible.sorted { lhs, rhs in
                switch (lhs.endDate, rhs.endDate) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.volume24hr > rhs.volume24hr
                }
            }
        case .liquidity:
            return eligible.sorted { $0.liquidity > $1.liquidity }
        }
    }

    // MARK: - Helpers

    private static func isPastEnd(_ end: Date?, now: Date) -> Bool {
        guard let end else { return false }
        return end.addingTimeInterval(endDateGrace) < now
    }

    private static func trendingLessThan(_ lhs: PeakEvent, _ rhs: PeakEvent) -> Bool {
        if lhs.volume24hr != rhs.volume24hr { return lhs.volume24hr > rhs.volume24hr }
        if lhs.liquidity != rhs.liquidity { return lhs.liquidity > rhs.liquidity }
        return lhs.volume > rhs.volume
    }
}

