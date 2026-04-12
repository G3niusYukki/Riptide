import Foundation
import SwiftUI
import Riptide

// MARK: - Conflict Resolution

enum ConflictResolution: String, CaseIterable, Identifiable {
    case newest = "newest"
    case ask = "ask"
    case merge = "merge"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .newest: return "保留最新"
        case .ask: return "询问我"
        case .merge: return "合并"
        }
    }
    
    var configSyncValue: ConfigSyncManager.ConflictResolution {
        switch self {
        case .newest: return .keepLocal
        case .ask: return .askUser
        case .merge: return .merge
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus: String {
    case unknown
    case connecting
    case connected
    case failed
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }
    
    var description: String {
        switch self {
        case .unknown: return "未测试"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .failed: return "连接失败"
        }
    }
}

// MARK: - WebDAV ViewModel

@MainActor
class WebDAVViewModel: ObservableObject {
    @Published var serverURL: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var autoSync: Bool = false
    @Published var syncInterval: Int = 30
    @Published var conflictResolution: ConflictResolution = .newest
    @Published var lastSyncTime: Date?
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var isSyncing = false
    @Published var localConfigDate: Date?
    @Published var remoteConfigDate: Date?
    @Published var showConflictSheet = false
    @Published var hasPendingConflict = false
    
    private var syncManager: ConfigSyncManager?
    private var syncScheduler: SyncScheduler?
    private var profileStore: ProfileStore?
    private var client: ConfigSyncWebDAVClient?
    
    var isValidConfiguration: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    var canSync: Bool {
        connectionStatus == .connected && !isSyncing
    }
    
    // MARK: - Initialization
    
    init(profileStore: ProfileStore? = nil) {
        self.profileStore = profileStore
        loadSavedCredentials()
    }
    
    // MARK: - Credential Management
    
    func loadSavedCredentials() {
        do {
            if let credentials = try SecureStorage.loadWebDAVCredentials() {
                username = credentials.username
                password = credentials.password
                
                // Load server URL from UserDefaults
                if let savedURL = UserDefaults.standard.string(forKey: "webdav_server_url") {
                    serverURL = savedURL
                }
                
                // Auto-test connection if we have saved credentials
                Task {
                    await testConnection()
                }
            }
            
            // Load settings
            autoSync = UserDefaults.standard.bool(forKey: "webdav_auto_sync")
            let savedInterval = UserDefaults.standard.integer(forKey: "webdav_sync_interval")
            syncInterval = savedInterval > 0 ? savedInterval : 30
            
            if let savedResolution = UserDefaults.standard.string(forKey: "webdav_conflict_resolution"),
               let resolution = ConflictResolution(rawValue: savedResolution) {
                conflictResolution = resolution
            }
            
            if let lastSync = UserDefaults.standard.object(forKey: "webdav_last_sync") as? Date {
                lastSyncTime = lastSync
            }
        } catch {
            showAlert(message: "加载凭证失败: \(error.localizedDescription)")
        }
    }
    
    func saveCredentials() throws {
        let credentials = WebDAVCredentials(username: username, password: password)
        try SecureStorage.saveWebDAVCredentials(credentials)
        
        // Save to UserDefaults
        UserDefaults.standard.set(serverURL, forKey: "webdav_server_url")
        UserDefaults.standard.set(autoSync, forKey: "webdav_auto_sync")
        UserDefaults.standard.set(syncInterval, forKey: "webdav_sync_interval")
        UserDefaults.standard.set(conflictResolution.rawValue, forKey: "webdav_conflict_resolution")
    }
    
    func clearCredentials() {
        do {
            try SecureStorage.deleteWebDAVCredentials()
        } catch {
            print("Failed to delete credentials: \(error)")
        }
        
        UserDefaults.standard.removeObject(forKey: "webdav_server_url")
        UserDefaults.standard.removeObject(forKey: "webdav_auto_sync")
        UserDefaults.standard.removeObject(forKey: "webdav_sync_interval")
        UserDefaults.standard.removeObject(forKey: "webdav_conflict_resolution")
        UserDefaults.standard.removeObject(forKey: "webdav_last_sync")
        
        serverURL = ""
        username = ""
        password = ""
        connectionStatus = .unknown
        autoSync = false
        lastSyncTime = nil
        
        stopAutoSync()
    }
    
    // MARK: - Connection Testing
    
    func testConnection() async {
        guard isValidConfiguration else {
            connectionStatus = .failed
            showAlert(message: "请填写完整的服务器信息")
            return
        }
        
        connectionStatus = .connecting
        
        do {
            guard let url = URL(string: serverURL) else {
                throw WebDAVError.invalidURL
            }
            
            let testClient = ConfigSyncWebDAVClient(
                serverURL: url,
                username: username,
                password: password
            )
            
            // Test by listing root directory
            _ = try await testClient.listFiles(in: "/")
            
            connectionStatus = .connected
            
            // Initialize the actual client and sync manager
            self.client = testClient
            await initializeSyncManager()
            
            // Save credentials on successful connection
            try saveCredentials()
            
            // Start auto-sync if enabled
            if autoSync {
                startAutoSync()
            }
            
        } catch {
            connectionStatus = .failed
            showAlert(message: "连接失败: \(error.localizedDescription)")
        }
    }
    
    private func initializeSyncManager() async {
        guard let client = client, let profileStore = profileStore else {
            return
        }
        
        let configDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Riptide")
        
        syncManager = ConfigSyncManager(
            client: client,
            localConfigDir: configDir,
            profileStore: profileStore
        )
    }
    
    // MARK: - Sync Operations
    
    func syncToRemote() async {
        guard let manager = syncManager else {
            showAlert(message: "请先测试连接")
            return
        }
        
        isSyncing = true
        
        do {
            let result = try await manager.syncToRemote()
            
            if result.success {
                lastSyncTime = result.timestamp
                UserDefaults.standard.set(lastSyncTime, forKey: "webdav_last_sync")
                showAlert(message: result.message)
            } else {
                showAlert(message: "同步失败: \(result.message)")
            }
        } catch {
            showAlert(message: "同步错误: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    func syncFromRemote() async {
        guard let manager = syncManager else {
            showAlert(message: "请先测试连接")
            return
        }
        
        isSyncing = true
        
        do {
            let result = try await manager.syncFromRemote()
            
            if result.success {
                lastSyncTime = result.timestamp
                UserDefaults.standard.set(lastSyncTime, forKey: "webdav_last_sync")
                showAlert(message: result.message)
            } else {
                showAlert(message: "同步失败: \(result.message)")
            }
        } catch {
            showAlert(message: "同步错误: \(error.localizedDescription)")
        }
        
        isSyncing = false
    }
    
    func resolveConflict(_ resolution: ConflictResolution) {
        conflictResolution = resolution
        UserDefaults.standard.set(resolution.rawValue, forKey: "webdav_conflict_resolution")
        hasPendingConflict = false
        showConflictSheet = false
    }
    
    // MARK: - Auto Sync
    
    func startAutoSync() {
        guard connectionStatus == .connected, let manager = syncManager else {
            return
        }
        
        stopAutoSync()
        
        syncScheduler = SyncScheduler(
            syncManager: manager,
            intervalMinutes: syncInterval
        )
        
        Task {
            await syncScheduler?.start()
        }
    }
    
    func stopAutoSync() {
        Task {
            await syncScheduler?.stop()
            syncScheduler = nil
        }
    }
    
    func updateAutoSyncSetting(_ enabled: Bool) {
        autoSync = enabled
        UserDefaults.standard.set(enabled, forKey: "webdav_auto_sync")
        
        if enabled {
            if connectionStatus == .connected {
                startAutoSync()
            }
        } else {
            stopAutoSync()
        }
    }
    
    func updateSyncInterval(_ minutes: Int) {
        syncInterval = minutes
        UserDefaults.standard.set(minutes, forKey: "webdav_sync_interval")
        
        // Restart auto-sync if running
        if autoSync {
            startAutoSync()
        }
    }
    
    // MARK: - Helper Methods
    
    private func showAlert(message: String) {
        alertMessage = message
        showAlert = true
    }
}

// MARK: - Sync Scheduler

actor SyncScheduler {
    private var task: Task<Void, Never>?
    private let interval: TimeInterval
    private let syncManager: ConfigSyncManager
    
    init(syncManager: ConfigSyncManager, intervalMinutes: Int) {
        self.syncManager = syncManager
        self.interval = TimeInterval(intervalMinutes * 60)
    }
    
    func start() {
        stop() // Ensure no duplicate tasks
        
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { break }
                    
                    _ = try await syncManager.syncToRemote()
                    print("Auto sync completed at \(Date())")
                } catch {
                    print("Auto sync failed: \(error)")
                }
            }
        }
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
    
    func isRunning() -> Bool {
        task != nil && !task!.isCancelled
    }
}
