import Foundation
import Riptide

actor AppMockTunnelRuntime: TunnelRuntime {
    private var currentStatus = TunnelRuntimeStatus()

    func start(profile: TunnelProfile) async throws {
        _ = profile
        currentStatus = TunnelRuntimeStatus(bytesUp: 128, bytesDown: 256, activeConnections: 1)
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

enum DemoConfigFactory {
    static func makeYAML() -> String {
        """
        mode: rule
        proxies:
          - name: "demo-socks"
            type: socks5
            server: "127.0.0.1"
            port: 1080
        rules:
          - MATCH,demo-socks
        """
    }
}
