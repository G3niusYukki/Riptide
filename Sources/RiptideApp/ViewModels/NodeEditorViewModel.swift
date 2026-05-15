import Foundation
import Riptide
import Yams

// MARK: - Node Editor ViewModel

/// View model for the node editor UI
@Observable
public final class NodeEditorViewModel: @unchecked Sendable {
    // MARK: - State
    private(set) var nodes: [ProxyNode] = []
    private(set) var selectedNode: ProxyNode?
    private(set) var validationErrors: [String] = []
    private(set) var isSaving: Bool = false
    private(set) var saveError: String?

    // MARK: - Dependencies
    private let profileStore: ProfileStore
    private let validator = ProxyNodeValidator()
    private var currentProfile: Riptide.Profile?

    // MARK: - Initialization
    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    // MARK: - Profile Selection
    public func selectProfile(_ profile: Riptide.Profile) async {
        self.currentProfile = profile
        await loadNodes(from: profile)
    }

    public func loadCurrentProfile() async {
        self.currentProfile = await profileStore.currentProfile()
        if let profile = currentProfile {
            await loadNodes(from: profile)
        }
    }

    // MARK: - Node Management
    public func createNewNode(kind: ProxyKind) async -> EditableProxyNode {
        var defaults = EditableProxyNode.defaults(for: kind)
        defaults.name = generateUniqueName(base: "New \(kind.displayName)")
        return defaults
    }

    public func addNode(_ node: ProxyNode) async throws {
        // Validate first
        let validation = await validator.validate(node: node)
        guard validation.isValid else {
            throw NodeValidationError.validationFailed(validation.errors)
        }

        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }

        isSaving = true
        defer { isSaving = false }

        // Re-import with new node
        let updatedYAML = generateYAMLWithNode(node)
        _ = try await profileStore.importProfile(name: currentProfile!.name, yaml: updatedYAML)

        // Refresh
        await loadCurrentProfile()
    }

    public func updateNode(_ oldNode: ProxyNode, to newNode: ProxyNode) async throws {
        // Validate first
        let validation = await validator.validate(node: newNode)
        guard validation.isValid else {
            throw NodeValidationError.validationFailed(validation.errors)
        }

        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }

        isSaving = true
        defer { isSaving = false }

        // Re-import with updated node
        let updatedYAML = generateUpdatedYAML(replacing: oldNode, with: newNode)
        _ = try await profileStore.importProfile(name: currentProfile!.name, yaml: updatedYAML)

        // Refresh
        await loadCurrentProfile()
    }

    public func deleteNode(_ node: ProxyNode) async throws {
        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }

        // Re-import without the node
        let updatedYAML = generateYAMLWithoutNode(node)
        _ = try await profileStore.importProfile(name: currentProfile!.name, yaml: updatedYAML)

        // Refresh
        await loadCurrentProfile()
    }

    public func duplicateNode(_ node: ProxyNode) async throws -> ProxyNode {
        let newName = generateUniqueName(base: "\(node.name) Copy")
        var newNode = EditableProxyNode(from: node)
        newNode.name = newName

        let proxyNode = newNode.toProxyNode()
        try await addNode(proxyNode)
        return proxyNode
    }

    // MARK: - Validation
    public func validate(_ editableNode: EditableProxyNode) async -> NodeValidationDetails {
        await validator.validate(node: editableNode.toProxyNode())
    }

    public func validateField(_ field: EditableField) async -> ValidationResult {
        switch field {
        case .name(let value):
            return await validator.validate(name: value)
        case .server(let value):
            return await validator.validate(server: value)
        case .port(let value):
            return await validator.validate(port: value)
        case .uuid(let value):
            return await validator.validate(uuid: value)
        case .cipher(let value, let kind):
            return await validator.validateCipher(value, for: kind)
        }
    }

    // MARK: - Private Helpers
    private func loadNodes(from profile: Riptide.Profile) async {
        // Parse YAML to extract proxy nodes
        // This is a simplified version - in production, use proper YAML parsing
        nodes = parseProxiesFromYAML(profile.rawYAML)
    }

    private func parseProxiesFromYAML(_ yaml: String) -> [ProxyNode] {
        guard let (config, _) = try? ClashConfigParser.parse(yaml: yaml) else {
            return []
        }
        return config.proxies
    }

    private func generateYAMLWithNode(_ node: ProxyNode) -> String {
        guard let profile = currentProfile else { return "" }

        guard var raw = try? Yams.load(yaml: profile.rawYAML) as? [String: Any] else {
            // Fallback: append to raw YAML
            let nodeYAML = generateNodeYAML(node)
            return profile.rawYAML + "\nproxies:\n  - \(nodeYAML)"
        }

        var proxies = (raw["proxies"] as? [[String: Any]]) ?? []
        proxies.append(proxyNodeToDict(node))
        raw["proxies"] = proxies

        return (try? Yams.dump(object: raw)) ?? profile.rawYAML
    }

    private func generateUpdatedYAML(replacing oldNode: ProxyNode, with newNode: ProxyNode) -> String {
        guard let profile = currentProfile else { return "" }

        guard var raw = try? Yams.load(yaml: profile.rawYAML) as? [String: Any] else {
            return profile.rawYAML
        }

        if var proxies = raw["proxies"] as? [[String: Any]] {
            if let idx = proxies.firstIndex(where: { ($0["name"] as? String) == oldNode.name }) {
                proxies[idx] = proxyNodeToDict(newNode)
            }
            raw["proxies"] = proxies
        }

        return (try? Yams.dump(object: raw)) ?? profile.rawYAML
    }

    private func generateYAMLWithoutNode(_ node: ProxyNode) -> String {
        guard let profile = currentProfile else { return "" }

        guard var raw = try? Yams.load(yaml: profile.rawYAML) as? [String: Any] else {
            return profile.rawYAML
        }

        if var proxies = raw["proxies"] as? [[String: Any]] {
            proxies.removeAll { ($0["name"] as? String) == node.name }
            raw["proxies"] = proxies
        }

        return (try? Yams.dump(object: raw)) ?? profile.rawYAML
    }

    private func proxyNodeToDict(_ node: ProxyNode) -> [String: Any] {
        var dict: [String: Any] = [
            "name": node.name,
            "type": node.kind.mihomoType,
            "server": node.server,
            "port": node.port
        ]
        if let cipher = node.cipher { dict["cipher"] = cipher }
        if let password = node.password { dict["password"] = password }
        if let uuid = node.uuid { dict["uuid"] = uuid }
        if let flow = node.flow { dict["flow"] = flow }
        if let alterId = node.alterId { dict["alterId"] = alterId }
        if let security = node.security { dict["security"] = security }
        if let sni = node.sni { dict["sni"] = sni }
        if let alpn = node.alpn { dict["alpn"] = alpn }
        if let skipCertVerify = node.skipCertVerify { dict["skip-cert-verify"] = skipCertVerify }
        if let network = node.network { dict["network"] = network }
        if let wsPath = node.wsPath { dict["ws-path"] = wsPath }
        if let wsHost = node.wsHost { dict["ws-headers"] = wsHost }
        if let grpcServiceName = node.grpcServiceName { dict["grpc-service-name"] = grpcServiceName }
        if let snellVersion = node.snellVersion { dict["version"] = snellVersion }
        return dict
    }

    private func generateNodeYAML(_ node: ProxyNode) -> String {
        var lines: [String] = []
        lines.append("name: \"\(node.name)\"")
        lines.append("type: \(node.kind.mihomoType)")
        lines.append("server: \"\(node.server)\"")
        lines.append("port: \(node.port)")

        if let cipher = node.cipher {
            lines.append("cipher: \"\(cipher)\"")
        }
        if let password = node.password {
            lines.append("password: \"\(password)\"")
        }
        if let uuid = node.uuid {
            lines.append("uuid: \"\(uuid)\"")
        }

        return lines.joined(separator: "\n    ")
    }

    private func generateUniqueName(base: String) -> String {
        var name = base
        var counter = 1
        while nodes.contains(where: { $0.name == name }) {
            name = "\(base) \(counter)"
            counter += 1
        }
        return name
    }
}

// MARK: - Supporting Types

public enum EditableField: Sendable {
    case name(String)
    case server(String)
    case port(Int)
    case uuid(String)
    case cipher(String?, ProxyKind)
}

// MARK: - ProxyKind Extension
extension ProxyKind {
    var displayName: String {
        switch self {
        case .http: return "HTTP"
        case .socks5: return "SOCKS5"
        case .shadowsocks: return "Shadowsocks"
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .hysteria2: return "Hysteria2"
        case .snell: return "Snell"
        case .relay: return "Relay"
        case .tuic: return "TUIC"
        case .wireguard: return "WireGuard"
        }
    }

    var mihomoType: String {
        switch self {
        case .shadowsocks: return "ss"
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        case .hysteria2: return "hysteria2"
        case .snell: return "snell"
        case .http: return "http"
        case .socks5: return "socks5"
        case .relay: return "relay"
        case .tuic: return "tuic"
        case .wireguard: return "wireguard"
        }
    }
}
