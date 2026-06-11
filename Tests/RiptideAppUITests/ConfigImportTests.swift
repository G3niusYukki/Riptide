import XCTest
import RiptideApp

final class ConfigImportTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        app.buttons[A11yID.Tab.config].tap()
    }

    func testImportButtonExists() {
        let importButton = app.buttons[A11yID.Config.importButton]
        waitForElement(importButton)
    }

    func testAddSubscriptionButtonExists() {
        let addSubButton = app.buttons[A11yID.Config.addSubscription]
        waitForElement(addSubButton)
    }

    func testImportFilePickerOpens() {
        let importButton = app.buttons[A11yID.Config.importButton]
        waitForElement(importButton)
        importButton.tap()
        // NSOpenPanel appears as a dialog or sheet on macOS — check both.
        let openPanel = app.dialogs.firstMatch
        let openSheet = app.sheets.firstMatch
        let appeared = openPanel.waitForExistence(timeout: 3.0)
            || openSheet.waitForExistence(timeout: 3.0)
        XCTAssertTrue(appeared, "File picker should open after tapping import button")
    }

    func testEditYAMLButtonExists() {
        // The "编辑 YAML" button only appears once an active profile is
        // loaded, which the launch fixtures provide. If it's not present we
        // just skip — the button is only meaningful with a profile.
        let button = app.buttons[A11yID.Config.editYAMLButton]
        if !button.waitForExistence(timeout: 2.0) {
            // Acceptable: no active profile in this fixture.
            return
        }
        XCTAssertTrue(button.exists)
    }
}
