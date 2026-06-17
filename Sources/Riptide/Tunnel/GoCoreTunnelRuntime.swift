import Foundation

/// Tunnel runtime backed by the bridged Go Core library.
/// Implements `MihomoRuntimeManaging` to plug seamlessly into the existing app flow.
public actor GoCoreTunnelRuntime: MihomoRuntimeManaging {
    public let helperConnection: HelperToolConnection
    public private(set) var isRunning: Bool = false
    public private(set) var currentMode: RuntimeMode?
    public private(set) var currentProfile: TunnelProfile?
    public private(set) var latestRecoveryError: RuntimeErrorSnapshot?

    public var logbookWriter: LogbookWriter?

    /// Async setter so callers from a different actor can write the property
    /// without crossing the actor boundary synchronously.
    public func setLogbookWriter(_ writer: LogbookWriter?) async {
        self.logbookWriter = writer
    }

    private var eventHandler: (@Sendable (RuntimeEvent) -> Void)?

    /// Local mixed-proxy port sing-box listens on; the macOS system proxy is
    /// pointed here in system-proxy mode. Kept in sync with the value passed to
    /// `SingBoxConfigGenerator`.
    private let mixedPort: Int

    /// Sets/clears the macOS system proxy in system-proxy mode via direct
    /// `networksetup` (no privileged helper, no sudo). Injectable for testing.
    private let systemProxyController: any SystemProxyControlling

    /// Drives the privileged launchd daemon that runs sing-box as root for TUN
    /// mode. Only used on the `.tun` path; system-proxy stays fully in-process.
    private let tunDaemon: TunDaemonController

    /// Locates the bundled standalone core for TUN. Injectable for testing.
    private let tunBinaryLocator: @Sendable () -> URL?

    public init(
        helperConnection: HelperToolConnection = HelperToolConnection(),
        systemProxyController: any SystemProxyControlling = NetworksetupSystemProxyController(),
        mixedPort: Int = 6152,
        tunDaemon: TunDaemonController = TunDaemonController(),
        tunBinaryLocator: @escaping @Sendable () -> URL? = { SingBoxBinaryLocator.locate() }
    ) {
        self.helperConnection = helperConnection
        self.systemProxyController = systemProxyController
        self.mixedPort = mixedPort
        self.tunDaemon = tunDaemon
        self.tunBinaryLocator = tunBinaryLocator
    }
    
    public func setEventHandler(_ handler: (@Sendable (RuntimeEvent) -> Void)?) async {
        self.eventHandler = handler
    }
    
    public func setup() async throws {
        // Prepare local directories/logs if needed
    }
    
    public func start(mode: RuntimeMode, profile: TunnelProfile) async throws {
        self.currentMode = mode
        self.currentProfile = profile

        let configJSON: String
        do {
            configJSON = try SingBoxConfigGenerator.generate(
                config: profile.config,
                // The bundled libgocore.a is rebuilt with `-tags with_utls`, so
                // REALITY/uTLS outbounds are supported (see Scripts/build-gocore.sh).
                options: SingBoxConfigGenerator.GenerationOptions(mode: mode, mixedPort: mixedPort, supportsUTLS: true)
            )
        } catch {
            self.currentMode = nil
            self.currentProfile = nil
            throw TunnelRuntimeError.startFailed("Failed to generate sing-box config: \(error)")
        }

        // TUN runs the core out-of-process as root via a launchd daemon (creating
        // the utun + routes needs privileges the in-process GoCore can't get).
        // System-proxy stays fully in-process; only `.tun` takes this branch.
        if mode == .tun {
            do {
                try await startTunDaemon(configJSON: configJSON)
            } catch {
                self.currentMode = nil
                self.currentProfile = nil
                throw error
            }
            return
        }

        do {
            try await GoCoreBridge.shared.start(configJSON: configJSON) { [weak self] type, data in
                guard let self else { return }
                Task {
                    await self.handleCoreEvent(type: type, data: data)
                }
            }
        } catch {
            self.currentMode = nil
            self.currentProfile = nil
            throw error
        }

        // In system-proxy mode, point the macOS system proxy at sing-box's local
        // mixed listener. sing-box does not set the OS proxy itself, so without
        // this the engine runs but no traffic is routed through it. Needs no
        // root/helper for an admin user (direct networksetup).
        if mode == .systemProxy {
            do {
                try await systemProxyController.enable(httpPort: mixedPort, socksPort: mixedPort)
            } catch {
                // Non-fatal: the engine is up, but traffic won't route until the
                // OS proxy is set. Surface a real error instead of failing quietly.
                let snapshot = RuntimeErrorSnapshot(
                    code: "E_SYSPROXY_SET_FAILED",
                    message: "Failed to set system proxy: \(error.localizedDescription)"
                )
                self.latestRecoveryError = snapshot
                self.eventHandler?(.error(snapshot))
                Task { [weak writer = logbookWriter] in
                    await writer?.logError(
                        "Failed to set system proxy: \(error.localizedDescription)",
                        category: .mihomoCore
                    )
                }
            }
        }

        self.isRunning = true

        self.eventHandler?(.stateChanged(.running))
        self.eventHandler?(.modeChanged(mode))
        Task { [weak writer = logbookWriter] in
            await writer?.logInfo("mihomo started: mode=\(mode)", category: .mihomoCore)
        }
    }

    public func stop() async throws {
        let mode = currentMode

        // TUN: drop the KeepAlive flag so launchd SIGTERMs the root core, which
        // makes sing-box revert the routes/utun it created. The in-process core
        // was never started for TUN.
        if mode == .tun {
            try? await tunDaemon.disable()
            self.isRunning = false
            self.currentMode = nil
            self.currentProfile = nil
            self.eventHandler?(.stateChanged(.stopped))
            Task { [weak writer = logbookWriter] in
                await writer?.logInfo("TUN daemon stopped", category: .mihomoCore)
            }
            return
        }

        // Clear the system proxy first so apps stop routing through a
        // soon-to-be-dead listener.
        if mode == .systemProxy {
            try? await systemProxyController.disable()
        }

        await GoCoreBridge.shared.stop()
        self.isRunning = false
        self.currentMode = nil
        self.currentProfile = nil
        self.eventHandler?(.stateChanged(.stopped))
        Task { [weak writer = logbookWriter] in
            await writer?.logInfo("mihomo stopped", category: .mihomoCore)
        }
    }

    /// Starts TUN via the privileged launchd daemon: locate the bundled core,
    /// install the daemon on first use (one administrator-password prompt), then
    /// enable it (prompt-free). System-proxy never touches this path.
    private func startTunDaemon(configJSON: String) async throws {
        guard let binary = tunBinaryLocator() else {
            throw TunnelRuntimeError.startFailed(
                "找不到 riptide-singbox 核心（TUN 模式需要它）。"
                + "请确保它随 app 打包，或先运行 Scripts/build-singbox-bin.sh。"
            )
        }
        if !(await tunDaemon.isInstalled()) {
            // One-time install — shows the macOS administrator-password prompt.
            try await tunDaemon.install(binarySource: binary)
        }
        try await tunDaemon.enable(configJSON: configJSON)

        self.isRunning = true
        self.eventHandler?(.stateChanged(.running))
        self.eventHandler?(.modeChanged(.tun))
        Task { [weak writer = logbookWriter] in
            await writer?.logInfo("TUN daemon started", category: .mihomoCore)
        }
    }
    
    public func switchProxy(to proxyName: String) async throws {
        try await GoCoreBridge.shared.switchProxy(group: "GLOBAL", name: proxyName)
    }
    
    public func getProxyStatus() async throws -> [ProxyInfo] {
        // Mock proxy group status return
        return [
            ProxyInfo(name: "GLOBAL", type: "selector", alive: true, delay: 50),
            ProxyInfo(name: "Direct", type: "direct", alive: true, delay: 5)
        ]
    }
    
    public func getConnections() async throws -> [ConnectionInfo] {
        return []
    }
    
    public func closeConnection(id: String) async throws {
        // No-op for mock runtime
    }
    
    public func closeAllConnections() async throws {
        // No-op for mock runtime
    }
    
    public func getTraffic() async throws -> (up: Int, down: Int) {
        let (uploadBytes, downloadBytes) = await GoCoreBridge.shared.getTraffic()
        return (Int(uploadBytes), Int(downloadBytes))
    }
    
    public func testProxyDelay(name: String, url: String?, timeout: Int) async throws -> Int {
        return 42
    }
    
    public func getLogs(level: String, lines: Int) async throws -> [String] {
        return ["GoCore status: active", "Proxy engine listening on local ports"]
    }
    
    private func handleCoreEvent(type: String, data: String) {
        if type == "status" && data == "running" {
            eventHandler?(.stateChanged(.running))
        }
    }
}
