import XCTest
@testable import Peak

/// The unit contract between the amount field and CLOB.
///
/// A mistake here does not error — it submits a valid order for the wrong size.
/// That is the worst failure mode in the app, so it is pinned explicitly.
final class TradeAmountsTests: XCTestCase {

    // MARK: - Buys are entered in dollars

    func testMarketBuySendsDollarBudget() {
        let a = TradeAmounts(isSell: false, isMarket: true, price: 0.50, entered: 10)
        XCTAssertEqual(a.usd, 10, accuracy: 0.0001)
        XCTAssertEqual(a.shares, 20, accuracy: 0.0001, "$10 at 50¢ is 20 shares")
        XCTAssertEqual(a.orderAmount, 10, accuracy: 0.0001, "market buy spends a dollar budget")
    }

    func testLimitBuySendsShares() {
        // Limits are priced per share, so CLOB wants a share count even on a buy.
        let a = TradeAmounts(isSell: false, isMarket: false, price: 0.25, entered: 10)
        XCTAssertEqual(a.shares, 40, accuracy: 0.0001)
        XCTAssertEqual(a.orderAmount, 40, accuracy: 0.0001)
    }

    // MARK: - Sells are entered in shares

    func testMarketSellSendsShares() {
        let a = TradeAmounts(isSell: true, isMarket: true, price: 0.62, entered: 38.46)
        XCTAssertEqual(a.shares, 38.46, accuracy: 0.0001, "the field IS shares when selling")
        XCTAssertEqual(a.usd, 23.85, accuracy: 0.01, "38.46 shares at 62¢")
        XCTAssertEqual(a.orderAmount, 38.46, accuracy: 0.0001)
    }

    /// The regression that matters: entering 38.46 to sell must never be read as
    /// $38.46 and converted into ~62 shares.
    func testSellQuantityIsNeverConvertedThroughDollars() {
        let entered = 38.46
        let a = TradeAmounts(isSell: true, isMarket: true, price: 0.62, entered: entered)
        XCTAssertEqual(a.orderAmount, entered, accuracy: 0.0001)
        XCTAssertNotEqual(a.orderAmount, entered / 0.62, accuracy: 0.01)
    }

    /// And the mirror: a $10 market buy must not be read as 10 shares.
    func testBuyBudgetIsNeverReadAsShares() {
        let a = TradeAmounts(isSell: false, isMarket: true, price: 0.20, entered: 10)
        XCTAssertEqual(a.orderAmount, 10, accuracy: 0.0001)
        XCTAssertNotEqual(a.orderAmount, 50, accuracy: 0.01, "50 shares would be 5x the intended spend")
    }

    // MARK: - Validity

    func testZeroAmountIsInvalid() {
        XCTAssertFalse(TradeAmounts(isSell: false, isMarket: true, price: 0.5, entered: 0).isValid)
    }

    func testPriceOutsideProbabilityRangeIsInvalid() {
        for price in [0.0, 1.0, 1.5, -0.2] {
            let a = TradeAmounts(isSell: false, isMarket: true, price: price, entered: 10)
            XCTAssertFalse(a.isValid, "price \(price) is not a valid probability")
        }
    }

    func testZeroPriceDoesNotProduceInfiniteShares() {
        let a = TradeAmounts(isSell: false, isMarket: true, price: 0, entered: 10)
        XCTAssertEqual(a.shares, 0, "must not divide by zero into an infinite order")
        XCTAssertFalse(a.isValid)
    }

    func testTypicalValuesAreValid() {
        XCTAssertTrue(TradeAmounts(isSell: false, isMarket: true, price: 0.47, entered: 25).isValid)
        XCTAssertTrue(TradeAmounts(isSell: true, isMarket: true, price: 0.47, entered: 12.5).isValid)
    }

    /// Sub-cent prices are legal on Polymarket and must round-trip sanely.
    func testExtremePricesStillConvert() {
        let cheap = TradeAmounts(isSell: false, isMarket: true, price: 0.01, entered: 5)
        XCTAssertEqual(cheap.shares, 500, accuracy: 0.001)
        XCTAssertTrue(cheap.isValid)

        let rich = TradeAmounts(isSell: true, isMarket: true, price: 0.99, entered: 3)
        XCTAssertEqual(rich.usd, 2.97, accuracy: 0.001)
        XCTAssertTrue(rich.isValid)
    }
}
