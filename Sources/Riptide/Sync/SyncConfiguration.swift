import Foundation

// MARK: - Configuration

/// WebDAV synchronization configuration
public struct WebDAVConfiguration: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let serverURL: URL
    public let username: String
    public let remotePath: String
    public let autoSync: Bool
    public let syncInterval: TimeInterval
    public let conflictResolution: ConflictResolution

    public init(
        id: UUID = UUID(),
        serverURL: URL,
        username: String,
        remotePath: String = "/Riptide/Backups",
        autoSync: Bool = false,
        syncInterval: TimeInterval = 3600,
        conflictResolution: ConflictResolution = .askUser
    ) {
        self.id = id
        self.serverURL = serverURL
        self.username = username
        self.remotePath = remotePath
        self.autoSync = autoSync
        self.syncInterval = syncInterval
        self.conflictResolution = conflictResolution
    }

    public enum ConflictResolution: String, Sendable, Codable, CaseIterable, Identifiable {
        case localWins = "local-wins"
        case remoteWins = "remote-wins"
        case askUser = "ask-user"
        case merge = "merge"

        public var id: String { rawValue }

        public var displayNameKey: String {
            switch self {
            case .localWins:
                return "sync.conflict_local_wins"
            case .remoteWins:
                return "sync.conflict_remote_wins"
            case .askUser:
                return "sync.conflict_ask"
            case .merge:
                return "sync.conflict_merge"
            }
        }
    }
}

// MARK: - Sync Result Types

/// Result of a sync operation
public struct SyncResult: Sendable, Equatable {
    public let uploaded: [String]
    public let downloaded: [String]
    public let conflicts: [SyncConflict]
    public let timestamp: Date
    public let errors: [SyncError]

    public init(
        uploaded: [String] = [],
        downloaded: [String] = [],
        conflicts: [SyncConflict] = [],
        timestamp: Date = Date(),
        errors: [SyncError] = []
    ) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.conflicts = conflicts
        self.timestamp = timestamp
        self.errors = errors
    }

    public var isSuccess: Bool {
        errors.isEmpty && conflicts.isEmpty
    }

    public var hasIssues: Bool {
        !errors.isEmpty || !conflicts.isEmpty
    }
}

/// A sync conflict between local and remote versions
public struct SyncConflict: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let profileName: String
    public let profileID: UUID
    public let localModified: Date
    public let remoteModified: Date
    public let localProfile: Profile?
    public let remoteProfile: Profile?

    public init(
        id: UUID = UUID(),
        profileName: String,
        profileID: UUID,
        localModified: Date,
        remoteModified: Date,
        localProfile: Profile? = nil,
        remoteProfile: Profile? = nil
    ) {
        self.id = id
        self.profileName = profileName
        self.profileID = profileID
        self.localModified = localModified
        self.remoteModified = remoteModified
        self.localProfile = localProfile
        self.remoteProfile = remoteProfile
    }
}

/// A sync error for a specific profile
public struct SyncError: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let profileName: String
    public let error: String

    public init(
        id: UUID = UUID(),
        profileName: String,
        error: String
    ) {
        self.id = id
        self.profileName = profileName
        self.error = error
    }
}

// MARK: - Internal Types

/// Manifest file for sync operations
internal struct SyncManifest: Codable, Sendable, Equatable {
    let profiles: [ProfileInfo]
    let exportedAt: Date
    let deviceName: String
    let appVersion: String

    struct ProfileInfo: Codable, Sendable, Equatable {
        let id: UUID
        let name: String
        let modified: Date
        let hash: String
    }
}

/// WebDAV file metadata
public struct WebDAVFile: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let path: String
    public let name: String
    public let size: Int
    public let modified: Date
    public let isDirectory: Bool
    public let etag: String?

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        size: Int = 0,
        modified: Date = Date(),
        isDirectory: Bool = false,
        etag: String? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.etag = etag
    }
}

// MARK: - Errors

/// Errors that can occur during WebDAV operations
public enum WebDAVError: Error, Equatable, Sendable {
    case notConfigured
    case invalidURL
    case invalidCredentials
    case listFailed(String)
    case downloadFailed(String)
    case uploadFailed(String)
    case deleteFailed(String)
    case networkError(String)
    case parsingError(String)
    case keychainError(String)
    case syncInProgress
    case conflictResolutionFailed
    case serverError(Int, String)
    case notFound

    public var errorDescription: String {
        switch self {
        case .notConfigured:
            return "WebDAV not configured"
        case .invalidURL:
            return "Invalid server URL"
        case .invalidCredentials:
            return "Invalid username or password"
        case .listFailed(let reason):
            return "Failed to list files: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .deleteFailed(let reason):
            return "Delete failed: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .parsingError(let reason):
            return "Parsing error: \(reason)"
        case .keychainError(let reason):
            return "Keychain error: \(reason)"
        case .syncInProgress:
            return "Sync already in progress"
        case .conflictResolutionFailed:
            return "Failed to resolve conflicts"
        case .serverError(let code, let reason):
            return "Server error (\(code)): \(reason)"
        case .notFound:
            return "File not found"
        }
    }

    public var localizationKey: String {
        switch self {
        case .notConfigured:
            return "sync.error_not_configured"
        case .invalidURL:
            return "sync.error_invalid_url"
        case .invalidCredentials:
            return "sync.error_invalid_credentials"
        case .listFailed:
            return "sync.error_list_failed"
        case .downloadFailed:
            return "sync.error_download_failed"
        case .uploadFailed:
            return "sync.error_upload_failed"
        case .deleteFailed:
            return "sync.error_delete_failed"
        case .networkError:
            return "sync.error_network"
        case .parsingError:
            return "sync.error_parsing"
        case .keychainError:
            return "sync.error_keychain"
        case .syncInProgress:
            return "sync.error_in_progress"
        case .conflictResolutionFailed:
            return "sync.error_conflict_resolution"
        case .serverError:
            return "sync.error_server"
        case .notFound:
            return "sync.error_not_found"
        }
    }
}
