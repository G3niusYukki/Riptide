import Foundation
import Testing
@testable import Riptide

// MARK: - Node Editor Tests

@Suite("Node Editor")
struct NodeEditorTests {

    @Test("validates proxy node name")
    func testValidateNodeName() async throws {
        let validator = ProxyNodeValidator()

        // Valid names
        #expect(try await validator.validate(name: "My Proxy").isValid)
        #expect(try await validator.validate(name: "us-east-1").isValid)
        #expect(try await validator.validate(name: "东京节点").isValid)

        // Invalid names
        let emptyResult = try await validator.validate(name: "")
        #expect(!emptyResult.isValid)
        #expect(emptyResult.errorMessage?.contains("name") ?? false)

        let whitespaceResult = try await validator.validate(name: "   ")
        #expect(!whitespaceResult.isValid)
    }

    @Test("validates server address")
    func testValidateServer() async throws {
        let validator = ProxyNodeValidator()

        // Valid servers
        #expect(try await validator.validate(server: "1.2.3.4").isValid)
        #expect(try await validator.validate(server: "example.com").isValid)
        #expect(try await validator.validate(server: "sub.domain.example.com").isValid)
        #expect(try await validator.validate(server: "2001:db8::1").isValid)

        // Invalid servers
        let emptyResult = try await validator.validate(server: "")
        #expect(!emptyResult.isValid)

        let invalidResult = try await validator.validate(server: "not a valid server!!!")
        #expect(!invalidResult.isValid)
    }

    @Test("validates port number")
    func testValidatePort() async throws {
        let validator = ProxyNodeValidator()

        // Valid ports
        #expect(try await validator.validate(port: 1).isValid)
        #expect(try await validator.validate(port: 443).isValid)
        #expect(try await validator.validate(port: 65535).isValid)

        // Invalid ports
        #expect(!(try await validator.validate(port: 0).isValid))
        #expect(!(try await validator.validate(port: -1).isValid))
        #expect(!(try await validator.validate(port: 65536).isValid))
        #expect(!(try await validator.validate(port: 100000).isValid))
    }

    @Test("validates Shadowsocks cipher")
    func testValidateShadowsocksCipher() async throws {
        let validator = ProxyNodeValidator()

        // Valid ciphers
        #expect(try await validator.validateCipher("aes-256-gcm", for: .shadowsocks).isValid)
        #expect(try await validator.validateCipher("chacha20-ietf-poly1305", for: .shadowsocks).isValid)
        #expect(try await validator.validateCipher("aes-128-gcm", for: .shadowsocks).isValid)

        // Invalid ciphers
        let invalidResult = try await validator.validateCipher("invalid-cipher", for: .shadowsocks)
        #expect(!invalidResult.isValid)
    }

    @Test("validates UUID for VMess/VLESS")
    func testValidateUUID() async throws {
        let validator = ProxyNodeValidator()

        // Valid UUIDs
        #expect(try await validator.validate(uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890").isValid)
        #expect(try await validator.validate(uuid: "550e8400-e29b-41d4-a716-446655440000").isValid)

        // Invalid UUIDs
        #expect(!(try await validator.validate(uuid: "").isValid))
        #expect(!(try await validator.validate(uuid: "not-a-uuid").isValid))
        #expect(!(try await validator.validate(uuid: "12345678").isValid))
    }

    @Test("validates complete Shadowsocks node")
    func testValidateCompleteShadowsocksNode() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test SS",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "mypassword"
        )

        let result = try await validator.validate(node: node)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("validates complete VMess node")
    func testValidateCompleteVMessNode() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test VMess",
            kind: .vmess,
            server: "vmess.example.com",
            port: 443,
            uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            alterId: 0,
            security: "auto"
        )

        let result = try await validator.validate(node: node)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("validates complete VLESS node")
    func testValidateCompleteVLESSNode() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test VLESS",
            kind: .vless,
            server: "vless.example.com",
            port: 443,
            uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            flow: "xtls-rprx-vision"
        )

        let result = try await validator.validate(node: node)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("validates complete Trojan node")
    func testValidateCompleteTrojanNode() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test Trojan",
            kind: .trojan,
            server: "trojan.example.com",
            port: 443,
            password: "trojanpassword",
            sni: "example.com"
        )

        let result = try await validator.validate(node: node)
        #expect(result.isValid)
    }

    @Test("validates complete Hysteria2 node")
    func testValidateCompleteHysteria2Node() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test HY2",
            kind: .hysteria2,
            server: "hy2.example.com",
            port: 443,
            password: "hy2password"
        )

        let result = try await validator.validate(node: node)
        #expect(result.isValid)
    }

    @Test("detects missing required fields")
    func testDetectsMissingRequiredFields() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "",
            kind: .shadowsocks,
            server: "",
            port: 0,
            cipher: nil,
            password: nil
        )

        let result = try await validator.validate(node: node)
        #expect(!result.isValid)
        #expect(result.errors.count >= 3)
    }

    @Test("detects missing UUID for VMess")
    func testDetectsMissingUUIDForVMess() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test",
            kind: .vmess,
            server: "example.com",
            port: 443,
            uuid: nil
        )

        let result = try await validator.validate(node: node)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("UUID") })
    }

    @Test("detects missing password for Shadowsocks")
    func testDetectsMissingPasswordForShadowsocks() async throws {
        let validator = ProxyNodeValidator()
        let node = ProxyNode(
            name: "Test",
            kind: .shadowsocks,
            server: "example.com",
            port: 443,
            cipher: "aes-256-gcm",
            password: nil
        )

        let result = try await validator.validate(node: node)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("password") })
    }
}

// MARK: - Node Editor ViewModel Tests

@Suite("Editable Proxy Node")
struct EditableProxyNodeTests {

    @Test("creates new node with defaults")
    func testCreateNewNode() {
        let node = EditableProxyNode.defaults(for: .shadowsocks)

        #expect(node.kind == .shadowsocks)
        #expect(node.server == "")
        #expect(node.cipher == "aes-256-gcm")
        #expect(node.port == 8388)
    }

    @Test("creates VMess node with correct defaults")
    func testCreateVMessNode() {
        let node = EditableProxyNode.defaults(for: .vmess)

        #expect(node.kind == .vmess)
        #expect(node.security == "auto")
        #expect(node.alterId == 0)
        #expect(node.port == 443)
    }

    @Test("creates VLESS node with correct defaults")
    func testCreateVLESSNode() {
        let node = EditableProxyNode.defaults(for: .vless)

        #expect(node.kind == .vless)
        #expect(node.flow == "xtls-rprx-vision")
        #expect(node.port == 443)
    }

    @Test("converts to ProxyNode correctly")
    func testConvertsToProxyNode() {
        var editable = EditableProxyNode()
        editable.name = "Test"
        editable.kind = .shadowsocks
        editable.server = "1.2.3.4"
        editable.port = 443
        editable.cipher = "aes-256-gcm"
        editable.password = "secret"

        let node = editable.toProxyNode()

        #expect(node.name == "Test")
        #expect(node.kind == .shadowsocks)
        #expect(node.server == "1.2.3.4")
        #expect(node.port == 443)
        #expect(node.cipher == "aes-256-gcm")
        #expect(node.password == "secret")
    }

    @Test("initializes from ProxyNode correctly")
    func testInitializesFromProxyNode() {
        let node = ProxyNode(
            name: "Original",
            kind: .trojan,
            server: "example.com",
            port: 443,
            password: "pass123",
            sni: "sni.example.com"
        )

        let editable = EditableProxyNode(from: node)

        #expect(editable.name == "Original")
        #expect(editable.kind == .trojan)
        #expect(editable.server == "example.com")
        #expect(editable.port == 443)
        #expect(editable.password == "pass123")
        #expect(editable.sni == "sni.example.com")
    }
}
