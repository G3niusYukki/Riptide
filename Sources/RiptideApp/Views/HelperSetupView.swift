import SwiftUI

/// SwiftUI view for installing the privileged helper tool required for TUN mode.
/// This view is presented modally and guides the user through the installation process.
struct HelperSetupView: View {
    @StateObject private var manager = SMJobBlessManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Shield icon
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            // Title and description
            VStack(spacing: 8) {
                Text("Helper Tool Required")
                    .font(.title2.bold())

                Text("TUN mode requires a privileged helper tool to configure network interfaces. This tool runs with root privileges to manage the system-level VPN tunnel.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Installation status
            if manager.isInstalling {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding()
            } else if manager.isHelperInstalled {
                // Installed state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Helper is installed")
                        .font(.headline)
                }
                .padding(.vertical, 8)
            } else {
                // Not installed state
                VStack(spacing: 12) {
                    Button {
                        manager.installHelper()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                            Text("Install Helper Tool")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("Requires administrator password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Error message
            if let error = manager.installationError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .multilineTextAlignment(.center)
            }

            Spacer()

            // Close button (disabled until installed)
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            .disabled(!manager.isHelperInstalled)

            // Debug: Remove helper button (for development only)
            #if DEBUG
            if manager.isHelperInstalled {
                Button {
                    manager.removeHelper()
                } label: {
                    Text("Remove Helper (Debug)")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            #endif
        }
        .padding(32)
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Preview

#Preview("Not Installed") {
    HelperSetupView()
}

#Preview("Installed") {
    // Note: In a real preview, we can't actually install the helper,
    // so this would show the "not installed" state.
    // The preview is mainly for visual layout testing.
    HelperSetupView()
}
