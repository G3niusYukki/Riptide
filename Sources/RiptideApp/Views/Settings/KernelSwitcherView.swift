import SwiftUI

public struct KernelSwitcherView: View {
    public init() {}

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
            Section {
                Text("默认内核为 mihomo。切换到非默认内核需要手动确认并重启 Riptide。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("内核管理")
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
            return Text("已启用").font(.caption.bold()).foregroundStyle(.green)
        case .installed:
            return Text("已安装").font(.caption).foregroundStyle(.secondary)
        case .notInstalled:
            return Text("未安装").font(.caption).foregroundStyle(.secondary)
        case .notSelected:
            return Text("未选择").font(.caption).foregroundStyle(.secondary)
        }
    }
}
