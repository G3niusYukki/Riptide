import Foundation

public enum TunnelControlCommand: Sendable {
    case start(TunnelProfile)
    case stop
    case update(TunnelProfile)
    case status
}

public enum TunnelControlResponse: Equatable, Sendable {
    case ack
    case status(TunnelStatusSnapshot)
    case error(String)
}

public enum TunnelControlEvent: Equatable, Sendable {
    case statusChanged(TunnelStatusSnapshot)
    case error(String)
}

public actor InProcessTunnelControlChannel {
    private let lifecycleManager: TunnelLifecycleManager
    private var continuations: [UUID: AsyncStream<TunnelControlEvent>.Continuation]

    public init(lifecycleManager: TunnelLifecycleManager) {
        self.lifecycleManager = lifecycleManager
        self.continuations = [:]
    }

    public func send(_ command: TunnelControlCommand) async throws -> TunnelControlResponse {
        do {
            switch command {
            case .start(let profile):
                try await lifecycleManager.start(profile: profile)
                let snapshot = await lifecycleManager.status()
                broadcast(.statusChanged(snapshot))
                return .ack

            case .stop:
                try await lifecycleManager.stop()
                let snapshot = await lifecycleManager.status()
                broadcast(.statusChanged(snapshot))
                return .ack

            case .update(let profile):
                try await lifecycleManager.update(profile: profile)
                let snapshot = await lifecycleManager.status()
                broadcast(.statusChanged(snapshot))
                return .ack

            case .status:
                let snapshot = await lifecycleManager.status()
                return .status(snapshot)
            }
        } catch {
            let message = String(describing: error)
            broadcast(.error(message))
            return .error(message)
        }
    }

    public func events() -> AsyncStream<TunnelControlEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    private func broadcast(_ event: TunnelControlEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }
}
