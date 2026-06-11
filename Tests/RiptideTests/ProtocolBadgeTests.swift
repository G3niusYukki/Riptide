import XCTest
import SwiftUI
@testable import RiptideApp
@testable import Riptide

final class ProtocolBadgeTests: XCTestCase {
    func testColorForKnownKinds() {
        XCTAssertEqual(ProtocolBadge.color(for: .shadowsocks), Color(hex: "0fbcf9"))
        XCTAssertEqual(ProtocolBadge.color(for: .vmess), Color(hex: "a55eea"))
        XCTAssertEqual(ProtocolBadge.color(for: .trojan), Color(hex: "f0932b"))
    }

    func testColorForRelay() {
        XCTAssertEqual(ProtocolBadge.color(for: .relay), Color(hex: "95afc0"))
    }

    func testLabelForReality() {
        // Reality is a transport modifier, displayed as "VLESS+Reality"
        XCTAssertEqual(ProtocolBadge.label(for: .reality), "VLESS+Reality")
    }

    func testLabelForStandardKinds() {
        XCTAssertEqual(ProtocolBadge.label(for: .shadowsocks), "SS")
        XCTAssertEqual(ProtocolBadge.label(for: .hysteria2), "Hy2")
        XCTAssertEqual(ProtocolBadge.label(for: .wireguard), "WG")
    }
}
