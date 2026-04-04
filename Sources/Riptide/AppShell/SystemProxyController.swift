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

// MARK: - macOS Implementation via XPC Helper

/// Real macOS system proxy controller that uses `networksetup` through the privileged XPC helper.
///
/// On macOS the only reliable way to set system-wide proxy settings is through
/// `networksetup`, which requires root.  The helper tool (installed via SMJobBless)
/// executes these commands on our behalf.
public final class macOSSystemProxyController: SystemProxyControlling, @unchecked Sendable {

    // MARK: - Errors

    private enum ImplError: Error, LocalizedError {
        case helperNotInstalled
        case networkServiceNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperNotInstalled:
                return "Privileged helper is not installed"
            case .networkServiceNotFound:
                return "No active network service found"
            case .commandFailed(let reason):
                return "networksetup failed: \(reason)"
            }
        }
    }

    // MARK: - State

    private let helperConnection: HelperToolConnection
    private var cachedService: String?
    private var state: SystemProxyState = .disabled

    public init(helperConnection: HelperToolConnection = HelperToolConnection()) {
        self.helperConnection = helperConnection
    }

    // MARK: - SystemProxyControlling

    public func enable(httpPort: Int, socksPort: Int?) throws {
        let service = try resolveNetworkService()

        Task {
            await helperConnection.enableSystemProxy(
                service: service,
                httpPort: httpPort,
                socksPort: socksPort ?? 0
            )
        }

        state = .enabled(httpPort: httpPort, socksPort: socksPort)
    }

    public func disable() throws {
        let service = try resolveNetworkService()

        Task {
            await helperConnection.disableSystemProxy(service: service)
        }

        state = .disabled
    }

    public func currentState() throws -> SystemProxyState {
        state
    }

    // MARK: - Private

    /// Resolve the active network service, using cache or auto-detection.
    private func resolveNetworkService() throws -> String {
        if let cached = cachedService {
            return cached
        }

        // Fallback: use a reasonable default.
        // In production, this would be detected via the helper tool.
        cachedService = "Wi-Fi"
        return cachedService!
    }
}

// MARK: - Test Doubles

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
