import SwiftUI
import Riptide

/// WebDAV configuration synchronization settings view
@MainActor
struct WebDAVSettingsView: View {
    @StateObject private var viewModel: WebDAVViewModel
    @State private var showConflictResolution = false
    @Environment(\.dismiss) private var dismiss
    
    init(profileStore: ProfileStore? = nil) {
        _viewModel = StateObject(wrappedValue: WebDAVViewModel(profileStore: profileStore))
    }
    
    var body: some View {
        Form {
            serverSection
            syncSettingsSection
            manualSyncSection
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle("WebDAV 同步")
        .alert("同步结果", isPresented: $viewModel.showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
        .sheet(isPresented: $showConflictResolution) {
            ConflictResolutionView(
                localDate: viewModel.localConfigDate,
                remoteDate: viewModel.remoteConfigDate,
                onResolve: { resolution in
                    viewModel.resolveConflict(resolution)
                    showConflictResolution = false
                }
            )
        }
    }
    
    // MARK: - Sections
    
    private var serverSection: some View {
        Section("服务器设置") {
            TextField("服务器地址", text: $viewModel.serverURL)
                .textContentType(.URL)
            
            TextField("用户名", text: $viewModel.username)
                .textContentType(.username)
            
            SecureField("密码", text: $viewModel.password)
                .textContentType(.password)
            
            Button("测试连接") {
                Task { await viewModel.testConnection() }
            }
            .disabled(!viewModel.isValidConfiguration || viewModel.connectionStatus == .connecting)
            
            if viewModel.connectionStatus != .unknown {
                HStack {
                    Text("状态")
                    Spacer()
                    ConnectionStatusView(status: viewModel.connectionStatus)
                }
            }
        }
    }
    
    private var syncSettingsSection: some View {
        Section("同步设置") {
            Toggle("自动同步", isOn: Binding(
                get: { viewModel.autoSync },
                set: { viewModel.updateAutoSyncSetting($0) }
            ))
            
            if viewModel.autoSync {
                Picker("同步间隔", selection: Binding(
                    get: { viewModel.syncInterval },
                    set: { viewModel.updateSyncInterval($0) }
                )) {
                    Text("每 15 分钟").tag(15)
                    Text("每 30 分钟").tag(30)
                    Text("每小时").tag(60)
                    Text("每天").tag(24 * 60)
                }
            }
            
            Picker("冲突解决", selection: $viewModel.conflictResolution) {
                Text("保留最新").tag(ConflictResolution.newest)
                Text("询问我").tag(ConflictResolution.ask)
                Text("合并").tag(ConflictResolution.merge)
            }
        }
    }
    
    private var manualSyncSection: some View {
        Section("手动同步") {
            Button("上传到远程") {
                Task { await viewModel.syncToRemote() }
            }
            .disabled(!viewModel.canSync)
            
            Button("从远程下载") {
                Task { await viewModel.syncFromRemote() }
            }
            .disabled(!viewModel.canSync)
            
            if viewModel.isSyncing {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("同步中...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    private var statusSection: some View {
        Section("同步状态") {
            if let lastSync = viewModel.lastSyncTime {
                HStack {
                    Text("上次同步")
                    Spacer()
                    Text(lastSync, style: .date)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("同步时间")
                    Spacer()
                    Text(lastSync, style: .time)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Text("上次同步")
                    Spacer()
                    Text("从未同步")
                        .foregroundColor(.secondary)
                }
            }
            
            let shouldDisable = viewModel.serverURL.isEmpty && viewModel.username.isEmpty
            Button(role: .destructive) {
                viewModel.clearCredentials()
            } label: {
                Text("清除配置")
            }
            .disabled(shouldDisable)
        }
    }
}

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Conflict Resolution View

struct ConflictResolutionView: View {
    let localDate: Date?
    let remoteDate: Date?
    let onResolve: (ConflictResolution) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("冲突详情") {
                    if let local = localDate {
                        HStack {
                            Text("本地配置时间")
                            Spacer()
                            Text(local, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let remote = remoteDate {
                        HStack {
                            Text("远程配置时间")
                            Spacer()
                            Text(remote, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("选择解决方案") {
                    Button("保留本地配置") {
                        onResolve(.newest)
                    }
                    
                    Button("使用远程配置") {
                        onResolve(.newest)
                    }
                    
                    Button("合并配置") {
                        onResolve(.merge)
                    }
                }
            }
            .navigationTitle("解决冲突")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WebDAVSettingsView()
    }
}
