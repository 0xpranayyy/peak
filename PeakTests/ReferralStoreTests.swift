import XCTest
@testable import Peak

/// URL parsing is the part of ReferralStore worth pinning: a wrong host
/// match would mean any link (or a malicious one) could set a pending
/// referral code, and a too-loose path match would misfire on the app's own
/// other deep links (WalletConnect) rather than falling through to them.
@MainActor
final class ReferralStoreTests: XCTestCase {

    private let key = "peak.referral.pendingCode"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testValidInviteLinkIsRecognizedAndStoresTheCode() {
        let handled = ReferralStore.shared.handleIncomingURL(url("https://peakapp.site/invite/ABCD123"))
        XCTAssertTrue(handled)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "ABCD123")
    }

    func testWrongHostIsNotClaimed() {
        UserDefaults.standard.removeObject(forKey: key)
        let handled = ReferralStore.shared.handleIncomingURL(url("https://evil.example/invite/ABCD123"))
        XCTAssertFalse(handled, "only peakapp.site links are ours")
        XCTAssertNil(UserDefaults.standard.string(forKey: key), "a foreign host must not set a pending code")
    }

    func testWalletConnectStyleLinkFallsThrough() {
        UserDefaults.standard.removeObject(forKey: key)
        // Not a real WalletConnect URL, just standing in for "some other
        // scheme this app also handles" -- the point is it must return
        // false so PeakApp.swift's onOpenURL falls through to it.
        let handled = ReferralStore.shared.handleIncomingURL(url("wc://pair?uri=abc"))
        XCTAssertFalse(handled)
    }

    func testMissingCodeSegmentIsNotClaimed() {
        UserDefaults.standard.removeObject(forKey: key)
        let handled = ReferralStore.shared.handleIncomingURL(url("https://peakapp.site/invite/"))
        XCTAssertFalse(handled, "a code-less invite path has nothing to redeem")
    }

    func testWrongPathIsNotClaimed() {
        UserDefaults.standard.removeObject(forKey: key)
        let handled = ReferralStore.shared.handleIncomingURL(url("https://peakapp.site/legal/privacy"))
        XCTAssertFalse(handled, "must not swallow the site's other real pages")
    }

    func testCodeIsStoredExactlyAsGiven() {
        // Case-normalization is the server's job (referralStore.mjs upper-
        // cases on redeem) -- the client should not silently transform it,
        // or a logged pending code stops matching what was actually tapped.
        _ = ReferralStore.shared.handleIncomingURL(url("https://peakapp.site/invite/aBc123"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "aBc123")
    }
}
