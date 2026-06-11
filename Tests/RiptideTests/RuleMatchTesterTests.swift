import XCTest
import Riptide
@testable import RiptideApp

final class RuleMatchTesterTests: XCTestCase {
    func testParseDomain() {
        let target = RuleTarget.parse("www.google.com")
        XCTAssertEqual(target.domain, "www.google.com")
        XCTAssertNil(target.ipAddress)
    }

    func testParseIPAddress() {
        let target = RuleTarget.parse("1.1.1.1")
        XCTAssertEqual(target.ipAddress, "1.1.1.1")
        XCTAssertNil(target.domain)
    }

    func testParseDomainWithPort() {
        let target = RuleTarget.parse("example.com:443")
        XCTAssertEqual(target.domain, "example.com")
        XCTAssertEqual(target.destinationPort, 443)
    }

    func testParseIPv6() {
        let target = RuleTarget.parse("::1")
        XCTAssertEqual(target.ipAddress, "::1")
    }
}
