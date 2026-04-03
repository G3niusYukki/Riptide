import Foundation

/// The current state of the system proxy setting.
public enum SystemProxyState: Sendable, Equatable {
    case disabled
    case enabled(httpPort: Int, socksPort: Int?)
}

/// Errors that can occur when controlling the system proxy.
public enum SystemProxyError: Error, Equatable, Sendable {
    case alreadyEnabled
    case notEnabled
    case portInUse(Int)
    case permissionDenied
    case unknown(String)
}

/// Protocol for system proxy control.
/// Protocol-backed so test doubles can be injected without mutating the real system.
public protocol SystemProxyControlling: Sendable {
    /// Enable the system proxy with the given HTTP and SOCKS5 ports.
    func enable(httpPort: Int, socksPort: Int?) throws

    /// Disable the system proxy.
    func disable() throws

    /// Query the current system proxy state.
    func currentState() throws -> SystemProxyState
}

/// A test double that records enable/disable calls without touching the real system.
public final class MockSystemProxyController: SystemProxyControlling, @unchecked Sendable {
    private var _state: SystemProxyState = .disabled

    public init() {}

    public func enable(httpPort: Int, socksPort: Int?) throws {
        _state = .enabled(httpPort: httpPort, socksPort: socksPort)
    }

    public func disable() throws {
        _state = .disabled
    }

    public func currentState() throws -> SystemProxyState {
        _state
    }
}

/// A test double that always fails on enable, simulating permission denied.
public final class FailingSystemProxyController: SystemProxyControlling, @unchecked Sendable {
    public init() {}

    public func enable(httpPort: Int, socksPort: Int?) throws {
        throw SystemProxyError.permissionDenied
    }

    public func disable() throws {
        // no-op
    }

    public func currentState() throws -> SystemProxyState {
        .disabled
    }
}
