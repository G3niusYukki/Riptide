import SwiftUI

/// SwiftUI view for configuring TUN mode permissions.
/// Offers two paths: sudo (recommended, no certificate needed) or SMJobBless helper tool.
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

            // Title
            VStack(spacing: 8) {
                Text("TUN 模式需要管理员权限")
                    .font(.title2.bold())

                Text("有两种方式可以获取权限：")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Status indicator
            statusBadge

            // Option A: sudo (recommended)
            optionSection(
                title: "方式一：sudo（推荐）",
                description: "启动时 macOS 会弹出密码框，输入一次后缓存 5–15 分钟。无需 Apple 开发者证书。",
                buttonTitle: "使用 sudo 启动",
                buttonIcon: "terminal",
                isPrimary: true,
                action: { dismiss() }
            )

            Divider()

            // Option B: Helper tool
            optionSection(
                title: "方式二：安装 Helper 工具",
                description: "需要 Apple 开发者证书。安装后启动无需密码。",
                buttonTitle: manager.isInstalling ? "正在安装…" : "安装 Helper",
                buttonIcon: "lock.shield",
                isPrimary: false,
                isDisabled: manager.isInstalling || manager.isHelperInstalled,
                action: { manager.installHelper() }
            )

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

            // Close button
            Button {
                dismiss()
            } label: {
                Text("关闭")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)

            // Debug: Remove helper button (for development only)
            #if DEBUG
            if manager.isHelperInstalled {
                Button {
                    manager.removeHelper()
                } label: {
                    Text("移除 Helper（调试）")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            #endif
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 480)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if manager.isInstalling {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("正在安装 Helper 工具…")
                    .font(.callout)
            }
            .padding(.vertical, 4)
        } else if manager.isHelperInstalled {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Helper 工具已安装")
                    .font(.callout.bold())
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Option Section Builder

    private func optionSection(
        title: String,
        description: String,
        buttonTitle: String,
        buttonIcon: String,
        isPrimary: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: buttonIcon)
                    Text(buttonTitle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(isPrimary ? .accentColor : .secondary)
            .controlSize(.large)
            .disabled(isDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview

#Preview("Not Installed") {
    HelperSetupView()
}

#Preview("Installed") {
    HelperSetupView()
}
