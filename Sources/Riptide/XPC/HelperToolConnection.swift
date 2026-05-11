import Foundation

// MARK: - Sendable Wrappers for XPC Types

/// Wrapper for NSXPCConnection that provides @unchecked Sendable conformance.
/// NSXPCConnection is thread-safe by design (uses internal serial queue for callbacks).
private final class SendableXPCConnection: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }
}

/// Wrapper for HelperToolProtocol that provides @unchecked Sendable conformance.
/// XPC proxy objects are thread-safe by design (all calls are serialized through XPC).
public final class SendableHelperProxy: @unchecked Sendable {
    public let proxy: HelperToolProtocol

    init(_ proxy: HelperToolProtocol) {
        self.proxy = proxy
    }
}

// MARK: - HelperToolConnection

/// Actor that manages the XPC connection to the privileged helper tool.
/// Provides connection establishment, proxy access, lifecycle management,
/// automatic reconnection, and heartbeat monitoring.
public actor HelperToolConnection {

    // MARK: - Types

    /// Errors that can occur when connecting to or using the helper tool.
    public enum ConnectionError: Error, Equatable, Sendable {
        /// The helper tool is not installed in the system.
        case notInstalled
        /// Failed to establish XPC connection.
        case connectionFailed(String)
        /// XPC request to helper failed.
        case requestFailed(String)
        /// Helper version is incompatible with the host app.
        case versionMismatch(hostVersion: String, helperVersion: String)
        /// Connection attempt timed out.
        case timedOut(String)
    }

    // MARK: - Configuration

    /// The Mach service name for the helper tool.
    private let machServiceName = "com.riptide.helper"

    /// Maximum number of reconnection attempts before giving up.
    private let maxReconnectAttempts = 3

    /// Heartbeat check interval.
    private let heartbeatInterval: Duration = .seconds(30)

    /// Minimum helper version required by this host (semver string).
    /// Bump this when the XPC protocol changes.
    private let minimumHelperVersion = "1.0.0"

    // MARK: - State

    /// The current XPC connection (if any).
    private var connectionWrapper: SendableXPCConnection?

    /// Cached proxy object for the helper tool.
    private var proxyWrapper: SendableHelperProxy?

    /// Background heartbeat task.
    private var heartbeatTask: Task<Void, Never>?

    /// Background reconnection task (nil when not reconnecting).
    private var reconnectTask: Task<Void, Never>?

    /// The helper tool's reported version (nil until first successful connection).
    public private(set) var helperVersion: String?

    // MARK: - Initialization

    /// Creates a new HelperToolConnection.
    public init() {}

    // MARK: - Public Methods

    /// Checks if the helper tool is installed by attempting to create a connection.
    /// - Returns: true if the helper tool is installed and available.
    public func isHelperInstalled() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached { [machServiceName] in
                let testConnection = NSXPCConnection(machServiceName: machServiceName)
                testConnection.remoteObjectInterface = createHelperToolInterface()

                var hasResponded = false

                _ = testConnection.remoteObjectProxyWithErrorHandler { _ in
                    guard !hasResponded else { return }
                    hasResponded = true
                    testConnection.invalidate()
                    continuation.resume(returning: false)
                } as? HelperToolProtocol

                if let proxy = testConnection.remoteObjectProxy as? HelperToolProtocol {
                    proxy.getMihomoStatus { _, _ in
                        guard !hasResponded else { return }
                        hasResponded = true
                        testConnection.invalidate()
                        continuation.resume(returning: true)
                    }
                } else {
                    guard !hasResponded else { return }
                    hasResponded = true
                    testConnection.invalidate()
                    continuation.resume(returning: false)
                }

                testConnection.resume()

                // Timeout after 2 seconds
                Task.detached {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !hasResponded else { return }
                    hasResponded = true
                    testConnection.invalidate()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Launches mihomo using the helper tool.
    /// - Parameters:
    ///   - configPath: Path to the mihomo config file.
    ///   - mode: Launch mode string ("systemProxy" or "tun").
    /// - Returns: Error if launch failed, nil on success.
    public func launchMihomo(configPath: String, mode: String) async -> Error? {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return ConnectionError.notInstalled
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.launchMihomo(configPath: configPath, mode: mode) { error in
                continuation.resume(returning: error)
            }
        }
    }

    /// Terminates mihomo using the helper tool.
    /// - Returns: Error if termination failed, nil on success.
    public func terminateMihomo() async -> Error? {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return ConnectionError.notInstalled
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.terminateMihomo { error in
                continuation.resume(returning: error)
            }
        }
    }

    /// Gets the XPC proxy object for the helper tool.
    /// - Returns: The SendableHelperProxy wrapper containing the proxy object.
    /// - Throws: ConnectionError if connection fails.
    public func getHelperProxy() async throws -> SendableHelperProxy {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            throw ConnectionError.notInstalled
        }

        return wrapper
    }

    /// Gets the current mihomo status from the helper tool.
    /// - Returns: Tuple of (statusData, error).
    public func getMihomoStatus() async -> (Data?, Error?) {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return (nil, ConnectionError.notInstalled)
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.getMihomoStatus { data, error in
                continuation.resume(returning: (data, error))
            }
        }
    }

    /// Installs or updates the mihomo binary to the system location via the helper tool.
    /// - Parameter binaryPath: Path to the mihomo binary to install.
    /// - Returns: Error if installation failed, nil on success.
    public func installMihomo(binaryPath: String) async -> Error? {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return ConnectionError.notInstalled
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.installMihomo(binaryPath: binaryPath) { error in
                continuation.resume(returning: error)
            }
        }
    }

    // MARK: - System Proxy Control

    /// Enables system-wide proxy via the helper tool.
    public func enableSystemProxy(service: String, httpPort: Int, socksPort: Int) async -> Error? {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return ConnectionError.notInstalled
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.enableSystemProxy(service: service, httpPort: httpPort, socksPort: socksPort) { error in
                continuation.resume(returning: error)
            }
        }
    }

    /// Disables system-wide proxy via the helper tool.
    public func disableSystemProxy(service: String) async -> Error? {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return ConnectionError.notInstalled
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.disableSystemProxy(service: service) { error in
                continuation.resume(returning: error)
            }
        }
    }

    /// Queries the current system proxy state via the helper tool.
    public func querySystemProxyState(service: String) async -> (String?, Error?) {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return (nil, ConnectionError.notInstalled)
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.querySystemProxyState(service: service) { json, error in
                continuation.resume(returning: (json, error))
            }
        }
    }

    /// Auto-detects the primary network service.
    public func detectNetworkService() async -> (String?, Error?) {
        await ensureConnection()

        guard let wrapper = proxyWrapper else {
            return (nil, ConnectionError.notInstalled)
        }

        return await withCheckedContinuation { continuation in
            wrapper.proxy.detectNetworkService { service, error in
                continuation.resume(returning: (service, error))
            }
        }
    }

    /// Disconnects from the helper tool and cleans up resources.
    public func disconnect() async {
        stopHeartbeat()
        reconnectTask?.cancel()
        reconnectTask = nil
        proxyWrapper = nil
        connectionWrapper?.connection.invalidate()
        connectionWrapper = nil
    }

    /// Whether the connection is currently active and usable.
    public var isConnected: Bool {
        proxyWrapper != nil
    }

    // MARK: - Private Methods — Connection Lifecycle

    /// Ensures a connection to the helper tool exists.
    /// Attempts reconnection if the connection was lost.
    private func ensureConnection() async {
        guard proxyWrapper == nil else { return }
        _ = try? await establishConnection()
    }

    /// Establishes a new connection to the helper tool.
    /// - Throws: ConnectionError if connection fails.
    private func establishConnection() async throws {
        // Create new connection wrapped in Sendable container
        let newConnection = NSXPCConnection(machServiceName: machServiceName)
        let connectionWrapper = SendableXPCConnection(newConnection)
        self.connectionWrapper = connectionWrapper

        newConnection.remoteObjectInterface = createHelperToolInterface()

        // Set up invalidation handler
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            Task {
                await self.handleConnectionInvalidated()
            }
        }

        // Set up interruption handler
        newConnection.interruptionHandler = { [weak self] in
            guard let self else { return }
            Task {
                await self.handleConnectionInterrupted()
            }
        }

        // Resume the connection
        newConnection.resume()

        // Get the proxy with proper error handling
        let proxy: HelperToolProtocol? = newConnection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleConnectionInvalidated()
            }
        } as? HelperToolProtocol

        guard let validProxy = proxy else {
            newConnection.invalidate()
            connectionWrapper.connection.invalidate()
            self.connectionWrapper = nil
            throw ConnectionError.connectionFailed("Failed to create remote object proxy")
        }

        // Verify connection works with a status check
        let isConnected = await verifyConnection(proxy: validProxy)
        guard isConnected else {
            newConnection.invalidate()
            connectionWrapper.connection.invalidate()
            self.connectionWrapper = nil
            throw ConnectionError.notInstalled
        }

        // Fetch and validate helper version
        let version = await fetchHelperVersion(proxy: validProxy)
        self.helperVersion = version

        // Cache the proxy
        self.proxyWrapper = SendableHelperProxy(validProxy)

        // Start heartbeat monitoring
        startHeartbeat()
    }

    /// Verifies that the XPC connection is working by making a status request.
    private func verifyConnection(proxy: HelperToolProtocol) async -> Bool {
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    proxy.getMihomoStatus { _, _ in
                        continuation.resume(returning: true)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    /// Fetches the helper tool's version string.
    private func fetchHelperVersion(proxy: HelperToolProtocol) async -> String? {
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    proxy.getHelperVersion { version, _ in
                        continuation.resume(returning: version)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private Methods — Reconnection

    /// Handles connection invalidation (connection permanently lost).
    private func handleConnectionInvalidated() {
        proxyWrapper = nil
        connectionWrapper = nil
        stopHeartbeat()
        triggerReconnect()
    }

    /// Handles connection interruption (connection temporarily lost, may recover).
    private func handleConnectionInterrupted() {
        proxyWrapper = nil
        stopHeartbeat()
        triggerReconnect()
    }

    /// Triggers a background reconnection attempt if one isn't already running.
    private func triggerReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { await attemptReconnect() }
    }

    /// Attempts to reconnect with exponential backoff.
    /// Stops after `maxReconnectAttempts` or if the task is cancelled.
    private func attemptReconnect() async {
        defer { reconnectTask = nil }

        for attempt in 0..<maxReconnectAttempts {
            guard !Task.isCancelled else { return }

            // Exponential backoff: 1s, 2s, 4s
            let delaySeconds = pow(2.0, Double(attempt))
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }

            do {
                try await establishConnection()
                return // success
            } catch {
                // Retry
                continue
            }
        }
        // All attempts exhausted — connection remains nil.
        // The next `ensureConnection()` call will try again.
    }

    // MARK: - Private Methods — Heartbeat

    /// Starts periodic heartbeat monitoring.
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self, heartbeatInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: heartbeatInterval)
                guard !Task.isCancelled else { return }
                await self?.performHeartbeat()
            }
        }
    }

    /// Stops heartbeat monitoring.
    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Performs a single heartbeat check.
    /// If the check fails (timeout or connection error), triggers reconnection.
    private func performHeartbeat() async {
        guard let wrapper = proxyWrapper else { return }

        let alive = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    wrapper.proxy.getMihomoStatus { _, _ in
                        // Any response means the connection is alive
                        continuation.resume(returning: true)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if !alive {
            handleConnectionInterrupted()
        }
    }
}
