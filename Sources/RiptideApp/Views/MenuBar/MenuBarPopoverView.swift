import SwiftUI
import AppKit
import Riptide

/// NSPopover content shown when the user clicks the status-bar icon.
///
/// Layout (360×400):
///   Header  → mode card → group card → speed card → shortcut cards → footer
@MainActor
public struct MenuBarPopoverView: View {
    @Bindable public var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            modeCard
            groupCard
            speedCard
            shortcutsCard
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .frame(width: 360, height: 400)
        .background(.regularMaterial)
        .accessibilityIdentifier(A11yID.MenuBar.popover)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isRunning ? "shield.lefthalf.filled" : "shield.slash")
                .foregroundStyle(viewModel.isRunning ? Theme.success : Theme.subtext)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Riptide")
                    .font(.headline)
                Text(viewModel.activeProfile?.name ?? "无配置")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(viewModel.isRunning ? Theme.success : Theme.subtext)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Mode Card

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("运行模式")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("运行模式", selection: $viewModel.connectionMode) {
                    Text("系统代理").tag(ConnectionMode.systemProxy)
                    Text("TUN 模式").tag(ConnectionMode.tun)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewModel.isRunning)
                .accessibilityIdentifier(A11yID.MenuBar.modePicker)

                Button {
                    Task { await viewModel.toggleTunnel() }
                } label: {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? Theme.danger : Theme.success)
                .help(viewModel.isRunning ? "停止" : "启动")
                .accessibilityIdentifier(A11yID.MenuBar.toggleButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Group Card

    private var groupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前组")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(Theme.accent)
                if let group = primaryGroup {
                    Menu {
                        ForEach(viewModel.proxyGroups) { g in
                            Button(g.name) {
                                Task {
                                    if let firstNode = g.selectedNodeName ?? g.nodes.first?.name {
                                        await viewModel.selectProxy(groupID: g.id, nodeName: firstNode)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(group.name)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("·").foregroundStyle(.secondary)
                            Text(group.selectedNodeName ?? "未选择")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.MenuBar.groupSelector)
                } else {
                    Text("无活动配置")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityIdentifier(A11yID.MenuBar.groupCard)
    }

    // MARK: - Speed Card

    private var speedCard: some View {
        HStack(spacing: 0) {
            speedCell(title: "↑ 上传", bytes: viewModel.currentSpeedUp, color: .blue)
            Divider().frame(height: 24)
            speedCell(title: "↓ 下载", bytes: viewModel.currentSpeedDown, color: .green)
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityIdentifier(A11yID.MenuBar.speedCard)
    }

    private func speedCell(title: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatSpeed(bytes))
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shortcut Cards

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快捷切换")
                .font(.caption)
                .foregroundStyle(.secondary)
            if shortcutGroups.isEmpty {
                Text(viewModel.activeProfile == nil ? "导入配置后可使用快捷切换" : "暂无可切换的组")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(shortcutGroups) { group in
                    shortcutRow(for: group)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityIdentifier(A11yID.MenuBar.shortcutsCard)
    }

    private func shortcutRow(for group: ProxyGroupDisplay) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(group.selectedNodeName == nil ? Theme.subtext : Theme.accent)
            Text(group.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)
            Menu {
                ForEach(group.nodes) { node in
                    Button {
                        Task { await viewModel.selectProxy(groupID: group.id, nodeName: node.name) }
                    } label: {
                        HStack {
                            Text(node.name)
                            if node.isSelected {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(group.selectedNodeName ?? "未选择")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label("打开面板", systemImage: "macwindow")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(A11yID.MenuBar.openMainWindowButton)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(A11yID.MenuBar.quitButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var primaryGroup: ProxyGroupDisplay? {
        viewModel.proxyGroups.first(where: {
            $0.kind == .select || $0.kind == .urlTest || $0.kind == .fallback
        }) ?? viewModel.proxyGroups.first
    }

    private var shortcutGroups: [ProxyGroupDisplay] {
        Array(
            viewModel.proxyGroups
                .filter { $0.kind == .select && !$0.nodes.isEmpty }
                .prefix(4)
        )
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let value = Double(bytes)
        let absValue = abs(value)
        switch absValue {
        case 0: return "0 B/s"
        case 1..<1024: return String(format: "%.0f B/s", absValue)
        case 1024..<(1024 * 1024): return String(format: "%.1f KB/s", absValue / 1024)
        case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB/s", absValue / 1024 / 1024)
        default: return String(format: "%.1f GB/s", absValue / 1024 / 1024 / 1024)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = viewModel.mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
