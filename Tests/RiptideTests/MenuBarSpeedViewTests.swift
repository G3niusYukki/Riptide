import XCTest
@testable import RiptideApp

final class MenuBarSpeedViewTests: XCTestCase {
    func testFormatZero() {
        XCTAssertEqual(MenuBarSpeedView.format(0), "<1K")
    }

    func testFormatBytes() {
        XCTAssertEqual(MenuBarSpeedView.format(500), "<1K")
        XCTAssertEqual(MenuBarSpeedView.format(999), "<1K")
    }

    func testFormatKilobytes() {
        XCTAssertEqual(MenuBarSpeedView.format(1_000), "1.0K")
        XCTAssertEqual(MenuBarSpeedView.format(1_500), "1.5K")
        XCTAssertEqual(MenuBarSpeedView.format(999_999), "1000.0K")
    }

    func testFormatMegabytes() {
        XCTAssertEqual(MenuBarSpeedView.format(1_000_000), "1.0M")
        XCTAssertEqual(MenuBarSpeedView.format(3_400_000), "3.4M")
    }

    func testFormatGigabytes() {
        XCTAssertEqual(MenuBarSpeedView.format(1_000_000_000), "1.0G")
    }
}
