import Foundation
import Testing

@testable import Riptide

@Suite("Clash config parser")
struct ClashConfigParserTests {
    @Test("parses supported proxy definitions and ordered rules")
    func parsesValidClashConfig() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "my-ss"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - DOMAIN-SUFFIX,google.com,my-ss
          - DOMAIN-KEYWORD,ads,REJECT
          - IP-CIDR,10.0.0.0/8,DIRECT
          - MATCH,my-socks
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.mode == .rule)
        #expect(config.proxies.count == 2)
        #expect(config.proxies[0].kind == .shadowsocks)
        #expect(config.proxies[1].kind == .socks5)
        #expect(config.rules.count == 4)
        #expect(config.rules[0] == .domainSuffix(suffix: "google.com", policy: .proxyNode(name: "my-ss")))
        #expect(config.rules[1] == .domainKeyword(keyword: "ads", policy: .reject))
        #expect(config.rules[2] == .ipCIDR(cidr: "10.0.0.0/8", policy: .direct))
        #expect(config.rules[3] == .final(policy: .proxyNode(name: "my-socks")))
    }

    @Test("fails when required Shadowsocks fields are missing")
    func failsOnMissingRequiredProxyFields() {
        let yaml = """
        mode: rule
        proxies:
          - name: "broken-ss"
            type: ss
            server: "1.2.3.4"
            port: 443
        rules:
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("fails when rule references unknown proxy")
    func failsOnUnknownProxyReference() {
        let yaml = """
        mode: rule
        proxies:
          - name: "known"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - DOMAIN,example.com,missing
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("direct mode allows empty proxies and rules")
    func directModeAllowsEmptyRuntimeSections() throws {
        let yaml = """
        mode: direct
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.mode == .direct)
        #expect(config.proxies.isEmpty)
        #expect(config.rules.isEmpty)
    }

    @Test("global mode allows proxy list without explicit rules")
    func globalModeAllowsProxyOnlyConfig() throws {
        let yaml = """
        mode: global
        proxies:
          - name: "global-node"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.mode == .global)
        #expect(config.proxies.count == 1)
        #expect(config.rules.isEmpty)
    }

    @Test("parses VMess proxy with all fields")
    func parsesVMessProxyWithAllFields() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "vmess-us"
            type: vmess
            server: "1.2.3.4"
            port: 443
            uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
            alterId: 4
            security: "auto"
            network: "ws"
            sni: "example.com"
            skip-cert-verify: false
            ws-opts:
              path: "/v2"
              headers:
                Host: "example.com"
        rules:
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.proxies.count == 1)
        let node = config.proxies[0]
        #expect(node.kind == .vmess)
        #expect(node.name == "vmess-us")
        #expect(node.server == "1.2.3.4")
        #expect(node.port == 443)
        #expect(node.uuid == "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        #expect(node.alterId == 4)
        #expect(node.security == "auto")
        #expect(node.network == "ws")
        #expect(node.sni == "example.com")
        #expect(node.skipCertVerify == false)
        #expect(node.wsPath == "/v2")
        #expect(node.wsHost == "example.com")
    }

    @Test("fails when VMess uuid is missing")
    func failsOnMissingVMessUUID() {
        let yaml = """
        mode: rule
        proxies:
          - name: "broken-vmess"
            type: vmess
            server: "1.2.3.4"
            port: 443
        rules:
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("parses Hysteria2 proxy with all fields")
    func parsesHysteria2ProxyWithAllFields() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "hysteria2-us"
            type: hysteria2
            server: "1.2.3.4"
            port: 443
            password: "supersecret"
            sni: "example.com"
            skip-cert-verify: true
        rules:
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.proxies.count == 1)
        let node = config.proxies[0]
        #expect(node.kind == .hysteria2)
        #expect(node.name == "hysteria2-us")
        #expect(node.server == "1.2.3.4")
        #expect(node.port == 443)
        #expect(node.password == "supersecret")
        #expect(node.sni == "example.com")
        #expect(node.skipCertVerify == true)
    }

    @Test("parses Hysteria2 proxy with minimal fields")
    func parsesHysteria2ProxyMinimal() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "hysteria2-minimal"
            type: hysteria2
            server: "1.2.3.4"
            port: 443
            password: "secret"
        rules:
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.proxies.count == 1)
        let node = config.proxies[0]
        #expect(node.kind == .hysteria2)
        #expect(node.password == "secret")
        #expect(node.sni == nil)
        #expect(node.skipCertVerify == nil)
    }

    @Test("fails when Hysteria2 password is missing")
    func failsOnMissingHysteria2Password() {
        let yaml = """
        mode: rule
        proxies:
          - name: "broken-hysteria2"
            type: hysteria2
            server: "1.2.3.4"
            port: 443
        rules:
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("parses IP-CIDR6, SRC-IP-CIDR, SRC-PORT, DST-PORT rules")
    func parsesNewRuleTypes() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - IP-CIDR6,2001:db8::/32,proxy-a
          - SRC-IP-CIDR,192.168.0.0/16,proxy-a
          - SRC-PORT,443,proxy-a
          - DST-PORT,80,DIRECT
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.rules.count == 5)
        #expect(config.rules[0] == .ipCIDR6(cidr: "2001:db8::/32", policy: .proxyNode(name: "proxy-a")))
        #expect(config.rules[1] == .srcIPCIDR(cidr: "192.168.0.0/16", policy: .proxyNode(name: "proxy-a")))
        #expect(config.rules[2] == .srcPort(port: 443, policy: .proxyNode(name: "proxy-a")))
        #expect(config.rules[3] == .dstPort(port: 80, policy: .direct))
        #expect(config.rules[4] == .final(policy: .direct))
    }

    @Test("fails on invalid SRC-PORT port number")
    func failsOnInvalidSrcPort() {
        let yaml = """
        mode: rule
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - SRC-PORT,99999,proxy-a
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("fails on invalid DST-PORT port number")
    func failsOnInvalidDstPort() {
        let yaml = """
        mode: rule
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - DST-PORT,-1,proxy-a
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("parses dns hosts configuration")
    func parsesDNSHosts() throws {
        let yaml = """
        mode: rule
        dns:
          nameserver:
            - 8.8.8.8
          hosts:
            example.com: 1.2.3.4
            "*.google.com": 8.8.8.8
            localhost: 127.0.0.1
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,proxy-a
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.dnsPolicy.hosts["example.com"] == "1.2.3.4")
        #expect(config.dnsPolicy.hosts["*.google.com"] == "8.8.8.8")
        #expect(config.dnsPolicy.hosts["localhost"] == "127.0.0.1")
    }

    @Test("parses rule-providers section and RULE-SET rules")
    func parsesRuleProvidersAndRuleSet() throws {
        let yaml = """
        mode: rule
        rule-providers:
          test-provider:
            type: http
            behavior: domain
            url: "https://example.com/rules.yaml"
            interval: 86400
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - RULE-SET,test-provider,proxy-a
          - MATCH,DIRECT
        """

        let (config, providers) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.rules.count == 2)
        #expect(config.rules[0] == .ruleSet(name: "test-provider", policy: .proxyNode(name: "proxy-a")))
        #expect(config.rules[1] == .final(policy: .direct))
        #expect(providers.count == 1)
        #expect(providers["test-provider"] != nil)
    }

    @Test("fails when RULE-SET references unknown provider")
    func failsOnUnknownRuleSetProvider() {
        let yaml = """
        mode: rule
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - RULE-SET,nonexistent-provider,proxy-a
          - MATCH,DIRECT
        """

        #expect(throws: ClashConfigError.self) {
            _ = try ClashConfigParser.parse(yaml: yaml)
        }
    }

    @Test("parses RULE-SET with default DIRECT policy")
    func parsesRuleSetWithDefaultPolicy() throws {
        let yaml = """
        mode: rule
        rule-providers:
          my-provider:
            type: http
            behavior: classical
            url: "https://example.com/rules.yaml"
            interval: 3600
        proxies:
          - name: "proxy-a"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - RULE-SET,my-provider
          - MATCH,DIRECT
        """

        let (config, _) = try ClashConfigParser.parse(yaml: yaml)

        #expect(config.rules.count == 2)
        #expect(config.rules[0] == .ruleSet(name: "my-provider", policy: .direct))
        #expect(config.rules[1] == .final(policy: .direct))
    }
}
