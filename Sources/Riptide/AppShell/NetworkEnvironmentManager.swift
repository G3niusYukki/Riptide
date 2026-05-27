import Foundation
import Network
#if canImport(CoreWLAN)
import CoreWLAN
#endif

// MARK: - Environment Profile

/// A network-environment → proxy-configuration mapping.
/// Each WiFi SSID can be linked to a specific proxy mode and profile.
public struct EnvironmentProfile: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var ssidName: String
    public var proxyMode: ProxyMode
    public var connectionMode: RuntimeMode
    public var profileID: UUID?
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        ssidName: String,
        proxyMode: ProxyMode = .rule,
        connectionMode: RuntimeMode = .systemProxy,
        profileID: UUID? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.ssidName = ssidName
        self.proxyMode = proxyMode
        self.connectionMode = connectionMode
        self.profileID = profileID
        self.enabled = enabled
    }
}

// MARK: - Network Environment Manager

/// Monitors WiFi SSID changes and triggers automatic proxy configuration switches.
/// Falls back gracefully on Ethernet-only machines (no SSID available).
public actor NetworkEnvironmentManager {
    private var profiles: [UUID: EnvironmentProfile] = [:]
    private var currentSSID: String?
    private var isMonitoring = false
    private var changeHandler: (@Sendable (EnvironmentProfile) -> Void)?

    /// UserDefaults key for persisting environment profiles.
    private static let storageKey = "com.riptide.networkEnvironmentProfiles"

    public init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// All configured environment profiles.
    public var allProfiles: [EnvironmentProfile] {
        Array(profiles.values).sorted { $0.ssidName < $1.ssidName }
    }

    /// Returns the profile matching the current SSID, or nil.
    public var activeProfile: EnvironmentProfile? {
        guard let ssid = currentSSID else { return nil }
        return profiles.values.first { $0.ssidName == ssid && $0.enabled }
    }

    /// Sets a handler to be called when the environment changes.
    /// Handler receives the matching EnvironmentProfile, or a default if no match.
    public func setChangeHandler(_ handler: (@Sendable (EnvironmentProfile) -> Void)?) {
        self.changeHandler = handler
    }

    /// Add or update an environment profile.
    public func upsertProfile(_ profile: EnvironmentProfile) {
        profiles[profile.id] = profile
        saveToDisk()
    }

    /// Remove an environment profile.
    public func removeProfile(id: UUID) {
        profiles.removeValue(forKey: id)
        saveToDisk()
    }

    /// Enable or disable a profile.
    public func setEnabled(id: UUID, enabled: Bool) {
        guard var p = profiles[id] else { return }
        p.enabled = enabled
        profiles[id] = p
        saveToDisk()
    }

    /// Get the current WiFi SSID. Returns nil on Ethernet or if CoreWLAN is unavailable.
    public func currentWiFiSSID() -> String? {
        #if canImport(CoreWLAN)
        return CWWiFiClient.shared().interface()?.ssid()
        #else
        return nil
        #endif
    }

    /// Start monitoring SSID changes. Uses NWPathMonitor for interface change detection
    /// combined with periodic SSID polling. The change handler is called when the SSID
    /// differs from the previously observed value.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Snapshot current SSID
        let initial = currentWiFiSSID()
        currentSSID = initial

        // Poll via NWPathMonitor for interface changes
        startNWPathPolling()
    }

    /// Stop monitoring.
    public func stopMonitoring() {
        isMonitoring = false
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Private

    private var pathMonitor: NWPathMonitor?
    private var pathMonitorQueue: DispatchQueue?

    private func startNWPathPolling() {
        let queue = DispatchQueue(label: "com.riptide.env-monitor")
        pathMonitorQueue = queue
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handlePathChange(path) }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    private func handlePathChange(_ path: NWPath) async {
        // On network becoming available, check if SSID changed
        if path.status == .satisfied {
            let newSSID = currentWiFiSSID()
            if newSSID != currentSSID {
                currentSSID = newSSID
                await notifyChange()
            }
        }
    }

    private func notifyChange() async {
        guard let ssid = currentSSID,
              let profile = profiles.values.first(where: { $0.ssidName == ssid && $0.enabled }) else {
            // No matching profile — emit default environment
            let defaultProfile = EnvironmentProfile(
                ssidName: currentSSID ?? "unknown",
                proxyMode: .rule,
                connectionMode: .systemProxy
            )
            changeHandler?(defaultProfile)
            return
        }
        changeHandler?(profile)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(allProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let loaded = try? JSONDecoder().decode([EnvironmentProfile].self, from: data) else {
            return
        }
        for profile in loaded {
            profiles[profile.id] = profile
        }
    }
}
