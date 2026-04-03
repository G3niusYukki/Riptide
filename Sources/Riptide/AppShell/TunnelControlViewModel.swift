import Foundation

public actor TunnelControlViewModel {
    private let lifecycleManager: TunnelLifecycleManager
    private let importService: ConfigImportService
    private var mode: RuntimeMode

    public init(
        lifecycleManager: TunnelLifecycleManager,
        importService: ConfigImportService = ConfigImportService()
    ) {
        self.lifecycleManager = lifecycleManager
        self.importService = importService
        self.mode = .systemProxy
    }

    public func importConfig(name: String, yaml: String) throws -> ImportedProfile {
        try importService.importProfile(name: name, yaml: yaml)
    }

    public func applyImportedProfileAndStart(_ imported: ImportedProfile) async throws {
        try await lifecycleManager.start(profile: imported.profile)
    }

    public func stop() async throws {
        try await lifecycleManager.stop()
    }

    public func currentStatus() async -> TunnelStatusSnapshot {
        await lifecycleManager.status()
    }

    public func setMode(_ mode: RuntimeMode) {
        self.mode = mode
    }

    public func currentMode() -> RuntimeMode {
        mode
    }
}
