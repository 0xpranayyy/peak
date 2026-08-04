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

    func testTradeCardRendersBuyAndSell() throws {
        let (_, market) = fixture()
        for side in [TradeCelebrationResult.Side.buy, .sell] {
            let result = TradeCelebrationResult(
                side: side,
                outcomeLabel: market.yesLabel,
                marketQuestion: market.question,
                eventTitle: market.eventTitle,
                price: 0.54,
                shares: 18.5,
                usd: 10,
                isPartial: false,
                fillMessage: "Filled",
                marketImageURL: nil,
                marketSlug: market.slug,
                username: "peaktrader"
            )
            let image = try XCTUnwrap(PeakTradeShareCardRenderer.image(result: result))
            XCTAssertEqual(image.size.width, PeakPostcard.cardWidth, accuracy: 1)
            XCTAssertEqual(image.size.height, PeakPostcard.tradeCardHeight, accuracy: 1)
            XCTAssertGreaterThan(image.scale, 1)
        }
    }

    func testTradeCelebrationTweetMentionsSide() {
        let result = TradeCelebrationResult(
            side: .buy,
            outcomeLabel: "Yes",
            marketQuestion: "Will it rain?",
            eventTitle: nil,
            price: 0.4,
            shares: 25,
            usd: 10,
            isPartial: false,
            fillMessage: "Filled",
            marketImageURL: nil,
            marketSlug: nil,
            username: "peaktrader"
        )
        XCTAssertTrue(result.tweetText.lowercased().contains("bought"))
        XCTAssertTrue(result.tweetText.contains("Yes"))
        XCTAssertTrue(result.tweetText.contains("Peak"))
    }

    func testTradeReceiptMetricsMapFromFill() {
        let buy = TradeCelebrationResult.previewBuy
        XCTAssertEqual(buy.impliedOdds, 42)
        XCTAssertEqual(buy.potentialProfit ?? -1, 58, accuracy: 0.01)
        XCTAssertEqual(buy.potentialReturnPct ?? -1, 138, accuracy: 0.5)
        XCTAssertEqual(buy.potentialPayout ?? -1, 100, accuracy: 0.01)
        XCTAssertNotNil(buy.marketURL)

        let sell = TradeCelebrationResult.previewSell
        XCTAssertNil(sell.potentialProfit)
        XCTAssertNil(sell.potentialReturnPct)
        XCTAssertNil(sell.potentialPayout)
        XCTAssertEqual(sell.impliedOdds, 61)
        XCTAssertEqual(sell.displayName, "Mira Chen")
    }

    /// Run with `-only-testing:PeakTests/ShareCardRenderTests/testExportTradeShareCardPreviews`
    /// to write Bought/Sold PNGs under `docs/share-previews/`.
    func testExportTradeShareCardPreviews() throws {
        let outDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/share-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Synthetic market art so previews exercise the visible tile + ambient blur.
        let swatch = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            let colors = [
                UIColor(red: 0.10, green: 0.55, blue: 0.42, alpha: 1),
                UIColor(red: 0.06, green: 0.22, blue: 0.28, alpha: 1),
                UIColor(red: 0.18, green: 0.72, blue: 0.48, alpha: 1),
            ]
            for (i, color) in colors.enumerated() {
                color.setFill()
                let inset = CGFloat(i) * 36
                ctx.fill(CGRect(x: inset, y: inset, width: 256 - inset * 2, height: 256 - inset * 2))
            }
        }

        let buy = try XCTUnwrap(PeakTradeShareCardRenderer.image(result: .previewBuy, icon: swatch))
        let sell = try XCTUnwrap(PeakTradeShareCardRenderer.image(result: .previewSell, icon: swatch))
        let buyData = try XCTUnwrap(Self.pngDataFlattened(buy))
        let sellData = try XCTUnwrap(Self.pngDataFlattened(sell))
        try buyData.write(to: outDir.appendingPathComponent("trade-share-bought.png"))
        try sellData.write(to: outDir.appendingPathComponent("trade-share-sold.png"))

        XCTAssertGreaterThan(buyData.count, 80_000, "bought preview should not be a blank black frame")
        XCTAssertGreaterThan(sellData.count, 80_000, "sold preview should not be a blank black frame")
    }

    /// ImageRenderer sometimes yields a bitmap `pngData()` can't encode; flatten first.
    private static func pngDataFlattened(_ image: UIImage) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let size = image.size
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return flattened.pngData()
    }
}
