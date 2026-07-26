import XCTest
@testable import Peak

final class PeakUserCopyTests: XCTestCase {
    func testNetworkMessageOfflineCases() {
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.notConnectedToInternet)), PeakUserCopy.offline)
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.networkConnectionLost)), PeakUserCopy.offline)
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.dataNotAllowed)), PeakUserCopy.offline)
    }

    func testNetworkMessageTimeout() {
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.timedOut)), PeakUserCopy.timedOut)
    }

    func testMarketsUnreachableCopy() {
        XCTAssertFalse(PeakUserCopy.marketsUnreachable.isEmpty)
        XCTAssertTrue(PeakUserCopy.marketsUnreachable.lowercased().contains("polymarket"))
    }

    func testNetworkMessageCannotConnect() {
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.cannotFindHost)), PeakUserCopy.couldNotConnect)
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.cannotConnectToHost)), PeakUserCopy.couldNotConnect)
        XCTAssertEqual(PeakUserCopy.networkMessage(for: URLError(.dnsLookupFailed)), PeakUserCopy.couldNotConnect)
    }

    func testNetworkMessageNilForUnmappedURLErrorCode() {
        XCTAssertNil(PeakUserCopy.networkMessage(for: URLError(.badURL)))
    }

    func testNetworkMessageNilForNonNetworkError() {
        struct SomeOtherError: Error {}
        XCTAssertNil(PeakUserCopy.networkMessage(for: SomeOtherError()))
    }

    func testAccountStatusMissingAccount() {
        XCTAssertEqual(
            PeakUserCopy.accountStatus("No Polymarket account found for this signer"),
            PeakUserCopy.missingPolymarketAccount
        )
    }

    func testAccountStatusReady() {
        XCTAssertEqual(PeakUserCopy.accountStatus("wallet is ready"), PeakUserCopy.readyToTrade)
        XCTAssertEqual(PeakUserCopy.accountStatus("account synced"), PeakUserCopy.readyToTrade)
    }

    func testAccountStatusStillDeploying() {
        XCTAssertEqual(PeakUserCopy.accountStatus("deposit wallet deploy pending"), "Setup still finishing. Try again in a moment.")
    }

    func testAccountStatusLinkedProxyJargon() {
        XCTAssertEqual(
            PeakUserCopy.accountStatus("Imported. Linked to POLY_PROXY."),
            PeakUserCopy.connectedPolymarketAccount
        )
        XCTAssertEqual(
            PeakUserCopy.accountStatus("Linked POLY_PROXY: 0xabc"),
            PeakUserCopy.connectedPolymarketAccount
        )
        XCTAssertEqual(
            PeakUserCopy.accountStatus("Connected to your Polymarket account. Ready to trade."),
            PeakUserCopy.connectedPolymarketAccount
        )
    }

    func testWalletAuthFailureCopy() {
        XCTAssertEqual(
            PeakUserCopy.sanitizeOrderOrServerCopy(
                #"401 {"error":"No valid authorization keys or user signing keys available"}"#,
                fallback: "fallback"
            ),
            PeakUserCopy.walletAuthFailed
        )
    }
}

/// User-facing copy should say what happened, why, and what to do — and must
/// never blame the wrong party or name a unit that doesn't apply.
final class ErrorCopyQualityTests: XCTestCase {
    private let userFacing: [TradingError] = [
        .notConfigured, .notAvailable, .invalidAmount, .missingToken,
        .marketClosed, .setupRequired, .builderNotReady,
    ]

    func testEveryErrorHasCopy() {
        for error in userFacing {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "\(error) has no description")
            XCTAssertGreaterThan(text.count, 15, "\(error) copy is too terse to be useful")
        }
    }

    func testNoInfrastructureJargonLeaks() {
        let banned = ["clob", "fok", "builder credential", "funder", "signature_type", "nil", "null"]
        for error in userFacing {
            let lower = (error.errorDescription ?? "").lowercased()
            for word in banned {
                XCTAssertFalse(lower.contains(word), "\(error) leaks '\(word)'")
            }
        }
    }

    /// Buys are in dollars, sells in shares, so a shared message must not claim
    /// either. This previously read "Enter a valid USD amount".
    func testInvalidAmountIsUnitAgnostic() {
        let text = (TradingError.invalidAmount.errorDescription ?? "").lowercased()
        XCTAssertFalse(text.contains("usd"))
        XCTAssertFalse(text.contains("dollar"))
    }

    /// Missing Builder credentials are our problem; users sent to fix their
    /// wallet are being sent to fix something that works.
    func testBuilderNotReadyDoesNotBlameTheWallet() {
        let text = (TradingError.builderNotReady.errorDescription ?? "").lowercased()
        XCTAssertFalse(text.contains("your wallet isn’t ready"))
        XCTAssertTrue(text.contains("our side") || text.contains("not your wallet"))
    }
}
