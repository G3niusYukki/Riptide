import Foundation

public actor TunnelControlViewModel {
    private let lifecycleManager: TunnelLifecycleManager
    private let importService: ConfigImportService
    private let eventStore: RuntimeEventStore
    private var mode: RuntimeMode

    public init(
        lifecycleManager: TunnelLifecycleManager,
        importService: ConfigImportService = ConfigImportService(),
        eventStore: RuntimeEventStore = RuntimeEventStore()
    ) {
        self.lifecycleManager = lifecycleManager
        self.importService = importService
        self.eventStore = eventStore
        self.mode = .systemProxy
    }

    public func importConfig(name: String, yaml: String) throws -> ImportedProfile {
        try importService.importProfile(name: name, yaml: yaml)
    }

    public func applyImportedProfileAndStart(_ imported: ImportedProfile) async throws {
        try await lifecycleManager.start(profile: imported.profile)
        let snapshot = await lifecycleManager.status()
        await eventStore.record(.stateChanged(snapshot.state))
    }

    public func stop() async throws {
        try await lifecycleManager.stop()
        let snapshot = await lifecycleManager.status()
        await eventStore.record(.stateChanged(snapshot.state))
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

    // MARK: - Observability

    /// Current observable snapshot (events + connections + throughput).
    public func observableSnapshot() async -> ObservableSnapshot {
        await eventStore.aggregateSnapshot()
    }

    /// Recent log events.
    public func recentEvents(limit: Int = 100) async -> [RuntimeEventStore.RuntimeEventEntry] {
        await eventStore.recentEvents(limit: limit)
    }
}
