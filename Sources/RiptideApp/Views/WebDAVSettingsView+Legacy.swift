// This file has been removed - WebDAVSettingsView is now in Views/Settings/WebDAVSettingsView.swift
// The content below is preserved for reference but commented out to avoid compilation errors.
/*
import SwiftUI
import Riptide

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
    @State private var isSyncing = false
    @State private var lastSyncResult: Riptide.SyncResult?
    @State private var showSyncResult = false
    @State private var existingConfigID: UUID?

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

    private var serverSection: some View {
        Section(NSLocalizedString(Localized.syncServerSection.rawValue, comment: "")) {
            TextField(NSLocalizedString(Localized.syncServerUrl.rawValue, comment: ""), text: $serverURL)
            TextField(NSLocalizedString(Localized.syncUsername.rawValue, comment: ""), text: $username)
            SecureField(NSLocalizedString(Localized.syncPassword.rawValue, comment: ""), text: $password)
        }
    }

    private var isValidConfiguration: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty && !remotePath.isEmpty
    }

    private func saveConfiguration() async {
        // Implementation preserved for reference
    }

    private func loadExistingConfiguration() async {
        // Implementation preserved for reference
    }
}
*/
