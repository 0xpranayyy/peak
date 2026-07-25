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
        XCTAssertEqual(PeakUserCopy.accountStatus("wallet is ready"), "You’re set up to trade.")
        XCTAssertEqual(PeakUserCopy.accountStatus("account synced"), "You’re set up to trade.")
    }

    func testAccountStatusStillDeploying() {
        XCTAssertEqual(PeakUserCopy.accountStatus("deposit wallet deploy pending"), "Setup still finishing. Try again in a moment.")
    }
}
