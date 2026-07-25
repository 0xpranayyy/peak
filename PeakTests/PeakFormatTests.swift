import XCTest
@testable import Peak

final class PeakFormatTests: XCTestCase {
    func testCentsRoundsToNearestWhole() {
        XCTAssertEqual(PeakFormat.cents(0.5), "50¢")
        XCTAssertEqual(PeakFormat.cents(0.999), "100¢")
        XCTAssertEqual(PeakFormat.cents(0.001), "0¢")
    }

    func testPercentDefaultDigits() {
        XCTAssertEqual(PeakFormat.percent(0.4321), "43.2%")
    }

    func testPercentCustomDigits() {
        XCTAssertEqual(PeakFormat.percent(0.4321, digits: 0), "43%")
    }

    func testCompactCurrencyThresholds() {
        XCTAssertEqual(PeakFormat.compactCurrency(999), "$999")
        XCTAssertEqual(PeakFormat.compactCurrency(1_500), "$1.5K")
        XCTAssertEqual(PeakFormat.compactCurrency(2_300_000), "$2.3M")
        XCTAssertEqual(PeakFormat.compactCurrency(1_000_000_000), "$1.0B")
    }

    func testCompactCurrencyNegative() {
        XCTAssertEqual(PeakFormat.compactCurrency(-1_500), "-$1.5K")
    }

    func testShortDateNilIsEmDash() {
        XCTAssertEqual(PeakFormat.shortDate(nil), "—")
    }

    func testRelativeEndNilIsOpen() {
        XCTAssertEqual(PeakFormat.relativeEnd(nil), "Open")
    }
}

final class PeakTradeStyleTests: XCTestCase {
    func testWideSpreadPrefersLastTrade() {
        let odds = PeakTradeStyle.displayedOdds(mid: 0.5, spread: 0.15, lastTrade: 0.62, fallback: 0.5)
        XCTAssertEqual(odds, 0.62)
    }

    func testTightSpreadPrefersMidpoint() {
        let odds = PeakTradeStyle.displayedOdds(mid: 0.47, spread: 0.02, lastTrade: 0.60, fallback: 0.5)
        XCTAssertEqual(odds, 0.47)
    }

    func testFallsBackToLastTradeWhenNoMidpoint() {
        let odds = PeakTradeStyle.displayedOdds(mid: nil, spread: nil, lastTrade: 0.33, fallback: 0.5)
        XCTAssertEqual(odds, 0.33)
    }

    func testFallsBackToFallbackWhenNothingUsable() {
        let odds = PeakTradeStyle.displayedOdds(mid: nil, spread: nil, lastTrade: nil, fallback: 0.42)
        XCTAssertEqual(odds, 0.42)
    }

    func testOutOfRangeMidpointIsIgnored() {
        // mid == 0 or 1 is treated as "not usable" per the 0 < mid < 1 guard.
        let odds = PeakTradeStyle.displayedOdds(mid: 1.0, spread: nil, lastTrade: 0.2, fallback: 0.5)
        XCTAssertEqual(odds, 0.2)
    }
}

final class PeakEventDisplayOddsTests: XCTestCase {
    private func event(prices: [Double]) -> PeakEvent {
        PeakEvent(
            id: "e1",
            slug: nil,
            title: "Test",
            description: nil,
            imageURL: nil,
            startDate: nil,
            endDate: nil,
            volume: 0,
            volume24hr: 0,
            liquidity: 0,
            tags: [],
            markets: [
                Market(
                    id: "m1",
                    question: "Q",
                    slug: nil,
                    conditionId: nil,
                    outcomes: ["Yes", "No"],
                    outcomePrices: prices,
                    clobTokenIds: ["t1", "t2"],
                    volume: 0,
                    volume24hr: 0,
                    liquidity: 0,
                    endDate: nil,
                    negRisk: false,
                    active: true,
                    closed: false,
                    eventId: "e1",
                    eventTitle: "Test",
                    imageURL: nil
                ),
            ]
        )
    }

    func testHidesBareZeroWithoutEnrichment() {
        let e = event(prices: [0, 1])
        XCTAssertNil(e.resolvedDisplayProbability(enriched: nil))
    }

    func testShowsGammaOddsWhenPresent() {
        let e = event(prices: [0.42, 0.58])
        XCTAssertEqual(e.resolvedDisplayProbability(enriched: nil), 0.42)
    }

    func testEnrichedZeroIsShown() {
        let e = event(prices: [0, 1])
        XCTAssertEqual(e.resolvedDisplayProbability(enriched: 0), 0)
    }

    func testEnrichedOverridesGamma() {
        let e = event(prices: [0.42, 0.58])
        XCTAssertEqual(e.resolvedDisplayProbability(enriched: 0.55), 0.55)
    }
}
