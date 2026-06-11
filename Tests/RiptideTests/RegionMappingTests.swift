import XCTest
@testable import RiptideApp

final class RegionMappingTests: XCTestCase {
    func testChineseRegionKeywords() {
        XCTAssertEqual(RegionMapping.isoCode(for: "香港01"), "HK")
        XCTAssertEqual(RegionMapping.isoCode(for: "日本东京"), "JP")
        XCTAssertEqual(RegionMapping.isoCode(for: "美国-洛杉矶"), "US")
        XCTAssertEqual(RegionMapping.isoCode(for: "新加坡节点"), "SG")
        XCTAssertEqual(RegionMapping.isoCode(for: "台湾Hinet"), "TW")
        XCTAssertEqual(RegionMapping.isoCode(for: "韩国首尔"), "KR")
        XCTAssertNil(RegionMapping.isoCode(for: "未知节点"))
    }

    func testEnglishRegionKeywords() {
        XCTAssertEqual(RegionMapping.isoCode(for: "JP-Tokyo-01"), "JP")
        XCTAssertEqual(RegionMapping.isoCode(for: "US_Los_Angeles"), "US")
        XCTAssertEqual(RegionMapping.isoCode(for: "SG Premium"), "SG")
    }

    func testCaseInsensitiveMatching() {
        XCTAssertEqual(RegionMapping.isoCode(for: "jp-tokyo"), "JP")
        XCTAssertEqual(RegionMapping.isoCode(for: "US-WEST"), "US")
    }

    func testFirstMatchWins() {
        // "英国" (GB) must match first even when bare "UK" substring would also match.
        XCTAssertEqual(RegionMapping.isoCode(for: "英国 节点"), "GB")
    }
}
