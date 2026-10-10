import SwiftUI
import Riptide

public struct KernelSwitcherView: View {
    @Bindable var vm: AppViewModel

    public init(vm: AppViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Form {
            Section("可用内核") {
                KernelRow(
                    name: "mihomo (稳定版)",
                    version: "1.18.x",
                    availability: .active
                )
                KernelRow(
                    name: "mihomo (测试版)",
                    version: "—",
                    availability: .notSelected
                )
                KernelRow(
                    name: "sing-box",
                    version: "1.13.x",
                    availability: .notInstalled
                )
            }

            // MARK: - Service Mode
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("服务模式 (riptide-mihomo-service)")
                            .font(.callout)
                        Text(serviceSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    serviceBadge
                }

                if vm.mihomoServiceInstalled {
                    Button(role: .destructive) {
                        Task { await vm.uninstallMihomoService() }
                    } label: {
                        if vm.isModifyingMihomoService {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("卸载服务")
                        }
                    }
                    .disabled(vm.isModifyingMihomoService)
                } else {
                    Button {
                        Task { await vm.installMihomoService() }
                    } label: {
                        if vm.isModifyingMihomoService {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("安装服务")
                        }
                    }
                    .disabled(vm.isModifyingMihomoService)
                }

                if let error = vm.mihomoServiceError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            } header: {
                Text("特权服务")
            } footer: {
                Text("服务模式安装一个 launchd 特权守护进程：安装时请求一次管理员密码，"
                    + "之后启动/停止 mihomo 内核（含 TUN 模式）通过 Unix 套接字 IPC 完成，"
                    + "不再需要每次输入密码。")
            }

            Section {
                Text("默认内核为 mihomo。切换到非默认内核需要手动确认并重启 Riptide。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("内核管理")
        .task {
            await vm.refreshMihomoServiceStatus()
        }
    }

    private var serviceSubtitle: String {
        if vm.isModifyingMihomoService {
            return "正在执行…"
        }
        switch (vm.mihomoServiceInstalled, vm.mihomoServiceOnline) {
        case (true, true):
            return "已安装 · 守护进程运行中 · 版本 \(MihomoServiceProtocol.version)"
        case (true, false):
            return "已安装 · 守护进程未响应"
        case (false, _):
            return "未安装"
        }
    }

    private var serviceBadge: some View {
        switch (vm.mihomoServiceInstalled, vm.mihomoServiceOnline) {
        case (true, true):
            return AnyView(Text("在线").font(.caption.bold()).foregroundStyle(Theme.success))
        case (true, false):
            return AnyView(Text("离线").font(.caption).foregroundStyle(Theme.warning))
        case (false, _):
            return AnyView(Text("未安装").font(.caption).foregroundStyle(.secondary))
        }
    }
}

private struct KernelRow: View {
    enum Availability: Equatable {
        case active
        case installed
        case notInstalled
        case notSelected
    }

    let name: String
    let version: String
    let availability: Availability

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(version).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badge
        }
        .padding(.vertical, 2)
    }

    private var badge: some View {
        switch availability {
        case .active:
            return Text("已启用").font(.caption.bold()).foregroundStyle(Theme.success)
        case .installed:
            return Text("已安装").font(.caption).foregroundStyle(.secondary)
        case .notInstalled:
            return Text("未安装").font(.caption).foregroundStyle(.secondary)
        case .notSelected:
            return Text("未选择").font(.caption).foregroundStyle(.secondary)
        }
    }
}
