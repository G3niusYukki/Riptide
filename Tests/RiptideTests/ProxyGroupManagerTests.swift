import Foundation
import Testing
@testable import Riptide

// MARK: - Proxy Group Manager Tests

@Suite("Proxy Group Manager")
struct ProxyGroupManagerTests {

    @Test("selectBestProxy returns proxy with lowest delay")
    func selectBestProxyReturnsLowestDelay() async throws {
        let delays = [
            "proxy1": 200,
            "proxy2": 100,
            "proxy3": 300
        ]

        let best = ProxyGroupManager.selectBestProxy(from: ["proxy1", "proxy2", "proxy3"], delays: delays)

        #expect(best == "proxy2")
    }

    @Test("selectBestProxy returns first available when no delays measured")
    func selectBestProxyReturnsFirstWhenNoDelays() async throws {
        let delays: [String: Int] = [:]

        let best = ProxyGroupManager.selectBestProxy(from: ["proxy1", "proxy2"], delays: delays)

        #expect(best == "proxy1")
    }

    @Test("selectBestProxy skips proxies with timeout (nil delay)")
    func selectBestProxySkipsTimeouts() async throws {
        // Simulating delays where proxy1 failed (nil), proxy2 succeeded
        let delays: [String: Int] = [
            "proxy2": 150
        ]

        let best = ProxyGroupManager.selectBestProxy(from: ["proxy1", "proxy2"], delays: delays)

        // Should select proxy2 since proxy1 has no delay (timeout)
        #expect(best == "proxy2")
    }

    @Test("shouldAutoTest returns true for url-test groups")
    func shouldAutoTestUrlTest() async throws {
        let group = ProxyGroup(
            id: "auto",
            kind: .urlTest,
            proxies: ["p1", "p2"],
            interval: 300
        )

        #expect(ProxyGroupManager.shouldAutoTest(group: group) == true)
    }

    @Test("shouldAutoTest returns true for fallback groups")
    func shouldAutoTestFallback() async throws {
        let group = ProxyGroup(
            id: "fallback",
            kind: .fallback,
            proxies: ["p1", "p2"],
            interval: 300
        )

        #expect(ProxyGroupManager.shouldAutoTest(group: group) == true)
    }

    @Test("shouldAutoTest returns false for select groups")
    func shouldAutoTestSelect() async throws {
        let group = ProxyGroup(
            id: "manual",
            kind: .select,
            proxies: ["p1", "p2"]
        )

        #expect(ProxyGroupManager.shouldAutoTest(group: group) == false)
    }

    @Test("delay status color returns correct colors")
    func delayStatusColor() async throws {
        #expect(ProxyGroupManager.delayStatusColor(50) == .green)
        #expect(ProxyGroupManager.delayStatusColor(150) == .yellow)
        #expect(ProxyGroupManager.delayStatusColor(350) == .red)
        #expect(ProxyGroupManager.delayStatusColor(nil) == .gray)
    }
}
