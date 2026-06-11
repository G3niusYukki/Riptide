import XCTest
import AppKit
@testable import RiptideApp

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func testNewActionsExist() {
        let actions = HotkeyManager.HotkeyAction.allCases
        XCTAssertTrue(actions.contains(.toggleSystemProxy))
        XCTAssertTrue(actions.contains(.switchNextNode))
        XCTAssertTrue(actions.contains(.testAllDelay))
    }

    func testActionDisplayNames() {
        XCTAssertEqual(HotkeyManager.HotkeyAction.toggleSystemProxy.displayName, "切换系统代理")
        XCTAssertEqual(HotkeyManager.HotkeyAction.switchNextNode.displayName, "下一节点")
        XCTAssertEqual(HotkeyManager.HotkeyAction.testAllDelay.displayName, "测试延迟")
    }

    func testDefaultShortcutsIncludeToggleTunnel() {
        let manager = HotkeyManager()
        XCTAssertFalse(manager.shortcuts.isEmpty)
    }
}
