import Foundation
import Testing

@testable import Riptide

@Suite("App shell workflow")
struct AppShellWorkflowTests {
    @Test("config import succeeds for valid YAML")
    func importSuccess() throws {
        let service = ConfigImportService()
        let result = try service.importProfile(name: "test", yaml: validYAML())

        #expect(result.profile.name == "test")
        #expect(result.profile.config.proxies.count == 1)
    }

    @Test("config import fails for invalid YAML")
    func importFailure() {
        let service = ConfigImportService()

        #expect(throws: ClashConfigError.self) {
            _ = try service.importProfile(name: "test", yaml: "not: [valid")
        }
    }

    @Test("stats pipeline maps running snapshot")
    func statsMapping() {
        let pipeline = RuntimeStatsPipeline()
        let snapshot = TunnelStatusSnapshot(
            state: .running,
            activeProfileName: "default",
            bytesUp: 100,
            bytesDown: 200,
            activeConnections: 5,
            lastError: nil
        )

        let state = pipeline.map(snapshot: snapshot)
        #expect(state.isRunning == true)
        #expect(state.profileName == "default")
        #expect(state.activeConnections == 5)
    }

    @Test("control view model start stop flow updates status")
    func controlViewModelFlow() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let control = TunnelControlViewModel(lifecycleManager: manager)

        let imported = try await control.importConfig(name: "default", yaml: validYAML())
        try await control.applyImportedProfileAndStart(imported)

        let running = await control.currentStatus()
        #expect(running.state == .running)

        try await control.stop()
        let stopped = await control.currentStatus()
        #expect(stopped.state == .stopped)
    }

    private func validYAML() -> String {
        """
        mode: rule
        proxies:
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,my-socks
        """
    }
}
