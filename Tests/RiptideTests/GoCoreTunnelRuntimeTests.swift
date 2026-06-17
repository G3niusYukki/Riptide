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

            // The rebuilt core reports real counters (0 until the clash-api traffic
            // manager is wired) rather than the previous hard-coded mock values.
            let traffic = try await runtime.getTraffic()
            #expect(traffic.up == 0)
            #expect(traffic.down == 0)

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

    @Test("a vless REALITY share-URI subscription parses into reality fields")
    func parsesVlessRealitySubscription() async throws {
        let uri = "vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443"
            + "?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome"
            + "&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0&sid=0123456789abcdef&type=tcp#Reality"
        let base64 = Data(uri.utf8).base64EncodedString()

        let nodes = try await SubscriptionManager().parseBase64URIList(base64)
        let node = try #require(nodes.first)
        #expect(node.kind == .vless)
        #expect(node.uuid == "11111111-2222-3333-4444-555555555555")
        #expect(node.tls == true)
        #expect(node.realityPublicKey == "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0")
        #expect(node.realityShortId == "0123456789abcdef")
        #expect(node.realityServerName == "www.microsoft.com")
        #expect(node.realityFingerprint == "chrome")
        #expect(node.network == "tcp")
    }

    // Manual end-to-end: parse a REAL subscription file and feed the generated
    // config to the real core. Gated behind an env var (the file holds private
    // credentials). Run with:
    //   RIPTIDE_TEST_SUB_FILE=/path/to/sub swift test --filter realCoreAcceptsRealSubscription
    @Test("real core accepts a real subscription (manual)")
    func realCoreAcceptsRealSubscription() async throws {
        guard isGitHubActionsRuntime == false,
              let subFile = ProcessInfo.processInfo.environment["RIPTIDE_TEST_SUB_FILE"],
              let content = try? String(contentsOfFile: subFile, encoding: .utf8) else {
            return
        }
        let nodes = try await SubscriptionManager().parseBase64URIList(content)
        #expect(!nodes.isEmpty)

        let config = RiptideConfig(mode: .rule, proxies: nodes, rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "RealSub", config: config)
        try await withExclusiveGoCore {
            let runtime = GoCoreTunnelRuntime(systemProxyController: MockSystemProxyController())
            try await runtime.setup()
            try await runtime.start(mode: .systemProxy, profile: profile)  // throws if core rejects
            #expect(await runtime.isRunning == true)
            try await runtime.stop()
        }
    }

    // TUN routes through the privileged daemon, never the in-process core. Inject
    // a pre-installed daemon over temp dirs so no elevation / real core is needed
    // (this runs on CI). Verifies config+flag are written, the system proxy is
    // untouched, and stop() drops the flag.
    @Test("TUN mode drives the launchd daemon (config + flag), not the in-process core or system proxy")
    func tunModeUsesDaemon() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-tun-rt-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let launchDaemons = root.appendingPathComponent("LaunchDaemons", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDaemons, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binary = support.appendingPathComponent("riptide-singbox")
        FileManager.default.createFile(atPath: binary.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        FileManager.default.createFile(
            atPath: launchDaemons.appendingPathComponent("\(TunDaemonController.daemonLabel).plist").path,
            contents: Data())

        let daemon = TunDaemonController(
            supportDir: support, launchDaemonsDir: launchDaemons, uid: 501, privilegedRunner: { _ in })
        let proxyController = MockSystemProxyController()
        let runtime = GoCoreTunnelRuntime(
            systemProxyController: proxyController, tunDaemon: daemon, tunBinaryLocator: { binary })

        let node = ProxyNode(name: "ss", kind: .shadowsocks, server: "1.2.3.4", port: 8388,
                             cipher: "aes-128-gcm", password: "pw")
        let config = RiptideConfig(mode: .rule, proxies: [node], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "TunProfile", config: config)

        try await runtime.setup()
        try await runtime.start(mode: .tun, profile: profile)

        #expect(await runtime.isRunning == true)
        #expect(await runtime.currentMode == .tun)
        // System proxy must NOT be touched in TUN mode.
        #expect(proxyController.currentState() == .disabled)

        let tunDir = support.appendingPathComponent("tun", isDirectory: true)
        let configPath = tunDir.appendingPathComponent("config.json")
        let flagPath = tunDir.appendingPathComponent("enabled")
        #expect(FileManager.default.fileExists(atPath: configPath.path))
        #expect(FileManager.default.fileExists(atPath: flagPath.path))
        let written = try String(contentsOf: configPath, encoding: .utf8)
        #expect(written.contains("\"tun\""))
        #expect(written.contains("auto_route"))

        try await runtime.stop()
        #expect(await runtime.isRunning == false)
        #expect(await runtime.currentMode == nil)
        // Stop drops the flag so launchd SIGTERMs the root core.
        #expect(FileManager.default.fileExists(atPath: flagPath.path) == false)
    }
}
