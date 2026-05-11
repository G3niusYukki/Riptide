import XCTest
@testable import Riptide

/// Tests for ConfigMerger: error types, merge logic for proxies, rules, DNS, and multi-merge.
final class ConfigMergerTests: XCTestCase {

    // MARK: - Helpers

    private func makeBaseConfig(
        proxies: [ProxyNode] = [],
        rules: [ProxyRule] = [.final(policy: .direct)],
        proxyGroups: [ProxyGroup] = []
    ) -> RiptideConfig {
        RiptideConfig(
            mode: .rule,
            proxies: proxies,
            rules: rules,
            proxyGroups: proxyGroups
        )
    }

    private func makeProxy(name: String, server: String = "1.2.3.4", port: Int = 443) -> ProxyNode {
        ProxyNode(name: name, kind: .shadowsocks, server: server, port: port,
                  cipher: "aes-256-gcm", password: "test")
    }

    // MARK: - MergeError

    func testMergeErrorEquatable() {
        XCTAssertEqual(
            ConfigMerger.MergeError.invalidYAML("bad"),
            ConfigMerger.MergeError.invalidYAML("bad")
        )
        XCTAssertEqual(
            ConfigMerger.MergeError.parseFailed("missing"),
            ConfigMerger.MergeError.parseFailed("missing")
        )
        XCTAssertNotEqual(
            ConfigMerger.MergeError.invalidYAML("a"),
            ConfigMerger.MergeError.invalidYAML("b")
        )
        XCTAssertNotEqual(
            ConfigMerger.MergeError.invalidYAML("x"),
            ConfigMerger.MergeError.parseFailed("x")
        )
    }

    func testMergeErrorLocalizedDescription() {
        let invalid = ConfigMerger.MergeError.invalidYAML("root not a map")
        XCTAssertFalse(invalid.localizedDescription.isEmpty)
        XCTAssertTrue(invalid.localizedDescription.contains("Invalid merge YAML"))

        let parse = ConfigMerger.MergeError.parseFailed("missing fields")
        XCTAssertFalse(parse.localizedDescription.isEmpty)
        XCTAssertTrue(parse.localizedDescription.contains("parse failed"))
    }

    // MARK: - Invalid YAML

    func testMergeThrowsOnInvalidYAML() {
        let base = makeBaseConfig()
        // Completely non-YAML content — Yams or ConfigMerger should throw
        XCTAssertThrowsError(try ConfigMerger.merge(base: base, mergeYAML: "{{invalid"))
    }

    func testMergeThrowsOnEmptyString() {
        let base = makeBaseConfig()
        XCTAssertThrowsError(try ConfigMerger.merge(base: base, mergeYAML: ""))
    }

    func testMergeThrowsOnNonMappingRoot() {
        let base = makeBaseConfig()
        // YAML list at root (not a mapping)
        XCTAssertThrowsError(try ConfigMerger.merge(base: base, mergeYAML: "- item1\n- item2"))
    }

    // MARK: - Empty Merge

    func testMergeWithEmptyMappingReturnsBase() throws {
        let base = makeBaseConfig(
            proxies: [makeProxy(name: "p1")],
            rules: [.final(policy: .direct)]
        )

        let result = try ConfigMerger.merge(base: base, mergeYAML: "{}")

        XCTAssertEqual(result.proxies.count, 1)
        XCTAssertEqual(result.proxies.first?.name, "p1")
        XCTAssertEqual(result.rules.count, 1)
    }

    // MARK: - Proxy Merge

    func testMergeAppendsNewProxy() throws {
        let base = makeBaseConfig(proxies: [makeProxy(name: "existing")])

        let yaml = """
        proxies:
          - name: "new-proxy"
            type: ss
            server: 5.6.7.8
            port: 8388
            cipher: chacha20-ietf-poly1305
            password: pass123
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        XCTAssertEqual(result.proxies.count, 2)
        XCTAssertEqual(result.proxies[0].name, "existing")
        XCTAssertEqual(result.proxies[1].name, "new-proxy")
        XCTAssertEqual(result.proxies[1].server, "5.6.7.8")
        XCTAssertEqual(result.proxies[1].port, 8388)
    }

    func testMergeReplacesExistingProxyByName() throws {
        let base = makeBaseConfig(proxies: [makeProxy(name: "p1", server: "1.1.1.1", port: 443)])

        let yaml = """
        proxies:
          - name: "p1"
            type: ss
            server: 2.2.2.2
            port: 8388
            cipher: aes-128-gcm
            password: newpass
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        XCTAssertEqual(result.proxies.count, 1)
        XCTAssertEqual(result.proxies[0].name, "p1")
        XCTAssertEqual(result.proxies[0].server, "2.2.2.2")
        XCTAssertEqual(result.proxies[0].port, 8388)
    }

    func testMergeProxyTypes() throws {
        let base = makeBaseConfig()

        let yaml = """
        proxies:
          - name: "vmess-node"
            type: vmess
            server: vm.example.com
            port: 443
            uuid: "test-uuid"
          - name: "trojan-node"
            type: trojan
            server: trojan.example.com
            port: 443
            password: trojanpass
          - name: "socks-node"
            type: socks5
            server: socks.example.com
            port: 1080
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        XCTAssertEqual(result.proxies.count, 3)
        XCTAssertEqual(result.proxies[0].kind, .vmess)
        XCTAssertEqual(result.proxies[1].kind, .trojan)
        XCTAssertEqual(result.proxies[2].kind, .socks5)
    }

    // MARK: - Rule Merge

    func testMergeAppendsRules() throws {
        let base = makeBaseConfig(rules: [.final(policy: .direct)])

        let yaml = """
        rules:
          - "DOMAIN-SUFFIX,google.com,PROXY"
          - "DOMAIN,facebook.com,REJECT"
          - "IP-CIDR,10.0.0.0/8,DIRECT"
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        // Original MATCH rule + 3 new rules
        XCTAssertEqual(result.rules.count, 4)
    }

    func testMergeRuleTypes() throws {
        let base = makeBaseConfig(rules: [])

        let yaml = """
        rules:
          - "DOMAIN,example.com,DIRECT"
          - "DOMAIN-SUFFIX,google.com,PROXY"
          - "DOMAIN-KEYWORD,facebook,REJECT"
          - "IP-CIDR,192.168.0.0/16,DIRECT"
          - "GEOIP,CN,DIRECT"
          - "MATCH,unused,PROXY"
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)
        // At least 5 of the 6 rule types should parse (MATCH with dummy payload may not)
        XCTAssertGreaterThanOrEqual(result.rules.count, 5)
    }

    // MARK: - Proxy Group Merge

    func testMergeAppendsNewProxyGroup() throws {
        let base = makeBaseConfig(proxyGroups: [
            ProxyGroup(id: "existing", kind: .select, proxies: ["p1"])
        ])

        let yaml = """
        proxy-groups:
          - name: "new-group"
            type: url-test
            proxies:
              - p1
              - p2
            interval: 300
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        XCTAssertEqual(result.proxyGroups.count, 2)
        XCTAssertEqual(result.proxyGroups[0].id, "existing")
        XCTAssertEqual(result.proxyGroups[1].id, "new-group")
    }

    // MARK: - DNS Merge

    func testMergeDNSFields() throws {
        let base = makeBaseConfig()

        let yaml = """
        dns:
          enable: true
          fake-ip-range: "198.18.0.1/16"
          enhanced-mode: fake-ip
          hosts:
            "example.com": "127.0.0.1"
        """

        let result = try ConfigMerger.merge(base: base, mergeYAML: yaml)

        XCTAssertTrue(result.dnsPolicy.fakeIPEnabled)
        XCTAssertEqual(result.dnsPolicy.fakeIPCIDR, "198.18.0.1/16")
        XCTAssertEqual(result.dnsPolicy.hosts["example.com"], "127.0.0.1")
    }

    func testMergeDNSRedirHostDisablesFakeIP() throws {
        let base = makeBaseConfig()
        // Set fakeIP to true initially
        let baseWithFakeIP = RiptideConfig(
            mode: base.mode, proxies: base.proxies, rules: base.rules,
            proxyGroups: base.proxyGroups,
            dnsPolicy: DNSPolicy(
                fakeIPEnabled: true,
                fakeIPCIDR: "198.18.0.1/16"
            )
        )

        let yaml = """
        dns:
          enhanced-mode: "redir-host"
        """

        let result = try ConfigMerger.merge(base: baseWithFakeIP, mergeYAML: yaml)
        XCTAssertFalse(result.dnsPolicy.fakeIPEnabled)
    }

    // MARK: - Multiple Merges

    func testMultipleMergesAppliedInOrder() throws {
        let base = makeBaseConfig(proxies: [])

        let yaml1 = """
        proxies:
          - name: "p1"
            type: ss
            server: 1.1.1.1
            port: 443
            cipher: aes-256-gcm
            password: pass1
        """

        let yaml2 = """
        proxies:
          - name: "p2"
            type: ss
            server: 2.2.2.2
            port: 8388
            cipher: chacha20-ietf-poly1305
            password: pass2
        """

        let result = try ConfigMerger.merge(base: base, mergeYAMLs: [yaml1, yaml2])

        XCTAssertEqual(result.proxies.count, 2)
        XCTAssertEqual(result.proxies[0].name, "p1")
        XCTAssertEqual(result.proxies[1].name, "p2")
    }

    func testMultipleMergesLaterOverridesEarlier() throws {
        let base = makeBaseConfig(proxies: [])

        let yaml1 = """
        proxies:
          - name: "p1"
            type: ss
            server: 1.1.1.1
            port: 443
            cipher: aes-256-gcm
            password: pass1
        """

        let yaml2 = """
        proxies:
          - name: "p1"
            type: ss
            server: 9.9.9.9
            port: 8388
            cipher: chacha20-ietf-poly1305
            password: newpass
        """

        let result = try ConfigMerger.merge(base: base, mergeYAMLs: [yaml1, yaml2])

        XCTAssertEqual(result.proxies.count, 1)
        XCTAssertEqual(result.proxies[0].server, "9.9.9.9")
        XCTAssertEqual(result.proxies[0].port, 8388)
    }

    func testMultipleMergesWithEmptyArrayReturnsBase() throws {
        let base = makeBaseConfig(proxies: [makeProxy(name: "p1")])
        let result = try ConfigMerger.merge(base: base, mergeYAMLs: [])

        XCTAssertEqual(result.proxies.count, 1)
        XCTAssertEqual(result, base)
    }
}
