import Foundation

@testable import Riptide

actor MockTunnelRuntime: TunnelRuntime {
    private let startError: TunnelRuntimeError?
    private let stopError: TunnelRuntimeError?
    private let updateError: TunnelRuntimeError?
    private let statusValue: TunnelRuntimeStatus

    init(
        startError: TunnelRuntimeError? = nil,
        stopError: TunnelRuntimeError? = nil,
        updateError: TunnelRuntimeError? = nil,
        statusOverride: TunnelRuntimeStatus = TunnelRuntimeStatus()
    ) {
        self.startError = startError
        self.stopError = stopError
        self.updateError = updateError
        self.statusValue = statusOverride
    }

    func start(profile: TunnelProfile) async throws {
        _ = profile
        if let startError {
            throw startError
        }
    }

    func stop() async throws {
        if let stopError {
            throw stopError
        }
    }

    func update(profile: TunnelProfile) async throws {
        _ = profile
        if let updateError {
            throw updateError
        }
    }

    func status() async -> TunnelRuntimeStatus {
        statusValue
    }
}

actor LiveRuntimeMockDialer: TransportDialer {
    private var sessions: [MockTransportSession]
    private(set) var openRequests: [ProxyNode]

    init(_ sessions: [MockTransportSession]) {
        self.sessions = sessions
        self.openRequests = []
    }

    func openSession(to node: ProxyNode) async throws -> any TransportSession {
        openRequests.append(node)
        if sessions.isEmpty {
            throw TransportError.noSessionAvailable
        }
        return sessions.removeFirst()
    }
}
