import XCTest
@testable import Riptide

final class EngineRouterTests: XCTestCase {
    func test_router_routes_ss_to_mihomo_by_default() {
        let router = EngineRouter(policy: .defaultMihomo)
        let engine = router.engine(for: .shadowsocks)
        XCTAssertEqual(engine, .mihomo)
    }

    func test_router_routes_reality_to_singbox() {
        let router = EngineRouter(policy: .defaultMihomo)
        let engine = router.engine(for: .reality)
        XCTAssertEqual(engine, .singbox)
    }

    func test_router_falls_back_to_mihomo_for_unknown_kinds() {
        let router = EngineRouter(policy: .defaultMihomo)
        let engine = router.engine(for: .ssh)
        XCTAssertEqual(engine, .mihomo, "Unknown kinds must default to mihomo")
    }
}
