import XCTest
import RiptideApp

final class LaunchAgentTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        let settingsTab = app.buttons[A11yID.Tab.settings]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5.0), "Settings tab should exist")
        settingsTab.tap()
    }

    func testLaunchAtLoginToggleExists() {
        let toggle = app.switches[A11yID.Settings.launchAtLogin]
        waitForElement(toggle)
    }

    func testLaunchAtLoginToggleIsTappable() {
        let toggle = app.switches[A11yID.Settings.launchAtLogin]
        waitForElement(toggle)
        let initialValue = toggle.value as? String
        toggle.tap()
        let newValue = toggle.value as? String
        XCTAssertNotEqual(initialValue, newValue, "Toggle should change state when tapped")
    }
}
