import Foundation
import Testing

@testable import Riptide

@Suite("Proxy Provider Health Checker")
struct ProxyProviderHealthCheckerTests {
    var checker: ProxyProviderHealthChecker!
    
    init() {
        checker = ProxyProviderHealthChecker()
    }
    
    @Test("checkProvider returns unhealthy for non-existent file")
    func testCheckProviderReturnsUnhealthy() async throws {
        let config = ProxyProviderConfig(
            name: "test-provider",
            type: "file",
            path: "/tmp/nonexistent.yaml"
        )
        let provider = ProxyProvider(config: config)
        
        let health = await checker.checkProvider(provider)
        
        #expect(health.status == .unhealthy)
        #expect(health.lastChecked <= Date())
        #expect(health.errorMessage != nil)
    }
    
    @Test("checkProvider returns healthy when nodes are available")
    func testCheckProviderHealthyWithNodes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("healthcheck-test-\(UUID().uuidString).yaml")
        
        let yaml = """
        mode: rule
        proxies:
          - name: "node-a"
            type: socks5
            server: 1.1.1.1
            port: 1080
        rules:
          - MATCH,DIRECT
        """
        try yaml.write(to: testFile, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: testFile)
        }
        
        let config = ProxyProviderConfig(name: "healthy-provider", type: "file", path: testFile.path)
        let provider = ProxyProvider(config: config)
        
        await provider.start()
        let health = await checker.checkProvider(provider)
        
        #expect(health.status == .healthy)
        #expect(health.latency != nil)
        #expect(health.errorMessage == nil)
    }
    
    @Test("getHealth returns stored health")
    func testGetHealthReturnsStoredHealth() async throws {
        let config = ProxyProviderConfig(name: "test", type: "file", path: "/tmp/test.yaml")
        let provider = ProxyProvider(config: config)
        
        _ = await checker.checkProvider(provider)
        let stored = await checker.getHealth(for: provider.id)
        
        #expect(stored != nil)
        #expect(stored?.status == .unhealthy)
    }
    
    @Test("startMonitoring creates task and stores health")
    func testStartMonitoringCreatesTask() async throws {
        let config = ProxyProviderConfig(name: "monitor-test", type: "file", path: "/tmp/test.yaml")
        let provider = ProxyProvider(config: config)
        
        await checker.startMonitoring(provider: provider, interval: 60)
        
        // Give it a moment to start the task
        try await Task.sleep(for: .milliseconds(100))
        
        let health = await checker.getHealth(for: provider.id)
        #expect(health != nil)
        
        await checker.stopMonitoring(providerID: provider.id)
    }
    
    @Test("stopMonitoring cancels task")
    func testStopMonitoringCancelsTask() async throws {
        let config = ProxyProviderConfig(name: "stop-test", type: "file", path: "/tmp/test.yaml")
        let provider = ProxyProvider(config: config)
        
        await checker.startMonitoring(provider: provider, interval: 3600)
        await checker.stopMonitoring(providerID: provider.id)
        
        let health = await checker.getHealth(for: provider.id)
        #expect(health != nil)
    }
    
    @Test("ProviderHealth structure is Equatable")
    func testProviderHealthStructureIsEquatable() throws {
        let date = Date()
        let health1 = ProviderHealth(status: .healthy, lastChecked: date, latency: 0.1, errorMessage: nil)
        let health2 = ProviderHealth(status: .healthy, lastChecked: date, latency: 0.1, errorMessage: nil)
        
        #expect(health1 == health2)
    }
    
    @Test("ProviderHealth Status values")
    func testProviderHealthStatusValues() throws {
        let healthy = ProviderHealth(status: .healthy, lastChecked: Date(), latency: 0.1, errorMessage: nil)
        let degraded = ProviderHealth(status: .degraded, lastChecked: Date(), latency: nil, errorMessage: "HTTP 500")
        let unhealthy = ProviderHealth(status: .unhealthy, lastChecked: Date(), latency: nil, errorMessage: "Connection refused")
        let unknown = ProviderHealth(status: .unknown, lastChecked: Date(), latency: nil, errorMessage: nil)
        
        #expect(healthy.status == .healthy)
        #expect(degraded.status == .degraded)
        #expect(unhealthy.status == .unhealthy)
        #expect(unknown.status == .unknown)
    }
}
