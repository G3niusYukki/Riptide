import Foundation
import Testing
@testable import Riptide

private actor EventLatch {
    private var isFulfilled = false
    private var continuation: CheckedContinuation<Void, Never>?
    
    func fulfill() {
        if !isFulfilled {
            isFulfilled = true
            continuation?.resume()
            continuation = nil
        }
    }
    
    func wait() async {
        if isFulfilled { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelWait() {
        continuation?.resume()
        continuation = nil
    }

    func wait(timeoutNanoseconds: UInt64) async -> Bool {
        if isFulfilled { return true }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.wait()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            if !result {
                self.cancelWait()
            }
            group.cancelAll()
            return result
        }
    }
}

@Suite("GoCoreTunnelRuntime Tests", .serialized)
struct GoCoreTunnelRuntimeTests {

    @Test("Test lifecycle of GoCoreTunnelRuntime")
    func testRuntimeLifecycle() async throws {
        guard isGitHubActionsRuntime == false else {
            return
        }

        try await withExclusiveGoCore {
            // Inject a mock proxy controller so the real OS system proxy is never
            // touched, while still verifying the system-proxy wiring end to end.
            let proxyController = MockSystemProxyController()
            let runtime = GoCoreTunnelRuntime(systemProxyController: proxyController)

            #expect(await runtime.isRunning == false)
            #expect(await runtime.currentMode == nil)
            #expect(await runtime.currentProfile == nil)

            // Mock profile and mode
            let dummyConfig = RiptideConfig(mode: .direct, proxies: [], rules: [])
            let dummyProfile = TunnelProfile(name: "TestProfile", config: dummyConfig)

            let latch = EventLatch()
            await runtime.setEventHandler { event in
                if case .stateChanged(let state) = event, state == .running {
                    Task {
                        await latch.fulfill()
                    }
                }
            }

            try await runtime.setup()
            try await runtime.start(mode: .systemProxy, profile: dummyProfile)

            #expect(await runtime.isRunning == true)
            #expect(await runtime.currentMode == .systemProxy)
            // System-proxy mode must point the OS proxy at sing-box's mixed listener.
            #expect(proxyController.currentState() == .enabled(httpPort: 6152, socksPort: 6152))

            let didReceiveRunningEvent = await latch.wait(timeoutNanoseconds: 2_000_000_000)
            #expect(didReceiveRunningEvent)

            let traffic = try await runtime.getTraffic()
            #expect(traffic.up == 102456)
            #expect(traffic.down == 509210)

            let status = try await runtime.getProxyStatus()
            #expect(status.count == 2)

            try await runtime.stop()

            #expect(await runtime.isRunning == false)
            #expect(await runtime.currentMode == nil)
            // Stopping must clear the system proxy.
            #expect(proxyController.currentState() == .disabled)
        }
    }

    // Strongest schema check: generate configs for every supported protocol and
    // feed them to the REAL linked sing-box core. If any outbound emits a wrong or
    // post-v1.9.0 field, sing-box rejects the config and start() throws.
    @Test("real sing-box core accepts generated vmess/vless-reality/hysteria2/tuic/trojan/ss")
    func realCoreAcceptsAllProtocols() async throws {
        guard isGitHubActionsRuntime == false else {
            return
        }
        let uuid = "bf000d23-0752-40b4-affe-68f7707a9661"
        let realityKey = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

        try await withExclusiveGoCore {
            let nodes: [ProxyNode] = [
                ProxyNode(name: "ss", kind: .shadowsocks, server: "1.2.3.4", port: 8388,
                          cipher: "aes-128-gcm", password: "pw"),
                ProxyNode(name: "vmess", kind: .vmess, server: "ex.com", port: 443,
                          uuid: uuid, alterId: 0, security: "auto", sni: "ex.com", tls: true,
                          network: "ws", wsPath: "/p", wsHost: "ex.com"),
                ProxyNode(name: "vless", kind: .vless, server: "ex.com", port: 443,
                          uuid: uuid, flow: "xtls-rprx-vision", network: "tcp",
                          realityServerName: "www.microsoft.com", realityShortId: "0123456789abcdef",
                          realityPublicKey: realityKey, realityFingerprint: "chrome"),
                ProxyNode(name: "vlessGrpc", kind: .vless, server: "ex.com", port: 443,
                          uuid: uuid, sni: "ex.com", tls: true, network: "grpc",
                          grpcServiceName: "GunService"),
                ProxyNode(name: "trojan", kind: .trojan, server: "ex.com", port: 443,
                          password: "pw", sni: "ex.com"),
                ProxyNode(name: "hy2", kind: .hysteria2, server: "ex.com", port: 443,
                          password: "pw", sni: "ex.com", skipCertVerify: true),
                ProxyNode(name: "tuic", kind: .tuic, server: "ex.com", port: 443,
                          password: "pw", uuid: uuid, alpn: ["h3"], congestionControl: "bbr"),
            ]
            let config = RiptideConfig(mode: .rule, proxies: nodes, rules: [.final(policy: .direct)])
            let profile = TunnelProfile(name: "AllProtocols", config: config)
            let runtime = GoCoreTunnelRuntime(systemProxyController: MockSystemProxyController())

            try await runtime.setup()
            // Throws if sing-box rejects any generated outbound's schema.
            try await runtime.start(mode: .systemProxy, profile: profile)
            #expect(await runtime.isRunning == true)
            try await runtime.stop()
        }
    }
}
