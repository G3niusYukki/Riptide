import Foundation

/// Tunnel runtime backed by the bridged Go Core library.
/// Implements `MihomoRuntimeManaging` to plug seamlessly into the existing app flow.
public actor GoCoreTunnelRuntime: MihomoRuntimeManaging {
    public let helperConnection: HelperToolConnection
    public private(set) var isRunning: Bool = false
    public private(set) var currentMode: RuntimeMode?
    public private(set) var currentProfile: TunnelProfile?
    public private(set) var latestRecoveryError: RuntimeErrorSnapshot?
    
    private var eventHandler: (@Sendable (RuntimeEvent) -> Void)?
    
    public init(helperConnection: HelperToolConnection = HelperToolConnection()) {
        self.helperConnection = helperConnection
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
        self.isRunning = true
        
        // Render a basic config JSON for the Go core bridge
        let mockConfigJSON = "{}"
        
        try await GoCoreBridge.shared.start(configJSON: mockConfigJSON) { [weak self] type, data in
            guard let self else { return }
            Task {
                await self.handleCoreEvent(type: type, data: data)
            }
        }
        
        self.eventHandler?(.stateChanged(.running))
        self.eventHandler?(.modeChanged(mode))
    }
    
    public func stop() async throws {
        await GoCoreBridge.shared.stop()
        self.isRunning = false
        self.currentMode = nil
        self.currentProfile = nil
        self.eventHandler?(.stateChanged(.stopped))
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
        let (up, down) = await GoCoreBridge.shared.getTraffic()
        return (Int(up), Int(down))
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
