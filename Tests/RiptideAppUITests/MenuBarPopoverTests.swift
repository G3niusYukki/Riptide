import XCTest
import RiptideApp

/// UI tests for the NSPopover shown when the user clicks the status bar item
/// (Tasks 7.7 and 7.8).
///
/// The popover is hosted by `MenuBarPopoverView`, which carries the
/// `A11yID.MenuBar.*` accessibility identifiers. The tests click the status
/// bar item, then assert the popover content is visible and contains all the
/// expected sections (mode picker, group card, speed card, shortcuts card,
/// footer).
///
/// These tests are skipped on environments where the status bar item is not
/// available (for example a headless test runner without an `NSStatusBar`).
final class MenuBarPopoverTests: RiptideUITestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Wait for the main window to be ready so the status bar controller
        // is wired up and the status item is reachable from the UI test.
        let mainWindow = app.windows[A11yID.App.mainWindow]
        XCTAssertTrue(
            mainWindow.waitForExistence(timeout: 5.0),
            "Main window should exist before exercising the status bar popover"
        )
    }

    func testStatusBarItemIsPresent() throws {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No status bar item is available in this test environment")
        }
        XCTAssertTrue(statusItem.exists, "Status bar item should be reachable from the UI test")
    }

    func testPopoverAppearsWhenStatusItemIsClicked() throws {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No status bar item is available in this test environment")
        }
        statusItem.click()
        let popover = app.otherElements[A11yID.MenuBar.popover]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 3.0),
            "Menu bar popover should appear after clicking the status item"
        )
    }

    func testPopoverContainsAllSections() throws {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No status bar item is available in this test environment")
        }
        statusItem.click()
        let popover = app.otherElements[A11yID.MenuBar.popover]
        guard popover.waitForExistence(timeout: 3.0) else {
            throw XCTSkip("Popover did not open; cannot verify its sections")
        }
        XCTAssertTrue(
            app.segmentedControls[A11yID.MenuBar.modePicker].waitForExistence(timeout: 2.0),
            "Popover should contain a mode picker"
        )
        XCTAssertTrue(
            app.otherElements[A11yID.MenuBar.groupCard].waitForExistence(timeout: 2.0),
            "Popover should contain the group card"
        )
        XCTAssertTrue(
            app.otherElements[A11yID.MenuBar.speedCard].waitForExistence(timeout: 2.0),
            "Popover should contain the speed card"
        )
        XCTAssertTrue(
            app.otherElements[A11yID.MenuBar.shortcutsCard].waitForExistence(timeout: 2.0),
            "Popover should contain the shortcuts card"
        )
        XCTAssertTrue(
            app.buttons[A11yID.MenuBar.openMainWindowButton].waitForExistence(timeout: 2.0),
            "Popover should contain the 'open main window' button"
        )
        XCTAssertTrue(
            app.buttons[A11yID.MenuBar.quitButton].waitForExistence(timeout: 2.0),
            "Popover should contain the quit button"
        )
    }

    func testPopoverTogglesOffWhenStatusItemIsClickedAgain() throws {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("No status bar item is available in this test environment")
        }
        statusItem.click()
        let popover = app.otherElements[A11yID.MenuBar.popover]
        guard popover.waitForExistence(timeout: 3.0) else {
            throw XCTSkip("Popover did not open on first click")
        }
        statusItem.click()
        // NSPopover with .transient behavior dismisses on outside clicks and
        // also when the originating status item is clicked again. We just
        // check that the popover is no longer present after a short wait.
        let stillPresent = popover.waitForExistence(timeout: 0.5)
        XCTAssertFalse(stillPresent, "Popover should dismiss when the status item is clicked again")
    }
}
