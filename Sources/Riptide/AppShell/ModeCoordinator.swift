import Foundation

/// Coordinates runtime mode transitions between system proxy and TUN,
/// using MihomoRuntimeManager as the underlying runtime.
/// Surfaces degraded-state recommendations when a mode fails to start.
public actor ModeCoordinator {
    private let mihomoManager: any MihomoRuntimeManaging
    private var activeMode: RuntimeMode
    private var eventBuffer: [RuntimeEvent]

    private let maxEvents = 100

    public static let defaultHTTPPort: Int = 6152

    public init(mihomoManager: any MihomoRuntimeManaging) {
        self.mihomoManager = mihomoManager
        self.activeMode = .systemProxy
        self.eventBuffer = []
    }

    public func start(mode: RuntimeMode, profile: TunnelProfile?) async throws {
        guard let profile else {
            let msg = "Mode requires a profile"
            emit(.degraded(mode, msg))
            emit(.error(RuntimeErrorSnapshot(code: "E_NO_PROFILE", message: msg)))
            throw SystemProxyError.unknown("no profile for mode")
        }

        do {
            try await mihomoManager.start(mode: mode, profile: profile)
            activeMode = mode
            emit(.modeChanged(mode))
            emit(.stateChanged(.running))
        } catch {
            emit(.degraded(mode, "\(mode) start failed: \(String(describing: error))"))
            emit(.error(RuntimeErrorSnapshot(
                code: "E_MODE_FAILED",
                message: String(describing: error)
            )))
            throw error
        }
    }

    public func stop() async throws {
        do {
            try await mihomoManager.stop()
            emit(.stateChanged(.stopped))
        } catch {
            emit(.error(RuntimeErrorSnapshot(
                code: "E_STOP_FAILED",
                message: String(describing: error)
            )))
            throw error
        }
    }

    /// The current runtime mode.
    public func currentMode() -> RuntimeMode {
        activeMode
    }

    /// Recent runtime events emitted by this coordinator.
    public func recentEvents() -> [RuntimeEvent] {
        eventBuffer
    }

    /// Whether the helper tool is installed (required for both modes with mihomo).
    public func isHelperInstalled() async -> Bool {
        await mihomoManager.helperConnection.isHelperInstalled()
    }

    /// Gets traffic statistics from the mihomo runtime.
    public func getTraffic() async -> (up: Int64, down: Int64) {
        do {
            let traffic = try await mihomoManager.getTraffic()
            return (Int64(traffic.up), Int64(traffic.down))
        } catch {
            return (0, 0)
        }
    }

    /// Gets active connections from the mihomo runtime.
    public func getConnections() async -> Int {
        do {
            let connections = try await mihomoManager.getConnections()
            return connections.count
        } catch {
            return 0
        }
    }

    private func emit(_ event: RuntimeEvent) {
        eventBuffer.append(event)
        if eventBuffer.count > maxEvents {
            eventBuffer.removeFirst()
        }
    }
}
