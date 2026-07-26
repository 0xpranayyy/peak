import XCTest
@testable import Peak

final class TradingErrorMappingTests: XCTestCase {
    func testInsufficientFundsByCode() {
        let error = TradingError.fromServerMessage("some raw text", code: "insufficient_funds")
        guard case .insufficientFunds = error else {
            return XCTFail("expected .insufficientFunds, got \(error)")
        }
    }

    func testInsufficientSharesByMessageText() {
        let error = TradingError.fromServerMessage("not enough shares to sell", code: nil)
        guard case .insufficientFunds = error else {
            return XCTFail("expected .insufficientFunds, got \(error)")
        }
    }

    func testBuilderNotReady() {
        let error = TradingError.fromServerMessage("Builder credentials are missing", code: nil)
        guard case .builderNotReady = error else {
            return XCTFail("expected .builderNotReady, got \(error)")
        }
    }

    /// The backend maps CLOB's "couldn't be fully filled" to code `no_fill`, and
    /// the client keys off that code — not off the upstream wording.
    func testNoFillByCode() {
        let error = TradingError.fromServerMessage("couldn't be fully filled", code: "no_fill")
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testNoFillByMessageText() {
        for text in ["no fill at this price", "liquidity too thin"] {
            guard case .server = TradingError.fromServerMessage(text, code: nil) else {
                return XCTFail("expected .server for \(text)")
            }
        }
    }

    /// Empty upstream text must still yield usable copy rather than a blank alert.
    func testNoFillWithEmptyTextStillHasCopy() {
        guard case .server(let message) = TradingError.fromServerMessage("", code: "no_fill") else {
            return XCTFail("expected .server")
        }
        XCTAssertTrue(message.lowercased().contains("no fill"))
    }

    func testMarketClosed() {
        let error = TradingError.fromServerMessage("market is not accepting orders", code: "market_closed")
        guard case .marketClosed = error else {
            return XCTFail("expected .marketClosed, got \(error)")
        }
    }

    func testUnauthorizedMapsToNotConfigured() {
        let error = TradingError.fromServerMessage("unauthorized", code: nil)
        guard case .notConfigured = error else {
            return XCTFail("expected .notConfigured, got \(error)")
        }
    }

    func testSetupRequired() {
        let error = TradingError.fromServerMessage("finish trading/setup first", code: nil)
        guard case .setupRequired = error else {
            return XCTFail("expected .setupRequired, got \(error)")
        }
    }

    func testSetupFailedByCode() {
        let error = TradingError.fromServerMessage("raw deploy boom", code: "setup_failed")
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testSetupRequiredByCode() {
        let error = TradingError.fromServerMessage("Finish Set up trading first", code: "setup_required")
        guard case .setupRequired = error else {
            return XCTFail("expected .setupRequired, got \(error)")
        }
    }

    func testEmptyMessageFallsBackToGenericServerError() {
        let error = TradingError.fromServerMessage("", code: nil)
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testUnknownCodeFallsThroughToServer() {
        let error = TradingError.fromServerMessage("some unmapped upstream failure", code: "totally_unknown")
        guard case .server = error else {
            return XCTFail("expected .server, got \(error)")
        }
    }

    func testImportWalletRequiredByCode() {
        let error = TradingError.fromServerMessage("raw", code: "import_wallet_required")
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertTrue(PeakUserCopy.isImportWalletMessage(message))
        XCTAssertTrue(error.isImportWalletRequired)
    }

    func testSignFailedFromTypedDataBlob() {
        let error = TradingError.fromServerMessage(
            #"{"error":"invalid_data","message":"params required","unrecognized_keys":["typed_data"]}"#,
            code: nil
        )
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertEqual(message, PeakUserCopy.signFailed)
        XCTAssertFalse(message.contains("typed_data"))
        XCTAssertFalse(message.hasPrefix("{"))
    }

    func testApprovalsFailedByCode() {
        let error = TradingError.fromServerMessage("raw", code: "approvals_failed")
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertEqual(message, PeakUserCopy.approvalsNeeded)
    }

    func testWalletAuthFailedByCode() {
        let error = TradingError.fromServerMessage("raw", code: "wallet_auth_failed")
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertEqual(message, PeakUserCopy.walletAuthFailed)
    }

    func testWalletAuthFailedFromPrivy401Blob() {
        let error = TradingError.fromServerMessage(
            #"401 {"error":"No valid authorization keys or user signing keys available"}"#,
            code: nil
        )
        guard case .server(let message) = error else {
            return XCTFail("expected .server, got \(error)")
        }
        XCTAssertEqual(message, PeakUserCopy.walletAuthFailed)
        XCTAssertFalse(message.hasPrefix("{"))
        XCTAssertFalse(message.contains("401"))
    }
}

final class OpenOrderTests: XCTestCase {
    func testRemainingNeverGoesNegative() {
        let order = OpenOrder(
            id: "1", tokenID: "t", market: nil, side: "BUY",
            price: 0.5, originalSize: 10, sizeMatched: 15, status: nil
        )
        XCTAssertEqual(order.remaining, 0)
    }

    func testRemainingSubtractsMatchedSize() {
        let order = OpenOrder(
            id: "1", tokenID: "t", market: nil, side: "BUY",
            price: 0.5, originalSize: 10, sizeMatched: 4, status: nil
        )
        XCTAssertEqual(order.remaining, 6, accuracy: 0.0001)
    }
}

final class TradingPathFlagsTests: XCTestCase {
    func testRoundTripsThroughServerDict() {
        var flags = TradingPathFlags()
        flags.path = "new"
        flags.signer = "0xabc"
        flags.accountWallet = "0xdef"
        flags.walletTypeName = "DEPOSIT_WALLET"
        flags.syncReady = true
        flags.needsDeploy = false
        flags.builderConfigured = true
        flags.relayerConfigured = false

        let dict = flags.asServerDict()
        XCTAssertEqual(dict["path"] as? String, "new")
        XCTAssertEqual(dict["accountWallet"] as? String, "0xdef")
        XCTAssertEqual(dict["syncReady"] as? Bool, true)
        XCTAssertEqual(dict["relayerConfigured"] as? Bool, false)
    }

    func testFromPortfolioRootFallsBackToFunderWhenNoAccountWallet() {
        let root: [String: Any] = [
            "path": "existing",
            "funder": "0xfeeddead",
            "ready": true,
        ]
        let flags = TradingPathFlags.fromPortfolioRoot(root)
        XCTAssertEqual(flags.accountWallet, "0xfeeddead")
        XCTAssertEqual(flags.syncReady, true)
    }
}
