import XCTest
import SwiftUI
import UIKit
@testable import Peak

/// The share card is exported as an image, so nothing about it is visible until
/// it renders. `ImageRenderer` returning nil, or a card that silently collapses
/// to the wrong size, would ship as a broken share with no in-app symptom.
@MainActor
final class ShareCardRenderTests: XCTestCase {

    private func fixture(
        yes: Double = 0.54,
        title: String = "Los Angeles Angels vs. San Francisco Giants"
    ) -> (PeakEvent, Market) {
        let market = Market(
            id: "m1",
            question: title,
            slug: "angels-giants",
            conditionId: "c1",
            outcomes: ["Los Angeles Angels", "San Francisco Giants"],
            outcomePrices: [yes, 1 - yes],
            clobTokenIds: ["t1", "t2"],
            volume: 1_200_000,
            volume24hr: 460_500,
            liquidity: 90_000,
            endDate: nil,
            negRisk: false,
            active: true,
            closed: false,
            eventId: "e1",
            eventTitle: title,
            imageURL: nil
        )
        let event = PeakEvent(
            id: "e1",
            slug: "angels-giants",
            title: title,
            description: nil,
            imageURL: nil,
            startDate: nil,
            endDate: nil,
            volume: 1_200_000,
            volume24hr: 460_500,
            liquidity: 90_000,
            tags: [MarketTag(id: "t-sports", label: "Sports", slug: "sports")],
            markets: [market]
        )
        return (event, market)
    }

    private func history(_ count: Int = 24) -> [PricePoint] {
        (0..<count).map { i in
            PricePoint(
                timestamp: 1_700_000_000 + i * 3600,
                price: 0.42 + 0.12 * sin(Double(i) / 3.0)
            )
        }
    }

    func testCardRendersAtTheDeclaredSize() throws {
        let (event, market) = fixture()
        let image = try XCTUnwrap(
            PeakShareCardRenderer.image(event: event, market: market, history: history())
        )
        // scale 3 — points to pixels.
        XCTAssertEqual(image.size.width, PeakPostcard.cardWidth, accuracy: 1)
        XCTAssertEqual(image.size.height, PeakPostcard.cardHeight, accuracy: 1)
        XCTAssertGreaterThan(image.scale, 1, "a 1x share card looks soft on every modern feed")
    }

    /// The icon is the thing that was missing. Passing one must not break the
    /// render, and omitting one must still produce a card.
    func testCardRendersWithAndWithoutAMarketIcon() throws {
        let (event, market) = fixture()

        let withoutIcon = PeakShareCardRenderer.image(event: event, market: market)
        XCTAssertNotNil(withoutIcon, "a market with no artwork must still render")

        let swatch = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor.systemIndigo.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let withIcon = PeakShareCardRenderer.image(event: event, market: market, icon: swatch)
        XCTAssertNotNil(withIcon)
    }

    /// No history is the common case for a fresh market.
    func testCardRendersWithoutHistory() {
        let (event, market) = fixture()
        XCTAssertNotNil(PeakShareCardRenderer.image(event: event, market: market, history: []))
    }

    /// A single point cannot form a line; the sparkline is skipped rather than
    /// dividing by a zero-length span.
    func testSinglePointHistoryDoesNotBreakTheRender() {
        let (event, market) = fixture()
        XCTAssertNotNil(
            PeakShareCardRenderer.image(event: event, market: market, history: Array(history(1)))
        )
    }

    /// Extremes: a 99% favourite and a dead-even market both have to lay out.
    func testExtremeOddsStillRender() {
        for yes in [0.01, 0.5, 0.99] {
            let (event, market) = fixture(yes: yes)
            XCTAssertNotNil(
                PeakShareCardRenderer.image(event: event, market: market, history: history()),
                "failed at yes=\(yes)"
            )
        }
    }

    /// Long team names are normal in sports markets and must not blow up the
    /// fixed-size card.
    func testVeryLongTitleStillRenders() {
        let (event, market) = fixture(
            title: String(repeating: "Extremely Long Market Question ", count: 6)
        )
        XCTAssertNotNil(PeakShareCardRenderer.image(event: event, market: market))
    }

    func testPositionCardRenders() throws {
        let position = PortfolioPosition(
            id: "p1",
            title: "Will it rain tomorrow?",
            outcome: "Yes",
            size: 120,
            avgPrice: 0.42,
            currentPrice: 0.55,
            currentValue: 66,
            cashPnl: 15.6,
            percentPnl: 30.9,
            curPrice: 0.55,
            eventSlug: nil,
            conditionId: nil,
            asset: nil
        )
        let renderer = ImageRenderer(content: PeakPositionShareCard(position: position))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        // Shorter than the market card on purpose — it has no chart, and at the
        // market card's height a third of the paper renders empty.
        XCTAssertEqual(image.size.height, PeakPostcard.positionCardHeight, accuracy: 1)
        XCTAssertLessThan(PeakPostcard.positionCardHeight, PeakPostcard.cardHeight)
    }
}
