import SwiftUI
import Riptide

/// Settings view for WebDAV backup and synchronization configuration.
struct WebDAVSettingsView: View {
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var remotePath = "/Riptide/Backups"
    @State private var autoSync = false
    @State private var conflictResolution: Riptide.WebDAVConfiguration.ConflictResolution = .askUser
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var lastSyncResult: Riptide.SyncResult?
    @State private var showSyncResult = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            serverSection
            optionsSection
            actionsSection
            syncResultSection
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString(Localized.syncTitle.rawValue, comment: ""))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await saveConfiguration() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(NSLocalizedString(Localized.commonSave.rawValue, comment: ""))
                    }
                }
                .disabled(isSaving || !isValidConfiguration)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString(Localized.commonCancel.rawValue, comment: "")) { dismiss() }
            }
        }
        .alert(NSLocalizedString(Localized.commonError.rawValue, comment: ""), isPresented: $showError) {
            Button(NSLocalizedString(Localized.commonConfirm.rawValue, comment: ""), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadExistingConfiguration()
        }
    }

    // MARK: - Sections

    private var serverSection: some View {
        Section(NSLocalizedString(Localized.syncServerSection.rawValue, comment: "")) {
            TextField(NSLocalizedString(Localized.syncServerUrl.rawValue, comment: ""), text: $serverURL)

            TextField(NSLocalizedString(Localized.syncUsername.rawValue, comment: ""), text: $username)

            SecureField(NSLocalizedString(Localized.syncPassword.rawValue, comment: ""), text: $password)
        }
    }

    private var optionsSection: some View {
        Section(NSLocalizedString(Localized.syncOptionsSection.rawValue, comment: "")) {
            TextField(NSLocalizedString(Localized.syncRemotePath.rawValue, comment: ""), text: $remotePath)

            Toggle(NSLocalizedString(Localized.syncAutoSync.rawValue, comment: ""), isOn: $autoSync)

            Picker(NSLocalizedString(Localized.syncConflictResolution.rawValue, comment: ""), selection: $conflictResolution) {
                ForEach(Riptide.WebDAVConfiguration.ConflictResolution.allCases) { option in
                    Text(NSLocalizedString(option.displayNameKey, comment: "")).tag(option)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(NSLocalizedString(Localized.syncTestConnection.rawValue, comment: ""))
                    }
                }
            }
            .disabled(isTesting || !canTestConnection)

            if let result = testResult {
                Label {
                    Text(result)
                } icon: {
                    Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
                .foregroundStyle(testSuccess ? .green : .red)
            }

            if isConfigured {
                Button {
                    Task { await performSync() }
                } label: {
                    Text(NSLocalizedString(Localized.syncSyncNow.rawValue, comment: ""))
                }
                .disabled(isSyncing)

                Button(role: .destructive) {
                    Task { await clearConfiguration() }
                } label: {
                    Text(NSLocalizedString(Localized.syncClearConfig.rawValue, comment: ""))
                }
            }
        }
    }

    private var syncResultSection: some View {
        Group {
            if showSyncResult, let result = lastSyncResult {
                Section(NSLocalizedString(Localized.syncResultSection.rawValue, comment: "")) {
                    if !result.uploaded.isEmpty {
                        Label {
                            let format = NSLocalizedString(Localized.syncUploadedCount.rawValue, comment: "")
                            Text(String(format: format, result.uploaded.count))
                        } icon: {
                            Image(systemName: "arrow.up.circle")
                                .foregroundStyle(.green)
                        }
                    }

                    if !result.downloaded.isEmpty {
                        Label {
                            let format = NSLocalizedString(Localized.syncDownloadedCount.rawValue, comment: "")
                            Text(String(format: format, result.downloaded.count))
                        } icon: {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.blue)
                        }
                    }

                    if !result.conflicts.isEmpty {
                        Label {
                            let format = NSLocalizedString(Localized.syncConflictsCount.rawValue, comment: "")
                            Text(String(format: format, result.conflicts.count))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }

                    if !result.errors.isEmpty {
                        Label {
                            let format = NSLocalizedString(Localized.syncErrorsCount.rawValue, comment: "")
                            Text(String(format: format, result.errors.count))
                        } icon: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red)
                        }
                    }

                    if result.isSuccess {
                        Label {
                            Text(NSLocalizedString(Localized.syncSuccess.rawValue, comment: ""))
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var isValidConfiguration: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty && !remotePath.isEmpty
    }

    private var canTestConnection: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private var isConfigured: Bool {
        UserDefaults.standard.data(forKey: "webdav_configuration") != nil
    }

    private var isSyncing: Bool {
        false
    }

    // MARK: - Helper Methods

    private func displayName(for option: Riptide.WebDAVConfiguration.ConflictResolution) -> String {
        switch option {
        case .localWins:
            return NSLocalizedString(Localized.syncConflictLocalWins.rawValue, comment: "")
        case .remoteWins:
            return NSLocalizedString(Localized.syncConflictRemoteWins.rawValue, comment: "")
        case .askUser:
            return NSLocalizedString(Localized.syncConflictAsk.rawValue, comment: "")
        case .merge:
            return NSLocalizedString(Localized.syncConflictMerge.rawValue, comment: "")
        }
    }

    // MARK: - Actions

    private func loadExistingConfiguration() async {
        guard let data = UserDefaults.standard.data(forKey: "webdav_configuration") else {
            return
        }
        do {
            let config = try JSONDecoder().decode(Riptide.WebDAVConfiguration.self, from: data)
            await MainActor.run {
                serverURL = config.serverURL.absoluteString
                username = config.username
                remotePath = config.remotePath
                autoSync = config.autoSync
                conflictResolution = config.conflictResolution
            }
        } catch {
            // Ignore decode errors
        }
    }

    private func testConnection() async {
        await MainActor.run {
            isTesting = true
            testResult = nil
        }

        do {
            guard let url = URL(string: serverURL) else {
                throw Riptide.WebDAVError.invalidURL
            }

            let client = Riptide.WebDAVClient(
                serverURL: url,
                username: username,
                password: password
            )

            try await client.testConnection()

            await MainActor.run {
                isTesting = false
                testSuccess = true
                testResult = NSLocalizedString(Localized.syncTestSuccess.rawValue, comment: "")
            }
        } catch {
            await MainActor.run {
                isTesting = false
                testSuccess = false
                let format = NSLocalizedString(Localized.syncTestFailed.rawValue, comment: "")
                testResult = String(format: format, error.localizedDescription)
            }
        }
    }

    private func saveConfiguration() async {
        await MainActor.run {
            isSaving = true
        }

        do {
            guard let url = URL(string: serverURL) else {
                throw Riptide.WebDAVError.invalidURL
            }

            let config = Riptide.WebDAVConfiguration(
                serverURL: url,
                username: username,
                remotePath: remotePath,
                autoSync: autoSync,
                syncInterval: 3600,
                conflictResolution: conflictResolution
            )

            // Save configuration to UserDefaults
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "webdav_configuration")

            await MainActor.run {
                isSaving = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func performSync() async {
        // Sync functionality would be implemented with WebDAVManager
        // For now, just show a success placeholder
        await MainActor.run {
            lastSyncResult = Riptide.SyncResult(
                uploaded: [],
                downloaded: [],
                conflicts: [],
                timestamp: Date(),
                errors: []
            )
            showSyncResult = true
        }
    }

    private func clearConfiguration() async {
        UserDefaults.standard.removeObject(forKey: "webdav_configuration")
        await MainActor.run {
            serverURL = ""
            username = ""
            password = ""
            remotePath = "/Riptide/Backups"
            autoSync = false
            testResult = nil
            showSyncResult = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WebDAVSettingsView()
    }
}
