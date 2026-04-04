import Foundation
import Testing

@testable import Riptide

// MARK: - Mock MihomoRuntimeManager

/// A mock implementation of MihomoRuntimeManaging for testing.
actor MockMihomoRuntimeManager: MihomoRuntimeManaging {
    var isRunning: Bool = false
    var currentMode: RuntimeMode? = nil
    var currentProfile: TunnelProfile? = nil
    let helperConnection: HelperToolConnection = HelperToolConnection()

    // Configuration state
    var shouldThrowOnStart: Error? = nil
    var shouldThrowOnStop: Error? = nil
    var mockTraffic: (up: Int, down: Int) = (0, 0)
    var mockConnections: [ConnectionInfo] = []
    var mockProxies: [ProxyInfo] = []
    var mockDelays: [String: Int] = [:]  // proxy name -> delay
    var shouldFailDelayFor: String? = nil

    // Configuration methods (isolated)
    func configureThrowOnStart(_ error: Error?) {
        shouldThrowOnStart = error
    }

    func configureThrowOnStop(_ error: Error?) {
        shouldThrowOnStop = error
    }

    func configureMockTraffic(_ traffic: (up: Int, down: Int)) {
        mockTraffic = traffic
    }

    func configureMockConnections(_ connections: [ConnectionInfo]) {
        mockConnections = connections
    }

    func configureMockProxies(_ proxies: [ProxyInfo]) {
        mockProxies = proxies
    }

    func configureMockDelay(_ delay: Int, for proxyName: String) {
        mockDelays[proxyName] = delay
    }

    func configureFailDelay(for proxyName: String) {
        shouldFailDelayFor = proxyName
    }

    func setup() async throws {
        // No-op for mock
    }

    func start(mode: RuntimeMode, profile: TunnelProfile) async throws {
        if let error = shouldThrowOnStart {
            throw error
        }
        isRunning = true
        currentMode = mode
        currentProfile = profile
    }

    func stop() async throws {
        if let error = shouldThrowOnStop {
            throw error
        }
        isRunning = false
        currentMode = nil
    }

    func switchProxy(to proxyName: String) async throws {
        guard isRunning else {
            throw RuntimeError.notRunning
        }
    }

    func getProxyStatus() async throws -> [ProxyInfo] {
        guard isRunning else {
            throw RuntimeError.notRunning
        }
        return mockProxies
    }

    func getConnections() async throws -> [ConnectionInfo] {
        guard isRunning else {
            throw RuntimeError.notRunning
        }
        return mockConnections
    }

    func getTraffic() async throws -> (up: Int, down: Int) {
        guard isRunning else {
            throw RuntimeError.notRunning
        }
        return mockTraffic
    }

    func testProxyDelay(name: String, url: String?, timeout: Int) async throws -> Int {
        guard isRunning else {
            throw RuntimeError.notRunning
        }
        if let failProxy = shouldFailDelayFor, failProxy == name {
            throw RuntimeError.apiNotAvailable
        }
        return mockDelays[name] ?? 999
    }
}

// MARK: - Tests

@Suite("Mihomo runtime manager")
struct MihomoRuntimeManagerTests {
    @Test("mock manager starts not running")
    func mockStartsNotRunning() async throws {
        let manager = MockMihomoRuntimeManager()
        #expect(await manager.isRunning == false)
        #expect(await manager.currentMode == nil)
    }

    @Test("mock manager starts and stops")
    func mockStartAndStop() async throws {
        let manager = MockMihomoRuntimeManager()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        #expect(await manager.isRunning == true)
        #expect(await manager.currentMode == .systemProxy)
        #expect(await manager.currentProfile?.name == "test")

        try await manager.stop()
        #expect(await manager.isRunning == false)
        #expect(await manager.currentMode == nil)
    }

    @Test("mock manager throws on start when configured")
    func mockThrowsOnStart() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureThrowOnStart(RuntimeError.helperNotInstalled)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        do {
            try await manager.start(mode: .systemProxy, profile: profile)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }
        #expect(await manager.isRunning == false)
    }

    @Test("mock manager returns traffic when running")
    func mockReturnsTraffic() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureMockTraffic((up: 1024, down: 2048))

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        let traffic = try await manager.getTraffic()
        #expect(traffic.up == 1024)
        #expect(traffic.down == 2048)
    }

    @Test("mock manager throws when getting traffic while not running")
    func mockThrowsTrafficWhenNotRunning() async throws {
        let manager = MockMihomoRuntimeManager()

        do {
            _ = try await manager.getTraffic()
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }
    }
}

@Suite("Mode coordinator with mihomo")
struct ModeCoordinatorMihomoTests {
    @Test("mode coordinator starts in system proxy mode")
    func coordinatorStartsSystemProxy() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let mode = await coordinator.currentMode()
        #expect(mode == .systemProxy)
    }

    @Test("mode coordinator starts runtime in system proxy mode")
    func coordinatorStartsSystemProxyMode() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        #expect(await manager.isRunning == true)
        #expect(await manager.currentMode == .systemProxy)

        let events = await coordinator.recentEvents()
        let hasModeChanged = events.contains { event in
            if case .modeChanged(.systemProxy) = event { return true }
            return false
        }
        #expect(hasModeChanged)
    }

    @Test("mode coordinator starts runtime in TUN mode")
    func coordinatorStartsTunMode() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .tun, profile: profile)
        #expect(await manager.isRunning == true)
        #expect(await manager.currentMode == .tun)
    }

    @Test("mode coordinator requires profile to start")
    func coordinatorRequiresProfile() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)

        do {
            try await coordinator.start(mode: .systemProxy, profile: nil)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected
        }
    }

    @Test("mode coordinator surfaces fallback recommendation when start fails")
    func coordinatorSurfacesFallbackRecommendation() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureThrowOnStart(RuntimeError.helperNotInstalled)
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        do {
            try await coordinator.start(mode: .systemProxy, profile: profile)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected — the coordinator should throw after emitting the degraded event
        }
        let events = await coordinator.recentEvents()
        let hasDegraded = events.contains { event in
            if case .degraded(.systemProxy, _) = event { return true }
            return false
        }
        #expect(hasDegraded)
    }

    @Test("mode coordinator stops runtime")
    func coordinatorStop() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        #expect(await manager.isRunning == true)

        try await coordinator.stop()
        #expect(await manager.isRunning == false)
    }

    @Test("mode coordinator returns traffic stats")
    func coordinatorTrafficStats() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureMockTraffic((up: 1024, down: 2048))
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        let traffic = await coordinator.getTraffic()
        #expect(traffic.up == 1024)
        #expect(traffic.down == 2048)
    }

    @Test("mode coordinator returns zero traffic when not running")
    func coordinatorZeroTrafficWhenNotRunning() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)

        let traffic = await coordinator.getTraffic()
        #expect(traffic.up == 0)
        #expect(traffic.down == 0)
    }

    @Test("mode coordinator returns connection count")
    func coordinatorConnectionCount() async throws {
        let manager = MockMihomoRuntimeManager()
        let metadata1 = ConnectionMetadata(network: "tcp", type: "HTTP", sourceIP: "127.0.0.1", destinationIP: "1.2.3.4", host: "example.com")
        let metadata2 = ConnectionMetadata(network: "tcp", type: "HTTP", sourceIP: "127.0.0.1", destinationIP: "5.6.7.8", host: "test.com")
        let connections = [
            ConnectionInfo(id: UUID().uuidString, metadata: metadata1, upload: 100, download: 200),
            ConnectionInfo(id: UUID().uuidString, metadata: metadata2, upload: 50, download: 100)
        ]
        await manager.configureMockConnections(connections)
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        let connectionCount = await coordinator.getConnections()
        #expect(connectionCount == 2)
    }

    @Test("mode coordinator returns zero connections when not running")
    func coordinatorZeroConnectionsWhenNotRunning() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)

        let connections = await coordinator.getConnections()
        #expect(connections == 0)
    }

    @Test("mode coordinator checks helper installation status")
    func coordinatorChecksHelperInstallation() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)

        // Mock helper connection doesn't have a real helper installed
        let installed = await coordinator.isHelperInstalled()
        #expect(installed == false)
    }
}

// MARK: - Proxy Delay Tests

@Suite("Proxy delay testing")
struct ProxyDelayTests {

    @Test("testProxyDelay returns configured delay value")
    func testProxyDelayReturnsValue() async throws {
        let manager = MockMihomoRuntimeManager()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        await manager.configureMockDelay(150, for: "proxy1")

        let delay = try await manager.testProxyDelay(name: "proxy1", url: nil, timeout: 5000)

        #expect(delay == 150)
    }

    @Test("testProxyDelay throws when runtime not running")
    func testProxyDelayThrowsWhenNotRunning() async {
        let manager = MockMihomoRuntimeManager()
        // Don't start the manager

        await #expect(throws: RuntimeError.self) {
            _ = try await manager.testProxyDelay(name: "proxy1", url: nil, timeout: 5000)
        }
    }

    @Test("testProxyDelay propagates API errors when configured to fail")
    func testProxyDelayPropagatesErrors() async throws {
        let manager = MockMihomoRuntimeManager()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        await manager.configureFailDelay(for: "proxy1")

        await #expect(throws: RuntimeError.self) {
            _ = try await manager.testProxyDelay(name: "proxy1", url: nil, timeout: 5000)
        }
    }

    @Test("testProxyDelay returns default delay when not configured")
    func testProxyDelayReturnsDefault() async throws {
        let manager = MockMihomoRuntimeManager()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        // Don't configure any delay

        let delay = try await manager.testProxyDelay(name: "unknown-proxy", url: nil, timeout: 5000)

        #expect(delay == 999)
    }

    @Test("testProxyDelay returns different delays for different proxies")
    func testProxyDelayDifferentProxies() async throws {
        let manager = MockMihomoRuntimeManager()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await manager.start(mode: .systemProxy, profile: profile)
        await manager.configureMockDelay(100, for: "proxy1")
        await manager.configureMockDelay(250, for: "proxy2")
        await manager.configureMockDelay(500, for: "proxy3")

        let delay1 = try await manager.testProxyDelay(name: "proxy1", url: nil, timeout: 5000)
        let delay2 = try await manager.testProxyDelay(name: "proxy2", url: nil, timeout: 5000)
        let delay3 = try await manager.testProxyDelay(name: "proxy3", url: nil, timeout: 5000)

        #expect(delay1 == 100)
        #expect(delay2 == 250)
        #expect(delay3 == 500)
    }
}
