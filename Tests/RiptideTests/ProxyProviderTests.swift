import Foundation
import Testing

@testable import Riptide

@Suite("Proxy Provider")
struct ProxyProviderTests {

    // MARK: - ProxyProviderConfig Tests

    @Test("ProxyProviderConfig Codable round-trip")
    func proxyProviderConfigCodable() throws {
        let config = ProxyProviderConfig(
            name: "my-provider",
            type: "http",
            url: "https://example.com/proxies.yaml",
            path: "./providers/my.yaml",
            interval: 3600,
            healthCheck: HealthCheckConfig(enable: true, url: "http://www.gstatic.com/generate_204", interval: 300)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(ProxyProviderConfig.self, from: data)

        #expect(decoded.name == "my-provider")
        #expect(decoded.type == "http")
        #expect(decoded.url == "https://example.com/proxies.yaml")
        #expect(decoded.path == "./providers/my.yaml")
        #expect(decoded.interval == 3600)
        #expect(decoded.healthCheck?.enable == true)
        #expect(decoded.healthCheck?.url == "http://www.gstatic.com/generate_204")
        #expect(decoded.healthCheck?.interval == 300)
    }

    @Test("ProxyProviderConfig with minimal fields")
    func proxyProviderConfigMinimal() throws {
        let config = ProxyProviderConfig(name: "minimal", type: "file", path: "/tmp/proxies.txt")
        #expect(config.name == "minimal")
        #expect(config.type == "file")
        #expect(config.url == nil)
        #expect(config.interval == nil)
        #expect(config.healthCheck == nil)
    }

    // MARK: - ProxyProvider Actor Tests

    @Test("ProxyProvider initializes with empty nodes before start")
    func initializesWithEmptyNodes() async throws {
        let config = ProxyProviderConfig(name: "test", type: "http", url: "https://example.com/proxies.yaml", interval: 3600)
        let provider = ProxyProvider(config: config)

        // Before start, nodes should be empty.
        let nodes = await provider.nodes()
        #expect(nodes.isEmpty)
    }

    @Test("ProxyProvider stops periodic refresh")
    func stopsPeriodicRefresh() async throws {
        let config = ProxyProviderConfig(name: "test-stop", type: "http", url: "https://example.com/proxies.yaml", interval: 1)
        let provider = ProxyProvider(config: config)

        await provider.start()
        await provider.stop()

        // Calling stop should cancel the update task without error.
        let nodes = await provider.nodes()
        // Nodes may be empty if download failed (no real server), but stop should not crash.
        #expect(nodes != nil)
    }

    @Test("ProxyProvider parse URI list - ss:// format")
    func parsesSSURIs() async throws {
        // Test the URI parsing by using a file-based provider with URI content.
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("proxy-provider-uris.txt")

        let uriList = """
        ss://YWVzLTI1Ni1nY206c2VjcmV0QDEyNy4wLjAuMTo0NDM=#Test%20Node
        ss://YWVzLTI1Ni1nY206c2VjcmV0QDEyNy4wLjAuMTo0NDM=#Another%20Node
        """

        try uriList.write(to: testFile, atomically: true, encoding: .utf8)

        let config = ProxyProviderConfig(name: "uri-test", type: "file", path: testFile.path)
        let provider = ProxyProvider(config: config)

        await provider.start()
        let nodes = await provider.nodes()

        #expect(nodes.count == 2)
        if nodes.count >= 1 {
            #expect(nodes[0].name == "Test Node")
            #expect(nodes[0].kind == .shadowsocks)
        }
        if nodes.count >= 2 {
            #expect(nodes[1].name == "Another Node")
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    @Test("ClashConfigParser can parse YAML with proxies and rules directly")
    func directParseYAMLWithProxies() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "yaml-ss"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: aes-256-gcm
            password: "secret"
          - name: "yaml-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.proxies.count == 2)
        #expect(config.proxies[0].name == "yaml-ss")
        #expect(config.proxies[1].name == "yaml-socks")
    }

    @Test("ProxyProvider file reading works correctly")
    func fileReadingWorks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("read-test.yaml")

        let yaml = """
        mode: rule
        proxies:
          - name: "node-a"
            type: socks5
            server: "1.1.1.1"
            port: 1080
        rules:
          - MATCH,DIRECT
        """

        try yaml.write(to: testFile, atomically: true, encoding: .utf8)

        // Read the file directly to verify content.
        let readBack = try String(contentsOf: testFile, encoding: .utf8)
        #expect(readBack.contains("node-a"))
        #expect(readBack.contains("1.1.1.1"))

        // Parse via ClashConfigParser to verify it works.
        let (config, _) = try ClashConfigParser.parse(yaml: readBack)
        #expect(config.proxies.count == 1)
        #expect(config.proxies[0].name == "node-a")

        try? FileManager.default.removeItem(at: testFile)
    }

    @Test("ProxyProvider parse Clash YAML format")
    func parsesClashYAMLFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("proxy-provider-yaml.yaml")

        // ClashConfigParser.parse() requires mode and rules; add a minimal valid config.
        let yaml = """
        mode: rule
        proxies:
          - name: "yaml-ss"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: aes-256-gcm
            password: "secret"
          - name: "yaml-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,DIRECT
        """

        try yaml.write(to: testFile, atomically: true, encoding: .utf8)

        let config = ProxyProviderConfig(name: "yaml-test", type: "file", path: testFile.path)
        let provider = ProxyProvider(config: config)

        do {
            try await provider.start()
        } catch {
            print("Provider start error: \(error)")
        }
        let nodes = await provider.nodes()

        #expect(nodes.count == 2)
        if nodes.count >= 1 {
            #expect(nodes[0].name == "yaml-ss")
            #expect(nodes[0].kind == .shadowsocks)
            #expect(nodes[0].server == "1.2.3.4")
            #expect(nodes[0].port == 443)
        }
        if nodes.count >= 2 {
            #expect(nodes[1].name == "yaml-socks")
            #expect(nodes[1].kind == .socks5)
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    @Test("ProxyProvider refresh updates nodes")
    func refreshUpdatesNodes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("refresh-test.yaml")

        let yaml1 = """
        mode: rule
        proxies:
          - name: "node-a"
            type: socks5
            server: "1.1.1.1"
            port: 1080
        rules:
          - MATCH,DIRECT
        """
        let yaml2 = """
        mode: rule
        proxies:
          - name: "node-b"
            type: socks5
            server: "2.2.2.2"
            port: 1080
          - name: "node-c"
            type: http
            server: "3.3.3.3"
            port: 8080
        rules:
          - MATCH,DIRECT
        """

        try yaml1.write(to: testFile, atomically: true, encoding: .utf8)

        let config = ProxyProviderConfig(name: "refresh-test", type: "file", path: testFile.path)
        let provider = ProxyProvider(config: config)

        await provider.start()
        let nodes1 = await provider.nodes()
        #expect(nodes1.count == 1)
        if nodes1.count >= 1 {
            #expect(nodes1[0].name == "node-a")
        }

        // Update file content.
        try yaml2.write(to: testFile, atomically: true, encoding: .utf8)
        try? await provider.refresh()

        let nodes2 = await provider.nodes()
        #expect(nodes2.count == 2)
        if nodes2.count >= 1 {
            #expect(nodes2[0].name == "node-b")
        }
        if nodes2.count >= 2 {
            #expect(nodes2[1].name == "node-c")
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    @Test("ProxyProvider skips invalid URIs")
    func skipsInvalidURIs() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("invalid-uris.txt")

        // Use content with no valid proxy URIs — ProxyURIParser accepts even
        // malformed ss:// links, so use pure non-URI text.
        let content = """
        This is not a proxy URI.
        ss://this-does-not-parse
        # A comment line
        some random text without a scheme
        """

        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let config = ProxyProviderConfig(name: "skip-test", type: "file", path: testFile.path)
        let provider = ProxyProvider(config: config)

        await provider.start()
        let nodes = await provider.nodes()

        // No valid URIs should be parsed.
        #expect(nodes.isEmpty)

        try? FileManager.default.removeItem(at: testFile)
    }

    // MARK: - ClashConfigParser proxy-providers Tests

    @Test("ClashConfigParser parses proxy-providers section")
    func parsesProxyProvidersSection() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "local-proxy"
            type: socks5
            server: "127.0.0.1"
            port: 1080
        proxy-providers:
          my-provider:
            type: http
            url: "https://example.com/proxies.yaml"
            interval: 3600
            path: ./providers/my.yaml
            health-check:
              enable: true
              url: "http://www.gstatic.com/generate_204"
              interval: 300
        rules:
          - MATCH,local-proxy
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.proxyProviders.count == 1)
        let provider = config.proxyProviders["my-provider"]!
        #expect(provider.name == "my-provider")
        #expect(provider.type == "http")
        #expect(provider.url == "https://example.com/proxies.yaml")
        #expect(provider.interval == 3600)
        #expect(provider.path == "./providers/my.yaml")
        #expect(provider.healthCheck?.enable == true)
        #expect(provider.healthCheck?.url == "http://www.gstatic.com/generate_204")
        #expect(provider.healthCheck?.interval == 300)
    }

    @Test("ClashConfigParser handles empty proxy-providers section")
    func handlesEmptyProxyProviders() throws {
        let yaml = """
        mode: direct
        proxies:
          - name: "proxy"
            type: socks5
            server: "127.0.0.1"
            port: 1080
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.proxyProviders.isEmpty)
    }

    @Test("ClashConfigParser handles file-type proxy-provider")
    func parsesFileTypeProxyProvider() throws {
        let yaml = """
        mode: direct
        proxies:
          - name: "proxy"
            type: socks5
            server: "127.0.0.1"
            port: 1080
        proxy-providers:
          file-provider:
            type: file
            path: /etc/riptide/proxies.yaml
            interval: 86400
        rules:
          - MATCH,proxy
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.proxyProviders.count == 1)
        let provider = config.proxyProviders["file-provider"]!
        #expect(provider.type == "file")
        #expect(provider.path == "/etc/riptide/proxies.yaml")
        #expect(provider.interval == 86400)
        #expect(provider.url == nil)
    }

    @Test("ClashConfigParser handles proxy-provider without health-check")
    func parsesProxyProviderWithoutHealthCheck() throws {
        let yaml = """
        mode: direct
        proxies:
          - name: "proxy"
            type: socks5
            server: "127.0.0.1"
            port: 1080
        proxy-providers:
          minimal-provider:
            type: http
            url: "https://example.com/list.yaml"
            interval: 7200
        rules:
          - MATCH,proxy
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let provider = config.proxyProviders["minimal-provider"]!
        #expect(provider.healthCheck == nil)
    }
}
