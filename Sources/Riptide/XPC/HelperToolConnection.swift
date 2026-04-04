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
private final class SendableHelperProxy: @unchecked Sendable {
    let proxy: HelperToolProtocol

    init(_ proxy: HelperToolProtocol) {
        self.proxy = proxy
    }
}

// MARK: - HelperToolConnection

/// Actor that manages the XPC connection to the privileged helper tool.
/// Provides connection establishment, proxy access, and lifecycle management.
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
    }

    // MARK: - Properties

    /// The Mach service name for the helper tool.
    private let machServiceName = "com.riptide.helper"

    /// The current XPC connection (if any).
    private var connectionWrapper: SendableXPCConnection?

    /// Cached proxy object for the helper tool.
    private var proxyWrapper: SendableHelperProxy?

    // MARK: - Initialization

    /// Creates a new HelperToolConnection.
    public init() {}

    // MARK: - Public Methods

    /// Checks if the helper tool is installed by attempting to create a connection.
    /// - Returns: true if the helper tool is installed and available.
    public func isHelperInstalled() async -> Bool {
        // Use withCheckedContinuation for proper async handling
        return await withCheckedContinuation { continuation in
            Task.detached {
                let testConnection = NSXPCConnection(machServiceName: self.machServiceName)
                testConnection.remoteObjectInterface = createHelperToolInterface()

                var connectionValid = false
                var hasResponded = false

                // Set up error handler
                _ = testConnection.remoteObjectProxyWithErrorHandler { _ in
                    guard !hasResponded else { return }
                    hasResponded = true
                    connectionValid = false
                    testConnection.invalidate()
                    continuation.resume(returning: false)
                } as? HelperToolProtocol

                // Try to get proxy and make a test call
                if let proxy = testConnection.remoteObjectProxy as? HelperToolProtocol {
                    proxy.getMihomoStatus { _, _ in
                        guard !hasResponded else { return }
                        hasResponded = true
                        connectionValid = true
                        testConnection.invalidate()
                        continuation.resume(returning: true)
                    }
                } else {
                    hasResponded = true
                    testConnection.invalidate()
                    continuation.resume(returning: false)
                }

                testConnection.resume()

                // Timeout after 1 second
                Task.detached {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
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

    /// Disconnects from the helper tool and cleans up resources.
    public func disconnect() {
        proxyWrapper = nil
        connectionWrapper?.connection.invalidate()
        connectionWrapper = nil
    }

    // MARK: - Private Methods

    /// Ensures a connection to the helper tool exists.
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

        // Wrap proxy for storage
        let proxyWrapper = SendableHelperProxy(validProxy)

        // Verify connection works with a status check
        let isConnected = await verifyConnection(proxy: validProxy)
        guard isConnected else {
            newConnection.invalidate()
            connectionWrapper.connection.invalidate()
            self.connectionWrapper = nil
            throw ConnectionError.notInstalled
        }

        // Cache the proxy
        self.proxyWrapper = proxyWrapper
    }

    /// Verifies that the XPC connection is working by making a status request.
    private func verifyConnection(proxy: HelperToolProtocol) async -> Bool {
        return await withCheckedContinuation { continuation in
            proxy.getMihomoStatus { _, _ in
                // If we get any response (including errors about mihomo not running),
                // the connection itself is working
                continuation.resume(returning: true)
            }
        }
    }

    /// Handles connection invalidation.
    private func handleConnectionInvalidated() {
        proxyWrapper = nil
        connectionWrapper = nil
    }

    /// Handles connection interruption.
    private func handleConnectionInterrupted() {
        // Clear cached proxy but keep connection reference
        // The connection may recover on next use
        proxyWrapper = nil
    }
}
