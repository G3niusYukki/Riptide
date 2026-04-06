import Foundation
import Security

// MARK: - WebDAV Manager

/// High-level WebDAV sync manager with Keychain credential storage
public actor WebDAVManager {
    private let profileStore: ProfileStore
    private var client: WebDAVClient?
    private var config: WebDAVConfiguration?
    private var syncTask: Task<Void, Never>?
    private var isSyncing = false

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    // MARK: - Configuration

    /// Configure WebDAV sync with the given configuration
    public func configure(_ configuration: WebDAVConfiguration, password: String) async throws {
        self.config = configuration
        self.client = WebDAVClient(
            serverURL: configuration.serverURL,
            username: configuration.username,
            password: password
        )

        do {
            try await client?.testConnection()
            try await savePasswordToKeychain(password, for: configuration.id)

            if configuration.autoSync {
                startAutoSync()
            }
        } catch {
            self.client = nil
            self.config = nil
            throw error
        }
    }

    /// Load saved configuration and password from Keychain
    public func loadConfiguration() async throws -> WebDAVConfiguration? {
        guard let savedData = UserDefaults.standard.data(forKey: "webdav_configuration") else {
            return nil
        }

        let config = try JSONDecoder().decode(WebDAVConfiguration.self, from: savedData)
        self.config = config

        let password = try await loadPasswordFromKeychain(for: config.id)
        self.client = WebDAVClient(
            serverURL: config.serverURL,
            username: config.username,
            password: password
        )

        if config.autoSync {
            startAutoSync()
        }

        return config
    }

    /// Clear the current configuration and remove from Keychain
    public func clearConfiguration() async {
        if let config = config {
            try? await deletePasswordFromKeychain(for: config.id)
        }

        stopAutoSync()
        self.config = nil
        self.client = nil
        UserDefaults.standard.removeObject(forKey: "webdav_configuration")
    }

    /// Save configuration to UserDefaults
    public func saveConfiguration(_ configuration: WebDAVConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        UserDefaults.standard.set(data, forKey: "webdav_configuration")
        self.config = configuration
    }

    // MARK: - Sync Operations

    /// Upload all profiles to the WebDAV server
    public func uploadProfiles() async throws -> SyncResult {
        guard let client = client, let config = config else {
            throw WebDAVError.notConfigured
        }

        guard !isSyncing else {
            throw WebDAVError.syncInProgress
        }

        isSyncing = true
        defer { isSyncing = false }

        let profiles = await profileStore.allProfiles()
        var uploaded: [String] = []
        var errors: [SyncError] = []

        try await ensureDirectoryStructure(client: client, config: config)

        for profile in profiles {
            do {
                let data = try JSONEncoder().encode(profile)
                let path = "\(config.remotePath)/profiles/\(profile.id.uuidString).json"
                try await client.upload(path: path, data: data)
                uploaded.append(profile.name)
            } catch {
                errors.append(SyncError(
                    profileName: profile.name,
                    error: error.localizedDescription
                ))
            }
        }

        let manifest = SyncManifest(
            profiles: profiles.map { profile in
                SyncManifest.ProfileInfo(
                    id: profile.id,
                    name: profile.name,
                    modified: profile.lastRefresh ?? Date(),
                    hash: calculateHash(profile)
                )
            },
            exportedAt: Date(),
            deviceName: Host.current().localizedName ?? "Unknown",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )

        let manifestData = try JSONEncoder().encode(manifest)
        try await client.upload(
            path: "\(config.remotePath)/manifest.json",
            data: manifestData
        )

        return SyncResult(
            uploaded: uploaded,
            downloaded: [],
            conflicts: [],
            timestamp: Date(),
            errors: errors
        )
    }

    /// Download profiles from the WebDAV server
    public func downloadProfiles() async throws -> [Profile] {
        guard let client = client, let config = config else {
            throw WebDAVError.notConfigured
        }

        guard !isSyncing else {
            throw WebDAVError.syncInProgress
        }

        isSyncing = true
        defer { isSyncing = false }

        return try await downloadProfilesInternal(client: client, config: config)
    }

    /// Internal download that bypasses the isSyncing guard (called from sync())
    private func downloadProfilesInternal(client: WebDAVClient, config: WebDAVConfiguration) async throws -> [Profile] {
        let manifestData = try await client.download(
            path: "\(config.remotePath)/manifest.json"
        )
        let manifest = try JSONDecoder().decode(SyncManifest.self, from: manifestData)

        var profiles: [Profile] = []
        var downloadErrors: [SyncError] = []

        for info in manifest.profiles {
            do {
                let data = try await client.download(
                    path: "\(config.remotePath)/profiles/\(info.id.uuidString).json"
                )
                let profile = try JSONDecoder().decode(Profile.self, from: data)
                profiles.append(profile)
            } catch {
                downloadErrors.append(SyncError(
                    profileName: info.name,
                    error: error.localizedDescription
                ))
            }
        }

        // If all downloads failed, throw the first error to signal failure
        if profiles.isEmpty && !downloadErrors.isEmpty {
            throw WebDAVError.downloadFailed("\(downloadErrors.count) profile(s) failed to download")
        }

        return profiles
    }

    /// Perform bidirectional sync with conflict resolution
    public func sync() async throws -> SyncResult {
        guard let config = config else {
            throw WebDAVError.notConfigured
        }

        guard !isSyncing else {
            throw WebDAVError.syncInProgress
        }

        isSyncing = true
        defer { isSyncing = false }

        let remoteProfiles = try await downloadProfilesInternal(client: client!, config: config)
        let localProfiles = await profileStore.allProfiles()

        let localDict = Dictionary(uniqueKeysWithValues: localProfiles.map { ($0.id, $0) })
        let remoteDict = Dictionary(uniqueKeysWithValues: remoteProfiles.map { ($0.id, $0) })

        var uploaded: [String] = []
        var downloaded: [String] = []
        var conflicts: [SyncConflict] = []
        var errors: [SyncError] = []

        let allIDs = Set(localDict.keys).union(remoteDict.keys)

        for id in allIDs {
            let local = localDict[id]
            let remote = remoteDict[id]

            switch (local, remote) {
            case (let local?, nil):
                do {
                    let data = try JSONEncoder().encode(local)
                    let path = "\(config.remotePath)/profiles/\(local.id.uuidString).json"
                    try await client?.upload(path: path, data: data)
                    uploaded.append(local.name)
                } catch {
                    errors.append(SyncError(profileName: local.name, error: error.localizedDescription))
                }

            case (nil, let remote?):
                do {
                    try await profileStore.importProfile(name: remote.name, yaml: remote.rawYAML)
                    downloaded.append(remote.name)
                } catch {
                    errors.append(SyncError(profileName: remote.name, error: error.localizedDescription))
                }

            case (let local?, let remote?):
                let localDate = local.lastRefresh ?? Date.distantPast
                let remoteDate = remote.lastRefresh ?? Date.distantPast

                if localDate > remoteDate.addingTimeInterval(1) {
                    switch config.conflictResolution {
                    case .localWins:
                        do {
                            let data = try JSONEncoder().encode(local)
                            let path = "\(config.remotePath)/profiles/\(local.id.uuidString).json"
                            try await client?.upload(path: path, data: data)
                            uploaded.append(local.name)
                        } catch {
                            errors.append(SyncError(profileName: local.name, error: error.localizedDescription))
                        }

                    case .remoteWins:
                        do {
                            try await profileStore.importProfile(name: remote.name, yaml: remote.rawYAML)
                            downloaded.append(remote.name)
                        } catch {
                            errors.append(SyncError(profileName: remote.name, error: error.localizedDescription))
                        }

                    case .askUser, .merge:
                        let conflict = SyncConflict(
                            profileName: local.name,
                            profileID: local.id,
                            localModified: localDate,
                            remoteModified: remoteDate,
                            localProfile: local,
                            remoteProfile: remote
                        )
                        conflicts.append(conflict)
                    }
                } else if remoteDate > localDate.addingTimeInterval(1) {
                    switch config.conflictResolution {
                    case .localWins:
                        do {
                            let data = try JSONEncoder().encode(local)
                            let path = "\(config.remotePath)/profiles/\(local.id.uuidString).json"
                            try await client?.upload(path: path, data: data)
                            uploaded.append(local.name)
                        } catch {
                            errors.append(SyncError(profileName: local.name, error: error.localizedDescription))
                        }

                    case .remoteWins:
                        do {
                            try await profileStore.importProfile(name: remote.name, yaml: remote.rawYAML)
                            downloaded.append(remote.name)
                        } catch {
                            errors.append(SyncError(profileName: remote.name, error: error.localizedDescription))
                        }

                    case .askUser, .merge:
                        downloaded.append(remote.name)
                    }
                }

            default:
                break
            }
        }

        let manifest = SyncManifest(
            profiles: localProfiles.map { profile in
                SyncManifest.ProfileInfo(
                    id: profile.id,
                    name: profile.name,
                    modified: profile.lastRefresh ?? Date(),
                    hash: calculateHash(profile)
                )
            },
            exportedAt: Date(),
            deviceName: Host.current().localizedName ?? "Unknown",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )

        do {
            let manifestData = try JSONEncoder().encode(manifest)
            try await client?.upload(
                path: "\(config.remotePath)/manifest.json",
                data: manifestData
            )
        } catch {
            errors.append(SyncError(profileName: "manifest", error: error.localizedDescription))
        }

        return SyncResult(
            uploaded: uploaded,
            downloaded: downloaded,
            conflicts: conflicts,
            timestamp: Date(),
            errors: errors
        )
    }

    /// Resolve a conflict by choosing a side
    public func resolveConflict(
        _ conflict: SyncConflict,
        chooseLocal: Bool
    ) async throws -> SyncResult {
        guard let client = client, let config = config else {
            throw WebDAVError.notConfigured
        }

        var uploaded: [String] = []
        var downloaded: [String] = []
        var errors: [SyncError] = []

        if chooseLocal, let local = conflict.localProfile {
            do {
                let data = try JSONEncoder().encode(local)
                let path = "\(config.remotePath)/profiles/\(local.id.uuidString).json"
                try await client.upload(path: path, data: data)
                uploaded.append(local.name)
            } catch {
                errors.append(SyncError(profileName: local.name, error: error.localizedDescription))
            }
        } else if let remote = conflict.remoteProfile {
            downloaded.append(remote.name)
        }

        return SyncResult(
            uploaded: uploaded,
            downloaded: downloaded,
            conflicts: [],
            timestamp: Date(),
            errors: errors
        )
    }

    // MARK: - Auto Sync

    /// Start automatic sync based on the configured interval
    public func startAutoSync() {
        guard let config = config, config.autoSync else { return }

        syncTask?.cancel()
        syncTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(config.syncInterval))
                    guard !Task.isCancelled else { break }
                    _ = try await sync()
                } catch {
                }
            }
        }
    }

    /// Stop automatic sync
    public func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
    }

    /// Check if auto sync is currently running
    public func isAutoSyncRunning() -> Bool {
        syncTask != nil && !(syncTask?.isCancelled ?? true)
    }

    // MARK: - Private Methods

    private func ensureDirectoryStructure(client: WebDAVClient, config: WebDAVConfiguration) async throws {
        // createDirectory already handles 405 (already exists) by returning silently.
        // Let real errors (409 parent missing, 403 permission, etc.) propagate.
        try await client.createDirectory(path: config.remotePath)
        try await client.createDirectory(path: "\(config.remotePath)/profiles")
    }

    private func calculateHash(_ profile: Profile) -> String {
        let data = profile.rawYAML.data(using: .utf8) ?? Data()
        return data.base64EncodedString().prefix(16).description
    }

    // MARK: - Keychain Operations (public for settings UI)

    /// Save a WebDAV password to Keychain (public so settings views can persist credentials).
    public static func savePasswordToKeychain(_ password: String, for configID: UUID) throws {
        let service = "com.riptide.webdav.\(configID.uuidString)"
        let account = "password"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: password.data(using: .utf8)!
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WebDAVError.keychainError("Failed to save password: \(status)")
        }
    }

    private func savePasswordToKeychain(_ password: String, for configID: UUID) async throws {
        let service = "com.riptide.webdav.\(configID.uuidString)"
        let account = "password"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: password.data(using: .utf8)!
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WebDAVError.keychainError("Failed to save password: \(status)")
        }
    }

    private func loadPasswordFromKeychain(for configID: UUID) async throws -> String {
        let service = "com.riptide.webdav.\(configID.uuidString)"
        let account = "password"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw WebDAVError.keychainError("Password not found in keychain")
            }
            throw WebDAVError.keychainError("Failed to load password: \(status)")
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw WebDAVError.keychainError("Invalid password data")
        }

        return password
    }

    private func deletePasswordFromKeychain(for configID: UUID) async throws {
        let service = "com.riptide.webdav.\(configID.uuidString)"
        let account = "password"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Testing

    /// Test the WebDAV connection
    public func testConnection() async throws {
        guard let client = client else {
            throw WebDAVError.notConfigured
        }

        try await client.testConnection()
    }
}

// MARK: - Extension

extension WebDAVManager {
    /// Get current configuration (if any)
    public func currentConfiguration() -> WebDAVConfiguration? {
        config
    }

    /// Check if WebDAV is configured
    public func isConfigured() -> Bool {
        config != nil && client != nil
    }
}
