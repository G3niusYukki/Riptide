import XCTest
@testable import RiptideApp
@testable import Riptide

final class ProxyTabFilterTests: XCTestCase {
    func testSortByDelayAscending() {
        let nodes = [
            makeNode(name: "a", delay: 300),
            makeNode(name: "b", delay: 100),
            makeNode(name: "c", delay: 200),
        ]
        let sorted = ProxyTabFilter.sort(nodes, by: .delayAscending)
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func testSortByDelayDescending() {
        let nodes = [
            makeNode(name: "a", delay: 100),
            makeNode(name: "b", delay: 300),
        ]
        let sorted = ProxyTabFilter.sort(nodes, by: .delayDescending)
        XCTAssertEqual(sorted.map(\.name), ["b", "a"])
    }

    func testFilterAvailable() {
        let nodes = [
            makeNode(name: "a", alive: true),
            makeNode(name: "b", alive: false),
        ]
        let filtered = ProxyTabFilter.filter(nodes, by: .available)
        XCTAssertEqual(filtered.map(\.name), ["a"])
    }

    func testFilterByRegion() {
        let nodes = [
            makeNode(name: "香港01"),
            makeNode(name: "JP-Tokyo"),
            makeNode(name: "未知节点"),
        ]
        let filtered = ProxyTabFilter.filter(nodes, by: .region("HK"))
        XCTAssertEqual(filtered.map(\.name), ["香港01"])
    }

    private func makeNode(name: String, delay: Int? = nil, alive: Bool = true) -> ProxyNodeDisplay {
        ProxyNodeDisplay(
            id: name,
            name: name,
            kind: .shadowsocks,
            delayMs: delay,
            isSelected: false,
            status: alive ? .available : .timeout
        )
    }
}
