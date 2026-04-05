import SwiftUI

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
                    Image(systemName: vm.isCATrusted ? "checkmark.shield.fill" : "shield.slash")
                        .foregroundStyle(vm.isCATrusted ? .green : .orange)
                    Text(vm.isCATrusted ? "证书已安装并信任" : "证书未安装")
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
}
