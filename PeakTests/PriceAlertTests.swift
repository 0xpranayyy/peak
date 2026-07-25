import XCTest
@testable import Peak

final class PriceAlertTests: XCTestCase {
    private func makeAlert(direction: PriceAlert.Direction, target: Double) -> PriceAlert {
        PriceAlert(
            id: UUID().uuidString,
            eventID: "evt",
            eventTitle: "Some Event",
            marketID: "mkt",
            tokenID: "tok",
            outcomeLabel: "Yes",
            targetPrice: target,
            direction: direction,
            isActive: true,
            triggeredAt: nil,
            createdAt: Date()
        )
    }

    func testAtOrAboveTriggersWhenPriceMeetsOrExceedsTarget() {
        let alert = makeAlert(direction: .atOrAbove, target: 0.60)
        XCTAssertTrue(alert.isTriggered(by: 0.60))
        XCTAssertTrue(alert.isTriggered(by: 0.75))
        XCTAssertFalse(alert.isTriggered(by: 0.59))
    }

    func testAtOrBelowTriggersWhenPriceMeetsOrDropsUnderTarget() {
        let alert = makeAlert(direction: .atOrBelow, target: 0.30)
        XCTAssertTrue(alert.isTriggered(by: 0.30))
        XCTAssertTrue(alert.isTriggered(by: 0.10))
        XCTAssertFalse(alert.isTriggered(by: 0.31))
    }
}

@MainActor
final class PriceAlertStoreTests: XCTestCase {
    override func tearDown() async throws {
        for alert in PriceAlertStore.shared.alerts {
            PriceAlertStore.shared.remove(id: alert.id)
        }
        try await super.tearDown()
    }

    private func makeEventAndMarket() -> (PeakEvent, Market) {
        let market = Market(
            id: "m1",
            question: "Will it happen?",
            slug: nil,
            conditionId: nil,
            outcomes: ["Yes", "No"],
            outcomePrices: [0.5, 0.5],
            clobTokenIds: ["tok-yes", "tok-no"],
            volume: 0,
            volume24hr: 0,
            liquidity: 0,
            endDate: nil,
            negRisk: false,
            active: true,
            closed: false,
            eventId: "e1",
            eventTitle: "Test Event",
            imageURL: nil
        )
        let event = PeakEvent(
            id: "e1",
            slug: "test-event",
            title: "Test Event",
            description: nil,
            imageURL: nil,
            startDate: nil,
            endDate: nil,
            volume: 0,
            volume24hr: 0,
            liquidity: 0,
            tags: [],
            markets: [market]
        )
        return (event, market)
    }

    func testEvaluateFiresAndDeactivatesMatchingAlert() {
        let (event, market) = makeEventAndMarket()
        guard let alert = PriceAlertStore.shared.add(
            event: event, market: market, isYes: true, targetPrice: 0.70, direction: .atOrAbove
        ) else {
            return XCTFail("expected alert to be created")
        }

        let fired = PriceAlertStore.shared.evaluate(tokenID: alert.tokenID, price: 0.72)

        XCTAssertEqual(fired.map(\.id), [alert.id])
        XCTAssertFalse(PriceAlertStore.shared.activeAlerts.contains { $0.id == alert.id })
    }

    func testEvaluateIgnoresOutOfRangePrice() {
        let (event, market) = makeEventAndMarket()
        guard let alert = PriceAlertStore.shared.add(
            event: event, market: market, isYes: true, targetPrice: 0.10, direction: .atOrAbove
        ) else {
            return XCTFail("expected alert to be created")
        }

        // Prices must be in (0, 1); 0 and 1 are treated as not-yet-usable data.
        XCTAssertTrue(PriceAlertStore.shared.evaluate(tokenID: alert.tokenID, price: 0).isEmpty)
        XCTAssertTrue(PriceAlertStore.shared.evaluate(tokenID: alert.tokenID, price: 1).isEmpty)
    }

    func testTargetPriceIsClampedToValidRange() {
        let (event, market) = makeEventAndMarket()
        let alert = PriceAlertStore.shared.add(
            event: event, market: market, isYes: true, targetPrice: 5.0, direction: .atOrAbove
        )
        XCTAssertEqual(alert?.targetPrice, 0.99)
    }
}
