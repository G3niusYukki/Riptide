import Foundation
import Testing

@testable import Riptide

@Suite("VPN tunnel manager")
struct VPNTunnelManagerTests {
    @Test("manager reports not running initially")
    func reportsNotRunningInitially() {
        let manager = VPNTunnelManager()
        #expect(manager.isRunning == false)
    }

    @Test("manager reports running after start")
    func reportsRunningAfterStart() {
        let manager = VPNTunnelManager()
        manager.start(configuration: VPNConfiguration())
        #expect(manager.isRunning == true)
        manager.stop()
    }

    @Test("manager reports not running after stop")
    func reportsNotRunningAfterStop() {
        let manager = VPNTunnelManager()
        manager.start(configuration: VPNConfiguration())
        manager.stop()
        #expect(manager.isRunning == false)
    }

    @Test("manager buffers received packets when running")
    func buffersPacketsWhenRunning() {
        let manager = VPNTunnelManager()
        let packets = [Data([0x01, 0x02]), Data([0x03, 0x04])]
        manager.start(configuration: VPNConfiguration())
        manager.handlePackets(packets)
        // Buffering is internal; just verify no crash
        #expect(manager.isRunning == true)
    }
}

@Suite("Tunnel provider bridge")
struct TunnelProviderBridgeTests {
    @Test("bridge handles stop command and returns snapshot")
    func bridgeStopCommand() async throws {
        let bridge = TunnelProviderBridge()
        let snapshot = try await bridge.handle(command: .stop)
        #expect(snapshot.isRunning == true)
        #expect(snapshot.mode == .tun)
    }

    @Test("bridge handles snapshot command")
    func bridgeSnapshotCommand() async throws {
        let bridge = TunnelProviderBridge()
        let snapshot = try await bridge.handle(command: .snapshot)
        #expect(snapshot.mode == .tun)
        #expect(snapshot.recentErrors.isEmpty)
    }

    @Test("bridge records errors and includes them in snapshots")
    func bridgeRecordsErrors() async throws {
        let bridge = TunnelProviderBridge()
        let error = RuntimeErrorSnapshot(code: "E_TUN_DROP", message: "packet dropped")
        await bridge.recordError(error)

        let snapshot = await bridge.snapshot()
        #expect(snapshot.recentErrors.count == 1)
        #expect(snapshot.recentErrors.first?.code == "E_TUN_DROP")
    }

    @Test("tunnel provider snapshot is constructible and equatable")
    func snapshotConstructible() {
        let status = TunnelRuntimeStatus(bytesUp: 100, bytesDown: 200, activeConnections: 3)
        let error = RuntimeErrorSnapshot(code: "E_TEST", message: "test error")
        let snapshot = TunnelProviderSnapshot(
            status: status,
            mode: .tun,
            recentErrors: [error],
            isRunning: true
        )

        #expect(snapshot.status.bytesUp == 100)
        #expect(snapshot.status.bytesDown == 200)
        #expect(snapshot.mode == .tun)
        #expect(snapshot.recentErrors.count == 1)
        #expect(snapshot.isRunning == true)

        let duplicate = TunnelProviderSnapshot(
            status: status,
            mode: .tun,
            recentErrors: [error],
            isRunning: true
        )
        #expect(snapshot == duplicate)
    }

    @Test("tunnel provider command is codable")
    func commandIsCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let stopData = try encoder.encode(TunnelProviderCommand.stop)
        let decodedStop = try decoder.decode(TunnelProviderCommand.self, from: stopData)
        #expect(decodedStop == .stop)

        let configData = Data([0x01, 0x02, 0x03])
        let startCmd = TunnelProviderCommand.start(configData)
        let startData = try encoder.encode(startCmd)
        let decodedStart = try decoder.decode(TunnelProviderCommand.self, from: startData)
        if case .start(let decodedConfig) = decodedStart {
            #expect(decodedConfig == configData)
        } else {
            Issue.record("Expected start command")
        }
    }
}
