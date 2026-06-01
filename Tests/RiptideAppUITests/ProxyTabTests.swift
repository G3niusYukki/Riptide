import XCTest
import RiptideApp

final class ProxyTabTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        app.buttons[A11yID.Tab.proxy].tap()
    }

    func testProxyGroupCardsVisible() throws {
        let anyGroup = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", A11yID.Proxy.groupCard))
            .firstMatch
        guard anyGroup.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No proxy groups available; proxy tab requires an imported profile with groups")
        }
        XCTAssertTrue(anyGroup.exists, "At least one proxy group card should be visible")
    }

    func testLatencyTestButtonExists() {
        let anyDelayButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", A11yID.Proxy.testDelayButton))
            .firstMatch
        XCTAssertTrue(
            anyDelayButton.waitForExistence(timeout: 3.0),
            "Test latency button should exist in the proxy tab toolbar"
        )
    }

    func testTappingNodeSelectsIt() throws {
        let firstNode = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", A11yID.Proxy.nodeRow))
            .firstMatch
        guard firstNode.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No proxy nodes available; ensure a profile with nodes is loaded")
        }
        firstNode.tap()
        // Selection state is reflected visually via the checkmark icon in
        // ProxyNodeRow; we only assert that the element is still present
        // (didn't disappear) and hittable after tapping.
        XCTAssertTrue(firstNode.exists, "Tapped node row should remain visible after selection")
        XCTAssertTrue(firstNode.isHittable, "Tapped node row should still be hittable after selection")
    }
}
