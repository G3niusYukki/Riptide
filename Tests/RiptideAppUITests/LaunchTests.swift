import XCTest
@testable import RiptideApp

final class LaunchTests: RiptideUITestCase {

    func testAppLaunchesAndShowsMainWindow() {
        let window = app.windows["app.main-window"]
        waitForElement(window)
        XCTAssertTrue(window.exists, "Main window should be visible after launch")
    }

    func testDashboardIsDefaultTab() {
        let dashboardTab = app.buttons[A11yID.Tab.dashboard]
        waitForElement(dashboardTab)
        XCTAssertTrue(dashboardTab.isSelected, "Dashboard tab should be selected by default")
    }

    func testAllTabsPresent() {
        let tabNames = [A11yID.Tab.dashboard, A11yID.Tab.config, A11yID.Tab.proxy, A11yID.Tab.traffic, A11yID.Tab.logs]
        for tabId in tabNames {
            let tab = app.buttons[tabId]
            XCTAssertTrue(tab.waitForExistence(timeout: 3.0), "Tab \(tabId) should exist")
        }
    }
}
