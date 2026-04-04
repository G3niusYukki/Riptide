import SwiftUI
import Riptide

// MARK: - Node Editor View

public struct NodeEditorView: View {
    @State private var viewModel: NodeEditorViewModel
    @State private var editableNode: EditableProxyNode = EditableProxyNode()
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var nodeToDelete: ProxyNode?
    @State private var validationErrors: [String] = []

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
