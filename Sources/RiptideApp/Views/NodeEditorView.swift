import SwiftUI
import AppKit
import Riptide

// MARK: - Node Editor View

public struct NodeEditorView: View {
    @State private var viewModel: NodeEditorViewModel
    @State private var editableNode: EditableProxyNode = EditableProxyNode()
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: ProxyNode?
    @State private var validationErrors: [String] = []
    @State private var qrSheetNode: ProxyNode?
    @State private var showAllQRSheet: Bool = false

    public init(viewModel: NodeEditorViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Proxy Nodes")
                    .font(.headline)
                Spacer()
                Button("Share All") {
                    showAllQRSheet = true
                }
                .disabled(viewModel.nodes.isEmpty)
                Button("+ Add Node") {
                    showAddNodeSheet()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            // Node List
            List(viewModel.nodes) { node in
                NodeRow(node: node)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editableNode = EditableProxyNode(from: node)
                        isEditing = true
                    }
                    .contextMenu {
                        Button("Edit") {
                            editableNode = EditableProxyNode(from: node)
                            isEditing = true
                        }
                        Button("Share as QR Code") {
                            qrSheetNode = node
                        }
                        Button("Duplicate") {
                            Task {
                                _ = try? await viewModel.duplicateNode(node)
                            }
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            nodeToDelete = node
                            showDeleteConfirmation = true
                        }
                    }
            }
        }
        .sheet(isPresented: $isEditing) {
            NodeEditSheet(
                viewModel: viewModel,
                node: $editableNode,
                validationErrors: $validationErrors,
                onSave: { saveNode() },
                onCancel: { isEditing = false }
            )
        }
        .sheet(item: $qrSheetNode) { node in
            NodeQRSheet(nodes: [node])
        }
        .sheet(isPresented: $showAllQRSheet) {
            NodeQRSheet(nodes: viewModel.nodes)
        }
        .alert("Delete Node?", isPresented: $showDeleteConfirmation, presenting: nodeToDelete) { node in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    try? await viewModel.deleteNode(node)
                }
            }
        } message: { node in
            Text("Are you sure you want to delete '\(node.name)'?")
        }
        .task {
            await viewModel.loadCurrentProfile()
        }
    }

    private func showAddNodeSheet() {
        editableNode = EditableProxyNode.defaults(for: .shadowsocks)
        validationErrors = []
        isEditing = true
    }

    private func saveNode() {
        Task {
            let node = editableNode.toProxyNode()

            // Validate
            let validation = await viewModel.validate(editableNode)
            if !validation.isValid {
                validationErrors = validation.errors
                return
            }

            do {
                // Check if this is an edit or new node
                if let existing = viewModel.nodes.first(where: { $0.name == node.name }) {
                    try await viewModel.updateNode(existing, to: node)
                } else {
                    try await viewModel.addNode(node)
                }
                isEditing = false
                validationErrors = []
            } catch {
                validationErrors = [error.localizedDescription]
            }
        }
    }
}

// MARK: - Node Row

struct NodeRow: View {
    let node: ProxyNode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(node.kind.displayName, systemImage: iconForKind(node.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(node.server):\(node.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func iconForKind(_ kind: ProxyKind) -> String {
        switch kind {
        case .shadowsocks: return "lock.shield"
        case .vmess: return "network"
        case .vless: return "bolt"
        case .trojan: return "horse"
        case .hysteria2: return "speedometer"
        case .http: return "globe"
        case .socks5: return "sock"
        case .relay: return "arrow.2.squarepath"
        case .snell: return "lock.square"
        case .tuic: return "lock.shield"
        case .wireguard: return "antenna.radiowaves.left.and.right"
        case .reality, .anytls, .ssh:
            // NOTE(Task 16/17): dedicated SF Symbol once data fields land.
            return "questionmark.circle"
        }
    }
}

// MARK: - Node Edit Sheet

struct NodeEditSheet: View {
    let viewModel: NodeEditorViewModel
    @Binding var node: EditableProxyNode
    @Binding var validationErrors: [String]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                // Validation Errors Section
                if !validationErrors.isEmpty {
                    Section {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Basic Info
                Section("Basic Information") {
                    TextField("Name", text: $node.name)

                    Picker("Type", selection: $node.kind) {
                        ForEach([ProxyKind.shadowsocks, .vmess, .vless, .trojan, .hysteria2, .http, .socks5], id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    TextField("Server", text: $node.server)
                        .textContentType(.URL)

                    TextField("Port", value: $node.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                }

                // Protocol-Specific Fields
                if ProxyFieldRequirements.forKind(node.kind).requiresCipher {
                    Section("Authentication") {
                        Picker("Cipher", selection: $node.cipher) {
                            ForEach(ProxyFieldOptions.shadowsocksCiphers, id: \.self) { cipher in
                                Text(cipher).tag(Optional(cipher))
                            }
                        }

                        SecureField("Password", text: Binding(
                            get: { node.password ?? "" },
                            set: { node.password = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }

                if ProxyFieldRequirements.forKind(node.kind).requiresUUID {
                    Section("VMess/VLESS Settings") {
                        TextField("UUID", text: Binding(
                            get: { node.uuid ?? "" },
                            set: { node.uuid = $0.isEmpty ? nil : $0 }
                        ))

                        if node.kind == .vmess {
                            TextField("Alter ID", value: $node.alterId, format: .number)
                            Picker("Security", selection: $node.security) {
                                ForEach(ProxyFieldOptions.vmessSecurityOptions, id: \.self) { sec in
                                    Text(sec).tag(Optional(sec))
                                }
                            }
                        }

                        if node.kind == .vless {
                            Picker("Flow", selection: $node.flow) {
                                ForEach(ProxyFieldOptions.vlessFlowOptions, id: \.self) { flow in
                                    Text(flow.isEmpty ? "None" : flow).tag(Optional(flow))
                                }
                            }
                        }
                    }
                }

                if ProxyFieldRequirements.forKind(node.kind).requiresPassword && !ProxyFieldRequirements.forKind(node.kind).requiresCipher {
                    Section("Authentication") {
                        SecureField("Password", text: Binding(
                            get: { node.password ?? "" },
                            set: { node.password = $0.isEmpty ? nil : $0 }
                        ))
                    }
                }

                // TLS Settings
                Section("TLS Settings") {
                    TextField("SNI", text: Binding(
                        get: { node.sni ?? "" },
                        set: { node.sni = $0.isEmpty ? nil : $0 }
                    ))

                    Toggle("Skip Cert Verify", isOn: Binding(
                        get: { node.skipCertVerify ?? false },
                        set: { node.skipCertVerify = $0 }
                    ))
                }

                // Network Settings
                if ProxyFieldRequirements.forKind(node.kind).supportsNetwork {
                    Section("Network") {
                        Picker("Network", selection: $node.network) {
                            ForEach(ProxyFieldOptions.networkTypes, id: \.self) { net in
                                Text(net).tag(Optional(net))
                            }
                        }

                        if node.network == "ws" {
                            TextField("WS Path", text: Binding(
                                get: { node.wsPath ?? "" },
                                set: { node.wsPath = $0.isEmpty ? nil : $0 }
                            ))

                            TextField("WS Host", text: Binding(
                                get: { node.wsHost ?? "" },
                                set: { node.wsHost = $0.isEmpty ? nil : $0 }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Edit Proxy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

// MARK: - Extensions

extension ProxyNode: Identifiable {
    public var id: String { name }
}

// MARK: - Node QR Sheet

/// Sheet that displays scannable QR codes for one or more nodes.
/// Reused for both per-row "Share as QR Code" (1 node) and toolbar
/// "Share All" (N nodes). Unsupported kinds are listed in a footer
/// instead of silently dropped.
struct NodeQRSheet: View {
    let nodes: [ProxyNode]
    @Environment(\.dismiss) var dismiss
    @State private var uris: [String: String] = [:]
    @State private var generatedImages: [String: NSImage] = [:]
    @State private var unsupportedNames: [String] = []
    @State private var copyConfirmation: String?
    @State private var saveConfirmation: String?

    private var shareableNodes: [ProxyNode] {
        nodes.filter { generatedImages[$0.id] != nil }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Top status / info
            if unsupportedNames.isEmpty {
                Text("扫一扫二维码即可在手机上导入节点")
                    .foregroundStyle(.secondary)
            } else {
                Text("以下节点不支持分享: \(unsupportedNames.joined(separator: ", "))")
                    .foregroundStyle(.orange)
            }

            // Grid of QRs
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(shareableNodes) { node in
                        VStack(spacing: 6) {
                            if let img = generatedImages[node.id] {
                                Image(nsImage: img)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 200, height: 200)
                            } else {
                                ProgressView().frame(width: 200, height: 200)
                            }
                            Text(node.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding()
            }

            // Bottom action bar
            HStack {
                if let copyConfirmation {
                    Text(copyConfirmation).font(.caption).foregroundStyle(.secondary)
                }
                if let saveConfirmation {
                    Text(saveConfirmation).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy All URIs") { copyAllURIs() }
                    .disabled(uris.isEmpty)
                Button("Save All as PNGs") { saveAllPNGs() }
                    .disabled(generatedImages.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .task { generateAll() }
    }

    private func generateAll() {
        var uris: [String: String] = [:]
        var images: [String: NSImage] = [:]
        var unsupported: [String] = []
        for node in nodes {
            guard let uri = ProxyURISerializer.makeURI(from: node) else {
                unsupported.append(node.name)
                continue
            }
            uris[node.id] = uri
            if let img = QRCodeGenerator.generate(text: uri, size: 400) {
                images[node.id] = img
            }
        }
        self.uris = uris
        self.generatedImages = images
        self.unsupportedNames = unsupported
    }

    private func copyAllURIs() {
        let joined = uris.values.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
        copyConfirmation = "已复制 \(uris.count) 个 URI"
    }

    private func saveAllPNGs() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard let desktop else {
            saveConfirmation = "无法访问 Desktop"
            return
        }
        var saved = 0
        for (id, image) in generatedImages {
            guard let node = nodes.first(where: { $0.id == id }),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let pngData = rep.representation(using: .png, properties: [:]) else { continue }
            let name = node.name.isEmpty ? "node-\(id.prefix(8))" : node.name
            let safeName = name.replacingOccurrences(of: "/", with: "_")
            let url = desktop.appendingPathComponent("riptide-qr-\(safeName).png")
            try? pngData.write(to: url)
            saved += 1
        }
        saveConfirmation = "已保存 \(saved) 张到 Desktop"
    }
}
