import Foundation

// MARK: - WebDAV Client (Config Sync Variant)

/// Actor-based WebDAV client for configuration synchronization
public actor ConfigSyncWebDAVClient {
    private let baseURL: URL
    private let credentials: WebDAVCredentials
    private let urlSession: URLSession
    
    public init(serverURL: URL, username: String, password: String) {
        self.baseURL = serverURL
        self.credentials = WebDAVCredentials(username: username, password: password)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - WebDAV Operations
    
    /// Upload data to WebDAV server
    public func upload(data: Data, to path: String) async throws {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConfigSyncError.uploadFailed
        }
    }
    
    /// Download data from WebDAV server
    public func download(from path: String) async throws -> Data {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfigSyncError.unknown
        }
        
        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            throw ConfigSyncError.invalidCredentials
        case 404:
            throw ConfigSyncError.notFound
        default:
            throw ConfigSyncError.downloadFailed
        }
    }
    
    /// List files in a directory using PROPFIND
    public func listFiles(in path: String) async throws -> [ConfigSyncWebDAVFile] {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getlastmodified/>
                <D:resourcetype/>
            </D:prop>
        </D:propfind>
        """
        
        request.httpBody = propfindBody.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConfigSyncError.listFailed
        }
        
        return try parseWebDAVResponse(data)
    }
    
    /// Check if a file exists on WebDAV server
    public func fileExists(at path: String) async throws -> Bool {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConfigSyncError.unknown
        }
        
        return httpResponse.statusCode == 200
    }
    
    /// Delete a file from WebDAV server
    public func deleteFile(at path: String) async throws {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw ConfigSyncError.deleteFailed
        }
    }
    
    /// Create a directory on WebDAV server
    public func createDirectory(at path: String) async throws {
        guard let url = resolvedURL(for: path) else {
            throw ConfigSyncError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        request.setValue("Basic \(credentials.base64Encoded)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 else {
            throw ConfigSyncError.uploadFailed
        }
    }
    
    // MARK: - Private Methods
    
    private func resolvedURL(for path: String) -> URL? {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if normalizedPath.isEmpty {
            return baseURL
        }
        
        var base = baseURL
        if !base.absoluteString.hasSuffix("/") {
            base = base.appendingPathComponent("")
        }
        
        return URL(string: normalizedPath, relativeTo: base)?.absoluteURL
    }
    
    private func parseWebDAVResponse(_ data: Data) throws -> [ConfigSyncWebDAVFile] {
        var files: [ConfigSyncWebDAVFile] = []
        
        let parser = XMLParser(data: data)
        let delegate = ConfigPropfindParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            files = delegate.files
        } else if let error = parser.parserError {
            throw ConfigSyncError.parsingError(String(describing: error))
        }
        
        return files
    }
}

// MARK: - Config Propfind Parser Delegate

private final class ConfigPropfindParserDelegate: NSObject, XMLParserDelegate {
    var files: [ConfigSyncWebDAVFile] = []
    
    private var currentElement = ""
    private var currentHref = ""
    private var currentName = ""
    private var currentSize = 0
    private var currentModified = Date()
    private var currentIsDirectory = false
    
    private var elementBuffer = ""
    private var inResponse = false
    private var inPropstat = false
    private var inProp = false
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        
        if elementName == "D:response" || elementName == "response" {
            inResponse = true
            currentHref = ""
            currentName = ""
            currentSize = 0
            currentIsDirectory = false
            elementBuffer = ""
        } else if elementName == "D:propstat" || elementName == "propstat" {
            inPropstat = true
        } else if elementName == "D:prop" || elementName == "prop" {
            inProp = true
        } else if (elementName == "D:collection" || elementName == "collection") && inProp {
            currentIsDirectory = true
        }
        elementBuffer = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        elementBuffer += string
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = elementBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmed.isEmpty {
            if elementName == "D:href" || elementName == "href" {
                currentHref += trimmed
            } else if elementName == "D:displayname" || elementName == "displayname" {
                currentName += trimmed
            } else if elementName == "D:getcontentlength" || elementName == "getcontentlength" {
                currentSize = Int(trimmed) ?? 0
            } else if elementName == "D:getlastmodified" || elementName == "getlastmodified" {
                if let date = parseDAVDate(trimmed) {
                    currentModified = date
                }
            }
        }
        
        if elementName == "D:response" || elementName == "response" {
            inResponse = false
            
            let name = currentName.isEmpty ? (currentHref as NSString).lastPathComponent : currentName
            let path = currentHref
            
            let file = ConfigSyncWebDAVFile(
                path: path,
                name: name,
                size: currentSize,
                modified: currentModified,
                isDirectory: currentIsDirectory
            )
            
            files.append(file)
        } else if elementName == "D:propstat" || elementName == "propstat" {
            inPropstat = false
        } else if elementName == "D:prop" || elementName == "prop" {
            inProp = false
        }
        
        currentElement = ""
    }
    
    private func parseDAVDate(_ string: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Config Sync Manager

/// Manager for synchronizing configuration profiles via WebDAV
public actor ConfigSyncManager {
    private let client: ConfigSyncWebDAVClient
    private let localConfigDir: URL
    private let profileStore: ProfileStore
    private let remotePath = "Riptide/configs/"
    private let maxVersions = 10
    
    // MARK: - Types
    
    /// Sync package containing profiles and settings
    public struct SyncPackage: Codable, Sendable {
        let version: String
        let timestamp: Date
        let profiles: [ProfileData]
        let settings: SettingsData?
    }
    
    /// Profile data for synchronization
    public struct ProfileData: Codable, Sendable {
        let id: UUID
        let name: String
        let sourceKind: ProfileSourceKind
        let rawYAML: String
        let subscriptionURL: String?
        let lastRefresh: Date?
    }
    
    /// Settings data for synchronization
    public struct SettingsData: Codable, Sendable {
        let mode: String
        let systemProxyEnabled: Bool
        let autoStart: Bool
        let theme: String
    }
    
    /// Result of a sync operation
    public struct SyncResult: Sendable {
        public let success: Bool
        public let message: String
        public let filesSynced: Int
        public let timestamp: Date?
    }
    
    /// Conflict resolution strategy
    public enum ConflictResolution: String, Sendable, Codable, CaseIterable {
        case keepLocal = "keep-local"
        case useRemote = "use-remote"
        case askUser = "ask-user"
        case merge = "merge"
        
        public var displayName: String {
            switch self {
            case .keepLocal: return "保留本地"
            case .useRemote: return "使用远程"
            case .askUser: return "询问用户"
            case .merge: return "合并"
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        client: ConfigSyncWebDAVClient,
        localConfigDir: URL,
        profileStore: ProfileStore
    ) {
        self.client = client
        self.localConfigDir = localConfigDir
        self.profileStore = profileStore
    }
    
    // MARK: - Sync Operations
    
    /// Upload local configuration to remote WebDAV server
    public func syncToRemote() async throws -> SyncResult {
        // 1. Get all local profiles
        let profiles = await listLocalProfiles()
        
        // 2. Create sync package
        let package = SyncPackage(
            version: "1.0",
            timestamp: Date(),
            profiles: profiles,
            settings: try loadSettings()
        )
        
        // 3. Ensure remote directory exists
        try await client.createDirectory(at: remotePath)
        
        // 4. Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)
        
        // 5. Upload to WebDAV with timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        let remoteFile = "\(remotePath)config-\(timestamp).json"
        
        try await client.upload(data: data, to: remoteFile)
        
        // 6. Clean up old versions
        try await cleanupOldVersions(keep: maxVersions)
        
        return SyncResult(
            success: true,
            message: "上传成功",
            filesSynced: profiles.count,
            timestamp: Date()
        )
    }
    
    /// Download configuration from remote WebDAV server
    public func syncFromRemote() async throws -> SyncResult {
        // 1. Ensure remote directory exists or list files
        let remoteFiles: [ConfigSyncWebDAVFile]
        do {
            remoteFiles = try await client.listFiles(in: remotePath)
        } catch ConfigSyncError.notFound {
            return SyncResult(
                success: false,
                message: "远程配置目录不存在",
                filesSynced: 0,
                timestamp: nil
            )
        }
        
        // 2. Find latest config file
        let configFiles = remoteFiles.filter { $0.name.hasSuffix(".json") && $0.name.starts(with: "config-") }
        guard let latest = configFiles.sorted(by: { $0.modified > $1.modified }).first else {
            return SyncResult(
                success: false,
                message: "未找到远程配置",
                filesSynced: 0,
                timestamp: nil
            )
        }
        
        // 3. Download the file
        let data = try await client.download(from: latest.path)
        
        // 4. Decode sync package
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(SyncPackage.self, from: data)
        
        // 5. Merge to local
        try await mergeSyncPackage(package)
        
        return SyncResult(
            success: true,
            message: "下载成功 (\(package.timestamp))",
            filesSynced: package.profiles.count,
            timestamp: package.timestamp
        )
    }
    
    /// Resolve conflict between local and remote timestamps
    public func resolveConflict(
        localTimestamp: Date,
        remoteTimestamp: Date,
        strategy: ConflictResolution
    ) async -> ConflictResolution {
        switch strategy {
        case .keepLocal:
            return .keepLocal
        case .useRemote:
            return .useRemote
        case .askUser, .merge:
            // For merge/ask, default to newest
            return localTimestamp > remoteTimestamp ? .keepLocal : .useRemote
        }
    }
    
    // MARK: - Private Methods
    
    private func cleanupOldVersions(keep: Int) async throws {
        let files = try await client.listFiles(in: remotePath)
        let configFiles = files
            .filter { $0.name.hasSuffix(".json") && $0.name.starts(with: "config-") }
            .sorted(by: { $0.modified > $1.modified })
        
        if configFiles.count > keep {
            let toDelete = configFiles.dropFirst(keep)
            for file in toDelete {
                try? await client.deleteFile(at: file.path)
            }
        }
    }
    
    private func listLocalProfiles() async -> [ProfileData] {
        let profiles = await profileStore.allProfiles()
        return profiles.map { profile in
            ProfileData(
                id: profile.id,
                name: profile.name,
                sourceKind: profile.sourceKind,
                rawYAML: profile.rawYAML,
                subscriptionURL: profile.subscriptionURL?.absoluteString,
                lastRefresh: profile.lastRefresh
            )
        }
    }
    
    private func loadSettings() throws -> SettingsData? {
        // Load app settings from UserDefaults
        let defaults = UserDefaults.standard
        
        return SettingsData(
            mode: defaults.string(forKey: "riptide_mode") ?? "rule",
            systemProxyEnabled: defaults.bool(forKey: "system_proxy_enabled"),
            autoStart: defaults.bool(forKey: "auto_start_enabled"),
            theme: defaults.string(forKey: "app_theme") ?? "system"
        )
    }
    
    private func mergeSyncPackage(_ package: SyncPackage) async throws {
        // Import each profile from the package
        for profileData in package.profiles {
            do {
                // Check if profile already exists
                if await profileStore.profile(id: profileData.id) != nil {
                    // Profile exists - we could update it, but ProfileStore doesn't have update
                    // For now, skip existing profiles
                    continue
                } else {
                    // Import as new profile
                    _ = try await profileStore.importProfile(
                        name: profileData.name,
                        yaml: profileData.rawYAML
                    )
                }
            } catch {
                // Log error but continue with other profiles
                print("Failed to import profile \(profileData.name): \(error)")
            }
        }
        
        // Apply settings if present
        if let settings = package.settings {
            let defaults = UserDefaults.standard
            defaults.set(settings.mode, forKey: "riptide_mode")
            defaults.set(settings.systemProxyEnabled, forKey: "system_proxy_enabled")
            defaults.set(settings.autoStart, forKey: "auto_start_enabled")
            defaults.set(settings.theme, forKey: "app_theme")
        }
    }
}

// MARK: - Config Sync WebDAV File

public struct ConfigSyncWebDAVFile: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let size: Int
    public let modified: Date
    public let isDirectory: Bool
    
    public init(
        path: String,
        name: String,
        size: Int = 0,
        modified: Date = Date(),
        isDirectory: Bool = false
    ) {
        self.path = path
        self.name = name
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
    }
}

// MARK: - Config Sync Error

public enum ConfigSyncError: Error, LocalizedError, Sendable {
    case uploadFailed
    case downloadFailed
    case listFailed
    case deleteFailed
    case unknown
    case invalidCredentials
    case invalidURL
    case notFound
    case parsingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "上传失败"
        case .downloadFailed:
            return "下载失败"
        case .listFailed:
            return "列出文件失败"
        case .deleteFailed:
            return "删除失败"
        case .unknown:
            return "未知错误"
        case .invalidCredentials:
            return "无效的凭证"
        case .invalidURL:
            return "无效的 URL"
        case .notFound:
            return "文件不存在"
        case .parsingError(let reason):
            return "解析错误: \(reason)"
        }
    }
}
