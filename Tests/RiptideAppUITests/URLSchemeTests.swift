import XCTest
import RiptideApp

/// Tests for the `riptide://` URL scheme parser.
///
/// The URL scheme is only delivered to a fully installed .app bundle (the
/// Info.plist must contain a CFBundleURLTypes entry), so end-to-end routing
/// can only be exercised in a packaged app — not by `swift test`. The parser
/// itself is pure logic and is fully testable here, and that is what the spec
/// requires us to cover.
final class URLSchemeTests: RiptideUITestCase {

    func testParseSwitchGroupURL() {
        let url = URL(string: "riptide://switch?group=PROXY")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .switchGroup(name: "PROXY"))
    }

    func testParseSelectNodeURL() {
        let url = URL(string: "riptide://select?node=test-ss-01")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .selectNode(name: "test-ss-01"))
    }

    func testParseModeURLTun() {
        let url = URL(string: "riptide://mode?value=tun")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .setMode(value: "tun"))
    }

    func testParseModeURLSystem() {
        let url = URL(string: "riptide://mode?value=system")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .setMode(value: "system"))
    }

    func testParseModeURLOff() {
        let url = URL(string: "riptide://mode?value=off")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .setMode(value: "off"))
    }

    func testParseImportSubscriptionURL() {
        let url = URL(string: "riptide://import?url=https%3A%2F%2Fexample.com%2Fsub")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .importSubscription(url: "https://example.com/sub"))
    }

    func testParseDiagnosticsURL() {
        let url = URL(string: "riptide://diagnostics")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .runDiagnostics)
    }

    func testParseInvalidScheme() {
        let url = URL(string: "https://example.com")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testParseUnknownHost() {
        let url = URL(string: "riptide://unknown?foo=bar")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testParseSwitchGroupWithoutNameReturnsNil() {
        let url = URL(string: "riptide://switch")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testParseSelectNodeWithoutNodeReturnsNil() {
        let url = URL(string: "riptide://select")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertNil(action)
    }

    func testParseAcceptsNameAliasForGroup() {
        // Some URL builders may use ?name= instead of ?group=; both should work.
        let url = URL(string: "riptide://switch?name=PROXY")!
        let action = URLSchemeHandler.parse(url)
        XCTAssertEqual(action, .switchGroup(name: "PROXY"))
    }
}
