import XCTest
@testable import Peak

/// Regression tests for the Release-safety predicates that keep production
/// builds from silently pointing at localhost / plain HTTP. See README:
/// "Release builds do not auto-use localhost ... outside DEBUG."
final class TradingConfigSecurityTests: XCTestCase {
    func testIsLocalhostRecognizesLoopbackHosts() {
        XCTAssertTrue(TradingConfigStore.isLocalhost("http://127.0.0.1:8080"))
        XCTAssertTrue(TradingConfigStore.isLocalhost("http://localhost:8080"))
        XCTAssertTrue(TradingConfigStore.isLocalhost("https://LOCALHOST/api"))
    }

    func testIsLocalhostFalseForRealHost() {
        XCTAssertFalse(TradingConfigStore.isLocalhost("https://peak-api-production-60b6.up.railway.app"))
    }

    func testReleaseAllowedRejectsLocalhost() {
        XCTAssertFalse(TradingConfigStore.isReleaseAllowedBackendURL("http://127.0.0.1:8080"))
        XCTAssertFalse(TradingConfigStore.isReleaseAllowedBackendURL("https://localhost:8080"))
    }

    func testReleaseAllowedRejectsPlainHTTP() {
        XCTAssertFalse(TradingConfigStore.isReleaseAllowedBackendURL("http://example.com"))
    }

    func testReleaseAllowedAcceptsHTTPSNonLocalHost() {
        XCTAssertTrue(TradingConfigStore.isReleaseAllowedBackendURL("https://peak-api-production-60b6.up.railway.app"))
    }

    func testSupersededHostDetectsOldRailwayBackend() {
        // A saved value here is valid HTTPS and non-local, so nothing else in
        // resolveBackendURL would replace it — but the host is unreachable on
        // ISPs that block it, which broke trading with "Couldn't connect".
        XCTAssertTrue(
            TradingConfigStore.isSupersededBackendHost(
                "https://peak-api-production-60b6.up.railway.app"
            )
        )
    }

    func testSupersededHostLeavesCurrentBackendAlone() {
        XCTAssertFalse(TradingConfigStore.isSupersededBackendHost("https://api.peakapp.site"))
        XCTAssertFalse(TradingConfigStore.isSupersededBackendHost("http://127.0.0.1:8080"))
        XCTAssertFalse(TradingConfigStore.isSupersededBackendHost("not a url"))
    }

    func testReleaseAllowedRejectsGarbageURL() {
        XCTAssertFalse(TradingConfigStore.isReleaseAllowedBackendURL("not a url"))
        XCTAssertFalse(TradingConfigStore.isReleaseAllowedBackendURL(""))
    }
}
