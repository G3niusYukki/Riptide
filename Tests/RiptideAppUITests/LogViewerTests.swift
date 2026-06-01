import XCTest
import RiptideApp

final class LogViewerTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        app.buttons[A11yID.Tab.logs].tap()
    }

    func testAllLogViewerControlsVisible() {
        waitForElement(app.segmentedControls[A11yID.Logs.levelFilter])
        waitForElement(app.searchFields[A11yID.Logs.searchField])
        waitForElement(app.buttons[A11yID.Logs.exportButton])
    }

    func testSearchAcceptsTextInput() {
        let searchField = app.searchFields[A11yID.Logs.searchField]
        waitForElement(searchField)
        searchField.tap()
        searchField.typeText("error")
        XCTAssertEqual(searchField.value as? String, "error")
    }
}
