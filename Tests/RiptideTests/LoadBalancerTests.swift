import Foundation
import Testing
@testable import Riptide

/// FIX-1: LoadBalancer's consistent-hash seed must be per-instance stable
/// and the nil-host fallback must be deterministic. The old code re-seeded
/// `hashSeed = UInt64(Date()...)` on every `updateProxies` call AND used
/// `Date().timeIntervalSince1970` as the fallback key when host was nil —
/// both broke the documented "same host → same proxy" contract.
@Suite("LoadBalancer")
struct LoadBalancerTests {

    @Test("select for known host is stable across many calls")
    func selectForHostIsStableAcrossManyCalls() async {
        let balancer = LoadBalancer(strategy: .consistentHash)
        await balancer.updateProxies(["proxy-A", "proxy-B", "proxy-C", "proxy-D"])

        var first: String?
        for _ in 0..<100 {
            let s = await balancer.select(forHost: "api.example.com")
            if first == nil { first = s }
            #expect(s == first, "selection flipped mid-loop")
        }
        #expect(first != nil)
    }

    @Test("select for nil host returns the first proxy deterministically")
    func selectNilHostReturnsFirstProxy() async {
        let balancer = LoadBalancer(strategy: .consistentHash)
        await balancer.updateProxies(["alpha", "beta", "gamma"])

        let s = await balancer.select(forHost: nil)
        #expect(s == "alpha")
    }

    @Test("select for empty host returns the first proxy deterministically")
    func selectEmptyHostReturnsFirstProxy() async {
        let balancer = LoadBalancer(strategy: .consistentHash)
        await balancer.updateProxies(["alpha", "beta", "gamma"])

        let s = await balancer.select(forHost: "")
        #expect(s == "alpha")
    }

    @Test("selection for a host is stable when the proxy list is unchanged")
    func selectionIsStableAcrossUpdateProxies() async {
        let balancer = LoadBalancer(strategy: .consistentHash)
        await balancer.updateProxies(["proxy-A", "proxy-B"])
        let first = await balancer.select(forHost: "stable.example.com")

        // Calling updateProxies with the same list must NOT reseed the hash.
        // (The old code re-seeded from Date() here, breaking consistency.)
        await balancer.updateProxies(["proxy-A", "proxy-B"])
        let after = await balancer.select(forHost: "stable.example.com")

        #expect(first != nil)
        #expect(after == first, "re-seed on updateProxies broke stability")
    }

    @Test("round-robin cycles through proxies")
    func roundRobinCycles() async {
        let balancer = LoadBalancer(strategy: .roundRobin)
        await balancer.updateProxies(["p1", "p2", "p3"])

        let a = await balancer.select(forHost: "any")
        let b = await balancer.select(forHost: "any")
        let c = await balancer.select(forHost: "any")
        let d = await balancer.select(forHost: "any")

        #expect(a == "p1")
        #expect(b == "p2")
        #expect(c == "p3")
        #expect(d == "p1")
    }
}
