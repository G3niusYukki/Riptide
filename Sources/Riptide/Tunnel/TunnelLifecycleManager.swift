import Foundation

public protocol TunnelRuntime: Sendable {
    func start(profile: TunnelProfile) async throws
    func stop() async throws
    func update(profile: TunnelProfile) async throws
    func status() async -> TunnelRuntimeStatus
}

public enum TunnelRuntimeError: Error, Equatable, Sendable {
    case startFailed(String)
    case stopFailed(String)
    case updateFailed(String)
}

public enum TunnelLifecycleError: Error, Equatable, Sendable {
    case invalidTransition(from: TunnelLifecycleState, operation: String)
}

public actor TunnelLifecycleManager {
    private let runtime: any TunnelRuntime
    private var state: TunnelLifecycleState
    private var activeProfile: TunnelProfile?
    private var lastError: String?

    public init(runtime: any TunnelRuntime) {
        self.runtime = runtime
        self.state = .stopped
        self.activeProfile = nil
        self.lastError = nil
    }

    public func start(profile: TunnelProfile) async throws {
        guard state == .stopped else {
            throw TunnelLifecycleError.invalidTransition(from: state, operation: "start")
        }

        state = .starting
        do {
            try await runtime.start(profile: profile)
            state = .running
            activeProfile = profile
            lastError = nil
        } catch {
            state = .error
            activeProfile = nil
            lastError = String(describing: error)
            throw error
        }
    }

    public func stop() async throws {
        guard state == .running || state == .error else {
            throw TunnelLifecycleError.invalidTransition(from: state, operation: "stop")
        }

        state = .stopping
        do {
            try await runtime.stop()
            state = .stopped
            activeProfile = nil
            lastError = nil
        } catch {
            state = .error
            lastError = String(describing: error)
            throw error
        }
    }

    public func update(profile: TunnelProfile) async throws {
        guard state == .running else {
            throw TunnelLifecycleError.invalidTransition(from: state, operation: "update")
        }
        do {
            try await runtime.update(profile: profile)
            activeProfile = profile
            lastError = nil
        } catch {
            state = .error
            lastError = String(describing: error)
            throw error
        }
    }

    public func status() async -> TunnelStatusSnapshot {
        let runtimeStatus = await runtime.status()
        return TunnelStatusSnapshot(
            state: state,
            activeProfileName: activeProfile?.name,
            bytesUp: runtimeStatus.bytesUp,
            bytesDown: runtimeStatus.bytesDown,
            activeConnections: runtimeStatus.activeConnections,
            lastError: lastError
        )
    }
}
