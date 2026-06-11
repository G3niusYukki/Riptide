import XCTest
@testable import RiptideApp

final class CountryFlagViewTests: XCTestCase {
    func testFlagEmojiForKnownCode() {
        XCTAssertEqual(RegionMapping.flagEmoji(for: "HK"), "🇭🇰")
        XCTAssertEqual(RegionMapping.flagEmoji(for: "JP"), "🇯🇵")
        XCTAssertEqual(RegionMapping.flagEmoji(for: "US"), "🇺🇸")
    }

    func testFlagEmojiForUnknownCode() {
        XCTAssertEqual(RegionMapping.flagEmoji(for: ""), "🌐")
        XCTAssertEqual(RegionMapping.flagEmoji(for: "XX"), "🌐")
    }

    func testFlagEmojiIsCaseInsensitive() {
        XCTAssertEqual(RegionMapping.flagEmoji(for: "hk"), "🇭🇰")
        XCTAssertEqual(RegionMapping.flagEmoji(for: "JP"), "🇯🇵")
    }
}
