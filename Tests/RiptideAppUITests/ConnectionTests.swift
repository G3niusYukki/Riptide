import XCTest
import RiptideApp

final class ConnectionTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        app.buttons[A11yID.Tab.traffic].tap()
    }

    func testChartVisible() {
        let chart = app.otherElements[A11yID.Traffic.chart]
        waitForElement(chart)
    }

    func testConnectionListOrEmptyState() {
        let anyConn = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", A11yID.Traffic.connectionRow))
            .firstMatch
        let emptyState = app.staticTexts
            .matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                "no connection",
                "no active",
                "暂无连接"
            ))
            .firstMatch
        let hasConnections = anyConn.waitForExistence(timeout: 3.0)
        let hasEmptyState = emptyState.exists
        XCTAssertTrue(
            hasConnections || hasEmptyState,
            "Should show either connections or empty state on the traffic tab"
        )
    }
}
