import Foundation

/// Coordinates runtime mode transitions between system proxy and TUN,
/// surfacing degraded-state recommendations when a mode fails to start.
public actor ModeCoordinator {
    private let systemProxyController: any SystemProxyControlling
    private let lifecycleManager: TunnelLifecycleManager?
    private var activeMode: RuntimeMode
    private var eventBuffer: [RuntimeEvent]

    private let maxEvents = 100

    public static let defaultHTTPPort: Int = 6152

    public init(
        systemProxyController: any SystemProxyControlling,
        lifecycleManager: TunnelLifecycleManager?
    ) {
        self.systemProxyController = systemProxyController
        self.lifecycleManager = lifecycleManager
        self.activeMode = .systemProxy
        self.eventBuffer = []
    }

    public func start(mode: RuntimeMode, profile: TunnelProfile?) async throws {
        switch mode {
        case .systemProxy:
            do {
                try systemProxyController.enable(httpPort: Self.defaultHTTPPort, socksPort: nil)
                activeMode = mode
                emit(.modeChanged(.systemProxy))
                emit(.stateChanged(.running))
            } catch {
                emit(.degraded(.systemProxy, "system proxy enable failed: \(String(describing: error))"))
                emit(.error(RuntimeErrorSnapshot(
                    code: "E_SYSTEM_PROXY",
                    message: String(describing: error)
                )))
                throw error
            }

        case .tun:
            guard let manager = lifecycleManager else {
                let msg = "TUN mode requires a lifecycle manager"
                emit(.degraded(.tun, msg))
                emit(.error(RuntimeErrorSnapshot(code: "E_NO_MANAGER", message: msg)))
                throw SystemProxyError.unknown("no lifecycle manager for TUN mode")
            }
            guard let profile else {
                let msg = "TUN mode requires a profile"
                emit(.degraded(.tun, msg))
                emit(.error(RuntimeErrorSnapshot(code: "E_NO_PROFILE", message: msg)))
                throw SystemProxyError.unknown("no profile for TUN mode")
            }
            do {
                try await manager.start(profile: profile)
                activeMode = mode
                emit(.modeChanged(.tun))
                emit(.stateChanged(.running))
            } catch {
                emit(.degraded(.tun, "TUN start failed: \(String(describing: error))"))
                emit(.error(RuntimeErrorSnapshot(
                    code: "E_TUN_FAILED",
                    message: String(describing: error)
                )))
                throw error
            }
        }
    }

    public func stop() async throws {
        switch activeMode {
        case .systemProxy:
            try systemProxyController.disable()
        case .tun:
            if let manager = lifecycleManager {
                try await manager.stop()
            }
        }
        emit(.stateChanged(.stopped))
    }

    /// The current runtime mode.
    public func currentMode() -> RuntimeMode {
        activeMode
    }

    /// Recent runtime events emitted by this coordinator.
    public func recentEvents() -> [RuntimeEvent] {
        eventBuffer
    }

    private func emit(_ event: RuntimeEvent) {
        eventBuffer.append(event)
        if eventBuffer.count > maxEvents {
            eventBuffer.removeFirst()
        }
    }
}
