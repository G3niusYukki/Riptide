import SwiftUI
import Riptide

// MARK: - MITM Settings View

/// Settings for HTTPS interception (MITM), CA certificate management,
/// host whitelist, and interception log.
struct MITMSettingsView: View {
    @Bindable var vm: AppViewModel
    @State private var mitmEnabled = false
    @State private var hosts: [String] = []
    @State private var excludeHosts: [String] = []
    @State private var newHost = ""
    @State private var newExcludeHost = ""
    @State private var isInstallingCert = false
    @State private var interceptionLog: [String] = []

    private let mitmManager = MITMManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header toggle
                HStack {
                    Label("HTTPS 拦截 (MITM)", systemImage: "lock.shield")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Toggle("", isOn: $mitmEnabled)
                        .onChange(of: mitmEnabled) { _, newValue in
                            Task {
                                var config = await mitmManager.getConfig()
                                config.enabled = newValue
                                await mitmManager.setConfig(config)
                            }
                        }
                }

                // CA Certificate section
                caCertificateSection

                // Host whitelist section
                hostWhitelistSection

                // Exclude list section
                excludeHostSection

                // Interception log
                interceptionLogSection
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            let config = await mitmManager.getConfig()
            mitmEnabled = config.enabled
            hosts = config.hosts
            excludeHosts = config.excludeHosts
        }
    }

    // MARK: - CA Certificate Section

    private var caCertificateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CA 根证书", systemImage: "certificate")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)

            Text("MITM 需要安装 Riptide 自签名的 CA 根证书到系统钥匙串。安装后需要在「钥匙串访问」中手动信任此证书。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    isInstallingCert = true
                    Task {
                        do {
                            try CertificateAuthority().installCA()
                            // Save cert data to temp file for user to inspect
                            if let certData = CertificateAuthority().caCertificateData() {
                                let url = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("Riptide_CA.crt")
                                try certData.write(to: url)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        } catch {
                            // Installation failed — user can do it manually
                        }
                        isInstallingCert = false
                    }
                } label: {
                    Label(
                        isInstallingCert ? "安装中…" : "安装到钥匙串",
                        systemImage: "key"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstallingCert)

                Button {
                    Task {
                        if let certData = await mitmManager.caCertificateData() {
                            let savePanel = NSSavePanel()
                            savePanel.nameFieldStringValue = "Riptide_CA.crt"
                            savePanel.allowedContentTypes = [.x509Certificate]
                            if savePanel.runModal() == .OK,
                               let url = savePanel.url {
                                try certData.write(to: url)
                            }
                        }
                    }
                } label: {
                    Label("导出证书…", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Host Whitelist

    private var hostWhitelistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("拦截域名", systemImage: "list.bullet.rectangle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)

            Text("仅对列表中的域名进行 HTTPS 解密。支持通配符 (*.example.com)。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            // Add new host
            HStack {
                TextField("example.com", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newHost.isEmpty else { return }
                    hosts.append(newHost)
                    newHost = ""
                    saveHosts()
                }
                .buttonStyle(.bordered)
                .disabled(newHost.isEmpty)
            }

            // Existing hosts
            ForEach(hosts, id: \.self) { host in
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(Theme.accent)
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button {
                        hosts.removeAll { $0 == host }
                        saveHosts()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Exclude List

    private var excludeHostSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("排除域名", systemImage: "list.bullet.rectangle.portrait")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)

            Text("即使匹配拦截规则，也不解密这些域名。常用于银行、政府网站。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            HStack {
                TextField("*.bank.com", text: $newExcludeHost)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newExcludeHost.isEmpty else { return }
                    excludeHosts.append(newExcludeHost)
                    newExcludeHost = ""
                    saveHosts()
                }
                .buttonStyle(.bordered)
            }

            ForEach(excludeHosts, id: \.self) { host in
                HStack {
                    Image(systemName: "shield")
                        .foregroundStyle(Theme.warning)
                    Text(host)
                        .font(.caption)
                    Spacer()
                    Button {
                        excludeHosts.removeAll { $0 == host }
                        saveHosts()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Interception Log

    private var interceptionLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("拦截日志", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)

            if interceptionLog.isEmpty {
                Text("暂无拦截记录。启用 MITM 后，匹配的 HTTPS 请求会显示在这里。")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .padding()
            } else {
                ForEach(Array(interceptionLog.prefix(20)), id: \.self) { entry in
                    Text(entry)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.subtext)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Persistence

    private func saveHosts() {
        Task {
            var config = await mitmManager.getConfig()
            config.hosts = hosts
            config.excludeHosts = excludeHosts
            await mitmManager.setConfig(config)
        }
    }
}
