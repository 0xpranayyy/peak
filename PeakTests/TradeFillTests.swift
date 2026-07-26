import XCTest
@testable import Peak

/// What the user is told after a market sell.
///
/// Sells are FAK, so "the order succeeded" and "you sold what you asked for"
/// are no longer the same statement. Every case below exists because getting it
/// wrong would leave someone believing they had exited a position they are
/// still holding — a silent failure, not a visible one.
final class TradeFillTests: XCTestCase {

    // MARK: - Zero fill must never read as success

    func testZeroFillIsNotSuccess() {
        let fill = TradeFill(requested: 50, filled: 0, isSell: true)
        XCTAssertTrue(fill.isEmpty)
        XCTAssertFalse(fill.didSucceed, "nothing sold is a failed exit, however CLOB labels it")
        XCTAssertFalse(fill.isPartial)
        XCTAssertFalse(fill.isComplete)
    }

    func testZeroFillTellsUserTheirSharesAreSafe() {
        let message = TradeFill(requested: 50, filled: 0, isSell: true).message
        XCTAssertTrue(message.contains("untouched"), "the user must know they still hold everything")
        XCTAssertFalse(message.contains("Filled"), "must not imply anything traded")
    }

    // MARK: - Partial fills

    func testPartialFillReportsBothNumbers() {
        let fill = TradeFill(requested: 50, filled: 34, isSell: true)
        XCTAssertTrue(fill.isPartial)
        XCTAssertTrue(fill.didSucceed, "a partial sell did move shares")
        XCTAssertFalse(fill.isComplete)

        let message = fill.message
        XCTAssertTrue(message.contains("34"), "user needs the filled count")
        XCTAssertTrue(message.contains("50"), "and what they asked for, to infer the remainder")
        XCTAssertTrue(message.contains("sold"))
    }

    func testNearlyCompleteFillIsNotFlaggedPartial() {
        // Tick rounding can land a hair under. Warning about 49.7 of 50 shares
        // would train users to ignore a warning that matters.
        let fill = TradeFill(requested: 50, filled: 49.7, isSell: true)
        XCTAssertFalse(fill.isPartial)
        XCTAssertTrue(fill.isComplete)
    }

    func testJustBelowThresholdIsPartial() {
        let fill = TradeFill(requested: 100, filled: 98, isSell: true)
        XCTAssertTrue(fill.isPartial, "2% short is a real shortfall, not dust")
    }

    // MARK: - Complete fills

    func testCompleteFillReadsAsFilled() {
        let fill = TradeFill(requested: 50, filled: 50, isSell: true)
        XCTAssertTrue(fill.isComplete)
        XCTAssertTrue(fill.didSucceed)
        XCTAssertTrue(fill.message.contains("Filled"))
        XCTAssertFalse(fill.message.contains("couldn’t"), "no warning when nothing went wrong")
    }

    func testOverFillIsTreatedAsComplete() {
        let fill = TradeFill(requested: 50, filled: 50.2, isSell: true)
        XCTAssertTrue(fill.isComplete)
        XCTAssertFalse(fill.isPartial)
    }

    // MARK: - Unknown fill degrades honestly

    func testUnknownFillMakesNoClaim() {
        let fill = TradeFill(requested: 50, filled: nil, isSell: true)
        XCTAssertFalse(fill.isEmpty, "unknown is not zero")
        XCTAssertFalse(fill.isPartial)
        XCTAssertFalse(fill.isComplete)
        XCTAssertTrue(fill.didSucceed, "no evidence of failure means don't alarm the user")
        XCTAssertEqual(fill.message, "Your order was submitted.")
    }

    // MARK: - Copy quality

    func testBuyAndSellUseTheRightVerb() {
        XCTAssertTrue(TradeFill(requested: 10, filled: 4, isSell: false).message.contains("bought"))
        XCTAssertTrue(TradeFill(requested: 10, filled: 4, isSell: true).message.contains("sold"))
    }

    func testWholeShareCountsDoNotRenderWithDecimals() {
        let message = TradeFill(requested: 50, filled: 34, isSell: true).message
        XCTAssertTrue(message.contains("34 of 50"), "got: \(message)")
        XCTAssertFalse(message.contains("34.00"))
    }

    func testFractionalSharesKeepTwoDecimals() {
        let message = TradeFill(requested: 12.5, filled: 6.25, isSell: true).message
        XCTAssertTrue(message.contains("6.25"), "got: \(message)")
    }

    func testNoMessageIsEmptyOrLeaksNil() {
        for filled in [nil, 0, 25, 50, 50.5] as [Double?] {
            for isSell in [true, false] {
                let message = TradeFill(requested: 50, filled: filled, isSell: isSell).message
                XCTAssertFalse(message.isEmpty)
                XCTAssertFalse(message.contains("nil"))
                XCTAssertFalse(message.contains("Optional"))
                XCTAssertFalse(message.contains("inf"))
            }
        }
    }

    // MARK: - Degenerate input

    func testZeroRequestedDoesNotDivideByZero() {
        let fill = TradeFill(requested: 0, filled: 0, isSell: true)
        XCTAssertFalse(fill.isPartial)
        XCTAssertFalse(fill.message.isEmpty)
    }
}

/// Reading the fill size out of a CLOB response.
///
/// The unit is the trap: the same field may arrive as human shares or as raw
/// 1e6 base units. A wrong guess produces a confidently wrong sentence rather
/// than a crash, so this must fail to "unknown" instead of to a number.
final class NormalizedFillTests: XCTestCase {

    private func fill(_ raw: Any?, requested: Double = 50) -> Double? {
        RemoteTradingService.normalizedFill(raw, requestedShares: requested)
    }

    func testPlainDecimalStringIsUsedAsIs() {
        XCTAssertEqual(fill("34.5"), 34.5)
    }

    func testNumbersAreAccepted() {
        XCTAssertEqual(fill(34 as NSNumber), 34)
    }

    func testBaseUnitsAreReportedAsUnknownNotRescaled() {
        // Rescaling was tried and removed: it turned values that were never
        // share counts into plausible-looking small fills. Unknown is correct.
        XCTAssertNil(fill("34000000"))
    }

    func testZeroIsPreservedNotTreatedAsUnknown() {
        // The whole point: a zero fill is a real outcome and must survive.
        XCTAssertEqual(fill("0"), 0)
        XCTAssertNotNil(fill("0"))
    }

    func testValueLargerThanRequestedBecomesUnknown() {
        // Can't be a fill of a 50-share order; refuse to guess what it is.
        XCTAssertNil(fill("12345"))
    }

    func testSmallGenuinePartialFillIsStillReported() {
        // A real fill can legitimately be tiny — the ceiling must not swallow it.
        XCTAssertEqual(fill("0.5"), 0.5)
    }

    func testGarbageIsUnknown() {
        XCTAssertNil(fill(nil))
        XCTAssertNil(fill(""))
        XCTAssertNil(fill("abc"))
        XCTAssertNil(fill(Double.nan))
        XCTAssertNil(fill(Double.infinity))
        XCTAssertNil(fill("-5"), "a negative fill is nonsense, not a number to show")
    }

    func testNoRequestedSizeMeansNothingToReconcileAgainst() {
        XCTAssertNil(fill("34", requested: 0))
    }

    func testSlightOverFillIsAccepted() {
        XCTAssertEqual(fill("50.4"), 50.4, "rounding may exceed the request slightly")
    }
}
