import XCTest

final class DesignTokenTests: XCTestCase {
    func testDesignTokensMatchShippedPalette() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RiptideApp/Design/design-tokens.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let color = json?["color"] as? [String: Any]
        let accent = color?["accent"] as? [String: String]
        XCTAssertEqual(accent?["light"], "1F6F6A")
        XCTAssertEqual(accent?["dark"], "8FCFC6")
        XCTAssertNotNil(color?["activity-card"])
        let space = json?["space"] as? [String: Int]
        XCTAssertEqual(space?["lg"], 16)
    }
}
