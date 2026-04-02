import Foundation
import Riptide

actor CLIMockTunnelRuntime: TunnelRuntime {
    private var currentStatus = TunnelRuntimeStatus()

    func start(profile: TunnelProfile) async throws {
        _ = profile
        currentStatus = TunnelRuntimeStatus(bytesUp: 0, bytesDown: 0, activeConnections: 1)
    }

    func stop() async throws {
        currentStatus = TunnelRuntimeStatus()
    }

    func update(profile: TunnelProfile) async throws {
        _ = profile
    }

    func status() async -> TunnelRuntimeStatus {
        currentStatus
    }
}
