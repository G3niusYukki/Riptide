import XCTest

/// UI 测试的公共工具。所有 UI 测试类继承自 `RiptideUITestCase`。
@MainActor
open class RiptideUITestCase: XCTestCase {
    public var app: XCUIApplication!

    public override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // UI 测试环境标志:禁用 Sparkle 自动更新、禁用 mihomo 启动、加载测试订阅
        app.launchEnvironment["RIPTIDE_UI_TEST"] = "1"
        app.launchEnvironment["RIPTIDE_DISABLE_SPARKLE"] = "1"
        app.launchEnvironment["RIPTIDE_MIHOMO_SKIP_START"] = "1"
        app.launch()
    }

    public override func tearDown() async throws {
        app?.terminate()
        app = nil
        try await super.tearDown()
    }

    /// 等待并断言元素存在,带超时
    public func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0, file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(exists, "Element \(element.identifier) not found within \(timeout)s", file: file, line: line)
    }
}
