import XCTest
@testable import Peak

/// The leaderboard row's display logic — which name to show, the short wallet,
/// the monogram — is pure and was shipped untested. A wrong branch here shows a
/// 60-character machine string where a name should be, so it's pinned.
final class LeaderboardEntryTests: XCTestCase {

    private func decode(_ json: String) throws -> LeaderboardEntry {
        try JSONDecoder().decode(LeaderboardEntry.self, from: Data(json.utf8))
    }

    func testPseudonymWins() throws {
        let e = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":100,"pseudonym":"swisstony","name":"whatever","profileImage":""}"#)
        XCTAssertEqual(e.displayName, "swisstony")
    }

    func testFallsBackToNameWhenPseudonymEmpty() throws {
        let e = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":100,"pseudonym":"","name":"asparagus2012","profileImage":""}"#)
        XCTAssertEqual(e.displayName, "asparagus2012")
    }

    func testWalletLikePseudonymShowsShortWalletNotTheMachineString() throws {
        // Traders who never set a name get "<wallet>-<timestamp>" as pseudonym.
        let e = try decode(#"{"proxyWallet":"0x2c335066FE58fe9237c3d3Dc7b275C2a034a0563","amount":100,"pseudonym":"0x2c335066FE58fe9237c3d3Dc7b275C2a034a0563-1759935795465","name":"","profileImage":""}"#)
        XCTAssertEqual(e.displayName, "0x2c33…0563", "a 0x pseudonym must collapse to the short wallet")
    }

    func testEmptyNameAndPseudonymShowsShortWallet() throws {
        let e = try decode(#"{"proxyWallet":"0x204f72f35326db932158cba6adff0b9a1da95e14","amount":100,"pseudonym":"","name":"","profileImage":""}"#)
        XCTAssertEqual(e.displayName, "0x204f…5e14")
    }

    func testShortWalletLeavesAlreadyShortValuesAlone() throws {
        let e = try decode(#"{"proxyWallet":"0xshort","amount":0,"pseudonym":"","name":"","profileImage":""}"#)
        XCTAssertEqual(e.shortWallet, "0xshort")
    }

    func testMonogramIsFirstAlphanumeric() throws {
        let named = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":0,"pseudonym":"maz26","name":"","profileImage":""}"#)
        XCTAssertEqual(named.monogram, "M")
        // Wallet-only display starts with "0" -> monogram is a digit, still fine.
        let wallet = try decode(#"{"proxyWallet":"0x204f72f35326db932158cba6adff0b9a1da95e14","amount":0,"pseudonym":"","name":"","profileImage":""}"#)
        XCTAssertEqual(wallet.monogram, "0")
    }

    func testProfileImageURLNilWhenEmpty() throws {
        let none = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":0,"pseudonym":"x","name":"","profileImage":""}"#)
        XCTAssertNil(none.profileImageURL)
        let some = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":0,"pseudonym":"x","name":"","profileImage":"https://img.example/a.png"}"#)
        XCTAssertNotNil(some.profileImageURL)
    }

    func testRankDefaultsToZeroAndIsNotDecoded() throws {
        // The API carries no rank; it's assigned from list order after fetch.
        let e = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234","amount":100,"pseudonym":"x","name":"","profileImage":"","rank":99}"#)
        XCTAssertEqual(e.rank, 0, "rank must come from list order, never from the payload")
    }

    func testLenientDecodeSurvivesMissingFields() throws {
        // A malformed/partial row must not throw — it degrades, not crashes.
        let e = try decode(#"{"proxyWallet":"0xabc0000000000000000000000000000000001234"}"#)
        XCTAssertEqual(e.amount, 0)
        XCTAssertEqual(e.displayName, "0xabc0…1234")
    }

    func testAssigningRankFromListOrder() throws {
        // Mirrors LeaderboardAPI.fetch: decode array, then number them.
        let arrayJSON = #"[{"proxyWallet":"0xa000000000000000000000000000000000000001","amount":9,"pseudonym":"a","name":"","profileImage":""},{"proxyWallet":"0xb000000000000000000000000000000000000002","amount":8,"pseudonym":"b","name":"","profileImage":""}]"#
        var list = try JSONDecoder().decode([LeaderboardEntry].self, from: Data(arrayJSON.utf8))
        for i in list.indices { list[i].rank = i + 1 }
        XCTAssertEqual(list.map(\.rank), [1, 2])
        XCTAssertEqual(list[0].displayName, "a")
    }
}
