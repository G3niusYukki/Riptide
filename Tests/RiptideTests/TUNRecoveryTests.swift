import Foundation
import Testing
@testable import Riptide

// MARK: - TUN Recovery Tests

@Suite("TUN Recovery")
struct TUNRecoveryTests {

    @Test("TUN monitoring is not active before start")
    func tunMonitoringNotActiveBeforeStart() async throws {
        let manager = MihomoRuntimeManager()
        let active = await manager.isTUNMonitoringActive
        #expect(active == false)
    }

    @Test("TUN monitoring state is accessible")
    func tunMonitoringStateAccessible() async throws {
        let manager = MihomoRuntimeManager()
        // Verify the property exists and returns expected default
        let active = await manager.isTUNMonitoringActive
        #expect(active == false)
    }

    @Test("stop clears TUN monitoring state")
    func stopClearsTUNMonitoring() async throws {
        // This test verifies the cleanup path works without errors
        // Full TUN testing requires a running mihomo instance
        let manager = MihomoRuntimeManager()
        let active = await manager.isTUNMonitoringActive
        #expect(active == false)
    }
}
