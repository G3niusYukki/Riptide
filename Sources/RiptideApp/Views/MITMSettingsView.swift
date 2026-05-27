import SwiftUI
import Riptide

/// Settings view for MITM HTTPS interception configuration.
struct MITMSettingsView: View {
    @StateObject private var vm: MITMSettingsViewModel
    @State private var newHost = ""
    @State private var newExcludeHost = ""

    init() {
        _vm = StateObject(wrappedValue: MITMSettingsViewModel())
    }

    var body: some View {
        Form {
            Section("MITM 拦截") {
                Toggle("启用 MITM", isOn: Binding(
                    get: { vm.enabled },
                    set: { newValue in
                        if newValue { vm.enableMITM() } else { vm.disableMITM() }
                    }
                ))

                if vm.enabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("拦截主机模式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if vm.hosts.isEmpty {
                            Text("* (全部)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.hosts, id: \.self) { pattern in
                                HStack {
                                    Text(pattern)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Button {
                                        vm.removeHost(pattern)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            TextField("*.example.com 或 example.com", text: $newHost)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addHost()
                                }
                            Button("添加") {
                                addHost()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("排除主机（不拦截）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(vm.excludeHosts, id: \.self) { pattern in
                            HStack {
                                Text(pattern)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    vm.removeExcludeHost(pattern)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            TextField("api.example.com", text: $newExcludeHost)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addExcludeHost()
                                }
                            Button("添加") {
                                addExcludeHost()
                            }
                        }
                    }
                }
            }

            Section("CA 证书") {
                HStack {
                    Image(systemName: vm.isCAInstalled ? "checkmark.shield.fill" : "shield.slash")
                        .foregroundStyle(vm.isCAInstalled ? .green : .orange)
                    Text(vm.isCAInstalled ? "证书已安装（需在钥匙串中设为始终信任）" : "证书未安装")
                        .font(.caption)
                    Spacer()
                    Button("安装证书") {
                        vm.installCertificate()
                    }
                    .disabled(!vm.enabled)
                }
            }

            if !vm.interceptLog.isEmpty {
                Section("拦截日志") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(vm.interceptLog.prefix(50), id: \.self) { entry in
                                Text(entry)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

            if !vm.httpFlowRecords.isEmpty {
                Section {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(vm.httpFlowRecords.suffix(50).reversed())) { record in
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 6) {
                                        headerBlock("请求头", headers: record.request.headers)
                                        if !record.request.bodyPreview.isEmpty {
                                            bodyPreview("请求 Body", text: record.request.bodyPreviewText)
                                        }
                                        if let response = record.response {
                                            headerBlock("响应头", headers: response.headers)
                                            if !response.bodyPreview.isEmpty {
                                                bodyPreview("响应 Body", text: response.bodyPreviewText)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(record.request.method)
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.semibold)
                                            .frame(width: 46, alignment: .leading)
                                        Text(record.host + record.request.path)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        if let response = record.response {
                                            Text("\(response.statusCode)")
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(statusColor(response.statusCode))
                                        } else {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(byteCount(record))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                } header: {
                    HStack {
                        Text("HTTP Flow")
                        Spacer()
                        Button("清空") {
                            vm.clearHTTPFlowRecords()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MITM 设置")
    }

    private func addHost() {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vm.addHost(trimmed)
        newHost = ""
    }

    private func addExcludeHost() {
        let trimmed = newExcludeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        vm.addExcludeHost(trimmed)
        newExcludeHost = ""
    }

    private func headerBlock(_ title: String, headers: [MITMHTTPHeader]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(headers) { header in
                Text("\(header.name): \(header.value)")
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(2)
            }
        }
    }

    private func bodyPreview(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(6)
                .textSelection(.enabled)
        }
    }

    private func statusColor(_ statusCode: Int) -> Color {
        switch statusCode {
        case 200..<300:
            return .green
        case 300..<400:
            return .blue
        case 400..<500:
            return .orange
        default:
            return .red
        }
    }

    private func byteCount(_ record: MITMHTTPFlowRecord) -> String {
        let total = record.request.bodySize + (record.response?.bodySize ?? 0)
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .binary)
    }
}
