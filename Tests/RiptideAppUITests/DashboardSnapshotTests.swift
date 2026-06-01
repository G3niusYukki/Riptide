import XCTest
import RiptideApp

final class DashboardSnapshotTests: RiptideUITestCase {

    func testAllDashboardCardsVisible() {
        waitForElement(app.otherElements[A11yID.Dashboard.modeCard])
        waitForElement(app.otherElements[A11yID.Dashboard.nodeCard])
        waitForElement(app.otherElements[A11yID.Dashboard.speedCard])
        waitForElement(app.buttons[A11yID.Dashboard.diagnosticsButton])
    }

    func testDiagnosticsButtonTriggersSheet() throws {
        let button = app.buttons[A11yID.Dashboard.diagnosticsButton]
        waitForElement(button)
        button.tap()
        // The sheet's primary run button "开始诊断" only exists in DiagnosticsView,
        // so matching it proves the sheet actually appeared (the dashboard's
        // "诊断" button is a different element with different label text).
        let runButtonPredicate = NSPredicate(format: "label CONTAINS[c] '开始诊断'")
        let runButton = app.buttons.matching(runButtonPredicate).firstMatch
        XCTAssertTrue(
            runButton.waitForExistence(timeout: 3.0),
            "Diagnostics sheet should appear with a '开始诊断' run button after tapping the diagnostics button"
        )
    }

    func testModeCardShowsCurrentMode() {
        let modeCard = app.otherElements[A11yID.Dashboard.modeCard]
        waitForElement(modeCard)
        let label = modeCard.staticTexts.firstMatch.label
        XCTAssertFalse(label.isEmpty, "Mode card should display the current mode label")
    }
}
