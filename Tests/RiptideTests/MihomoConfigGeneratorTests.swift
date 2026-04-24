import Foundation
import Testing
@testable import Riptide

@Suite("Mihomo config generator")
struct MihomoConfigGeneratorTests {

    @Test("generates Shadowsocks proxy correctly")
    func testGenerateShadowsocksProxy() throws {
        let node = ProxyNode(
            name: "test-ss",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "testpassword"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-ss"))
        #expect(yaml.contains("type: ss"))
        #expect(yaml.contains("server: 1.2.3.4"))
        #expect(yaml.contains("port: 443"))
        #expect(yaml.contains("cipher: aes-256-gcm"))
        #expect(yaml.contains("password: testpassword"))
    }

    @Test("generates VLESS proxy correctly")
    func testGenerateVLESSProxy() throws {
        let node = ProxyNode(
            name: "test-vless",
            kind: .vless,
            server: "vless.example.com",
            port: 443,
            uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            flow: "xtls-rprx-vision",
            sni: "example.com",
            network: "tcp"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-vless"))
        #expect(yaml.contains("type: vless"))
        #expect(yaml.contains("uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890"))
        #expect(yaml.contains("flow: xtls-rprx-vision"))
        #expect(yaml.contains("servername: example.com"))
        #expect(yaml.contains("network: tcp"))
    }

    @Test("generates complete config with System Proxy mode")
    func testGenerateCompleteConfig() throws {
        let proxy1 = ProxyNode(
            name: "proxy-a",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let proxy2 = ProxyNode(
            name: "proxy-b",
            kind: .socks5,
            server: "5.6.7.8",
            port: 1080
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy1, proxy2],
            rules: [
                .domain(domain: "google.com", policy: .proxyNode(name: "proxy-a")),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152,
            apiPort: 9090
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // Port settings
        #expect(yaml.contains("mixed-port: 6152"))
        #expect(yaml.contains("allow-lan: false"))
        #expect(yaml.contains("mode: rule"))
        #expect(yaml.contains("log-level: info"))
        #expect(yaml.contains("ipv6: true"))
        #expect(yaml.contains("external-controller: 127.0.0.1:9090"))

        // TUN should be disabled in system proxy mode
        #expect(yaml.contains("tun:"))
        #expect(yaml.contains("enable: false"))

        // Proxies section
        #expect(yaml.contains("proxies:"))
        #expect(yaml.contains("name: proxy-a"))
        #expect(yaml.contains("name: proxy-b"))
        #expect(yaml.contains("type: ss"))
        #expect(yaml.contains("type: socks5"))

        // Rules section
        #expect(yaml.contains("rules:"))
        #expect(yaml.contains("DOMAIN,google.com,proxy-a"))
        #expect(yaml.contains("MATCH,DIRECT"))
    }

    @Test("generates TUN mode config correctly")
    func testGenerateTUNModeConfig() throws {
        let proxy = ProxyNode(
            name: "test-proxy",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .tun,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // TUN should be enabled
        #expect(yaml.contains("tun:"))
        #expect(yaml.contains("enable: true"))
        #expect(yaml.contains("stack: gvisor"))
        #expect(yaml.contains("auto-route: true"))
        #expect(yaml.contains("strict-route: true"))
        #expect(yaml.contains("dns-hijack:"))
    }

    @Test("generates proxy groups correctly")
    func testGenerateProxyGroups() throws {
        let proxy1 = ProxyNode(
            name: "node1",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let proxy2 = ProxyNode(
            name: "node2",
            kind: .socks5,
            server: "5.6.7.8",
            port: 1080
        )
        let group = ProxyGroup(
            id: "AutoSelect",
            kind: .urlTest,
            proxies: ["node1", "node2"],
            interval: 300,
            tolerance: 100
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy1, proxy2],
            rules: [.final(policy: .proxyNode(name: "AutoSelect"))],
            proxyGroups: [group]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("proxy-groups:"))
        #expect(yaml.contains("name: AutoSelect"))
        #expect(yaml.contains("type: url-test"))
        #expect(yaml.contains("interval: 300"))
        #expect(yaml.contains("tolerance: 100"))
        #expect(yaml.contains("proxies:"))
        #expect(yaml.contains("- node1"))
        #expect(yaml.contains("- node2"))
        #expect(yaml.contains("MATCH,AutoSelect"))
    }

    @Test("generates all rule types correctly")
    func testGenerateAllRuleTypes() throws {
        let proxy = ProxyNode(
            name: "my-proxy",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy],
            rules: [
                .domain(domain: "example.com", policy: .direct),
                .domainSuffix(suffix: "google.com", policy: .proxyNode(name: "my-proxy")),
                .domainKeyword(keyword: "ads", policy: .reject),
                .ipCIDR(cidr: "10.0.0.0/8", policy: .direct),
                .ipCIDR6(cidr: "2001:db8::/32", policy: .direct),
                .geoIP(countryCode: "CN", policy: .reject),
                .final(policy: .proxyNode(name: "my-proxy"))
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("DOMAIN,example.com,DIRECT"))
        #expect(yaml.contains("DOMAIN-SUFFIX,google.com,my-proxy"))
        #expect(yaml.contains("DOMAIN-KEYWORD,ads,REJECT"))
        #expect(yaml.contains("IP-CIDR,10.0.0.0/8,DIRECT"))
        #expect(yaml.contains("IP-CIDR6,2001:db8::/32,DIRECT"))
        #expect(yaml.contains("GEOIP,CN,REJECT"))
        #expect(yaml.contains("MATCH,my-proxy"))
    }

    @Test("generates VMess proxy correctly")
    func testGenerateVMessProxy() throws {
        let node = ProxyNode(
            name: "test-vmess",
            kind: .vmess,
            server: "vmess.example.com",
            port: 443,
            uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            alterId: 4,
            security: "auto",
            sni: "example.com",
            network: "ws",
            wsPath: "/v2",
            wsHost: "example.com"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-vmess"))
        #expect(yaml.contains("type: vmess"))
        #expect(yaml.contains("uuid: a1b2c3d4-e5f6-7890-abcd-ef1234567890"))
        #expect(yaml.contains("alterId: 4"))
        #expect(yaml.contains("cipher: auto"))
        #expect(yaml.contains("network: ws"))
        #expect(yaml.contains("servername: example.com"))
    }

    @Test("generates Trojan proxy correctly")
    func testGenerateTrojanProxy() throws {
        let node = ProxyNode(
            name: "test-trojan",
            kind: .trojan,
            server: "trojan.example.com",
            port: 443,
            password: "trojanpassword",
            sni: "example.com"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-trojan"))
        #expect(yaml.contains("type: trojan"))
        #expect(yaml.contains("password: trojanpassword"))
        #expect(yaml.contains("sni: example.com"))
    }

    @Test("generates Hysteria2 proxy correctly")
    func testGenerateHysteria2Proxy() throws {
        let node = ProxyNode(
            name: "test-hy2",
            kind: .hysteria2,
            server: "hy2.example.com",
            port: 443,
            password: "hy2password",
            sni: "example.com"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-hy2"))
        #expect(yaml.contains("type: hysteria2"))
        #expect(yaml.contains("password: hy2password"))
        #expect(yaml.contains("sni: example.com"))
    }

    @Test("generates HTTP proxy correctly with cipher as username")
    func testGenerateHTTPProxy() throws {
        let node = ProxyNode(
            name: "test-http",
            kind: .http,
            server: "http.example.com",
            port: 8080,
            cipher: "myusername",
            password: "httppassword"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-http"))
        #expect(yaml.contains("type: http"))
        #expect(yaml.contains("username: myusername"))
        #expect(yaml.contains("password: httppassword"))
    }

    @Test("generates SOCKS5 proxy correctly with cipher as username")
    func testGenerateSocks5Proxy() throws {
        let node = ProxyNode(
            name: "test-socks",
            kind: .socks5,
            server: "socks.example.com",
            port: 1080,
            cipher: "sockuser",
            password: "sockspass"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: test-socks"))
        #expect(yaml.contains("type: socks5"))
        #expect(yaml.contains("username: sockuser"))
        #expect(yaml.contains("password: sockspass"))
    }

    @Test("generates load-balance group with strategy")
    func testGenerateLoadBalanceGroup() throws {
        let proxy1 = ProxyNode(
            name: "node1",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let group = ProxyGroup(
            id: "LoadBalance",
            kind: .loadBalance,
            proxies: ["node1", "DIRECT"],
            interval: 300,
            strategy: .consistentHashing
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy1],
            rules: [.final(policy: .proxyNode(name: "LoadBalance"))],
            proxyGroups: [group]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: LoadBalance"))
        #expect(yaml.contains("type: load-balance"))
        #expect(yaml.contains("strategy: consistent-hashing"))
        #expect(yaml.contains("interval: 300"))
    }

    @Test("generates fallback group correctly")
    func testGenerateFallbackGroup() throws {
        let proxy1 = ProxyNode(
            name: "node1",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let group = ProxyGroup(
            id: "Fallback",
            kind: .fallback,
            proxies: ["node1", "DIRECT"],
            interval: 300
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy1],
            rules: [.final(policy: .proxyNode(name: "Fallback"))],
            proxyGroups: [group]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: Fallback"))
        #expect(yaml.contains("type: fallback"))
        #expect(yaml.contains("interval: 300"))
    }

    @Test("generates select group correctly")
    func testGenerateSelectGroup() throws {
        let proxy1 = ProxyNode(
            name: "node1",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let group = ProxyGroup(
            id: "ManualSelect",
            kind: .select,
            proxies: ["node1", "DIRECT", "REJECT"]
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy1],
            rules: [.final(policy: .proxyNode(name: "ManualSelect"))],
            proxyGroups: [group]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        #expect(yaml.contains("name: ManualSelect"))
        #expect(yaml.contains("type: select"))
        #expect(yaml.contains("proxies:"))
        #expect(yaml.contains("- node1"))
        #expect(yaml.contains("- DIRECT"))
        #expect(yaml.contains("- REJECT"))
    }

    @Test("properly escapes YAML special characters in proxy name")
    func testYAMLEscapingInProxyName() throws {
        let node = ProxyNode(
            name: "test: \"proxy\"",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // Name with quotes should be escaped and wrapped in quotes
        #expect(yaml.contains("name: \"test: \\\"proxy\\\"\""))
    }

    @Test("properly escapes YAML special characters in password")
    func testYAMLEscapingInPassword() throws {
        let node = ProxyNode(
            name: "test-ss",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "pass\\\"word\\\\test"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // Password with quotes and backslashes should be escaped
        #expect(yaml.contains("password: \"pass\\\\\\\"word\\\\\\\\test\""))
    }

    @Test("properly handles IPv6 server addresses")
    func testYAMLEscapingInServer() throws {
        let node = ProxyNode(
            name: "ipv6-proxy",
            kind: .shadowsocks,
            server: "2001:db8::1",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // IPv6 address with colons - colons don't require quoting in value position
        #expect(yaml.contains("server: 2001:db8::1"))
    }

    // MARK: - Custom generation options

    @Test("custom allowLAN option is reflected in config")
    func testCustomAllowLAN() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152,
            allowLAN: true
        )
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("allow-lan: true"))
    }

    @Test("custom logLevel option is reflected in config")
    func testCustomLogLevel() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152,
            logLevel: "debug"
        )
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("log-level: debug"))
    }

    @Test("custom ipv6 option is reflected in config")
    func testCustomIPv6Disabled() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152,
            ipv6: false
        )
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("ipv6: false"))
    }

    @Test("custom apiPort is reflected in external-controller")
    func testCustomAPIPort() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152,
            apiPort: 9091
        )
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("external-controller: 127.0.0.1:9091"))
    }

    // MARK: - Additional proxy types

    @Test("generates TUIC proxy correctly")
    func testGenerateTUICProxy() throws {
        let node = ProxyNode(
            name: "test-tuic",
            kind: .tuic,
            server: "tuic.example.com",
            port: 443,
            password: "tuicpassword",
            sni: "tuic.example.com",
            skipCertVerify: false
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("name: test-tuic"))
        #expect(yaml.contains("type: tuic"))
        #expect(yaml.contains("password: tuicpassword"))
        #expect(yaml.contains("sni: tuic.example.com"))
        #expect(yaml.contains("skip-cert-verify: false"))
    }

    @Test("generates Snell proxy correctly")
    func testGenerateSnellProxy() throws {
        let node = ProxyNode(
            name: "test-snell",
            kind: .snell,
            server: "snell.example.com",
            port: 8388,
            password: "snellpassword",
            snellVersion: 4
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .direct)]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("name: test-snell"))
        #expect(yaml.contains("type: snell"))
        #expect(yaml.contains("password: snellpassword"))
        #expect(yaml.contains("version: 4"))
    }

    // MARK: - Additional rule types

    @Test("generates SRC-IP-CIDR rule correctly")
    func testGenerateSrcIPCIDRRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .srcIPCIDR(cidr: "192.168.0.0/16", policy: .direct),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("SRC-IP-CIDR,192.168.0.0/16,DIRECT"))
    }

    @Test("generates SRC-PORT rule correctly")
    func testGenerateSrcPortRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .srcPort(port: 12345, policy: .reject),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("SRC-PORT,12345,REJECT"))
    }

    @Test("generates DST-PORT rule correctly")
    func testGenerateDstPortRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .dstPort(port: 443, policy: .direct),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("DST-PORT,443,DIRECT"))
    }

    @Test("generates PROCESS-NAME rule correctly")
    func testGenerateProcessNameRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .processName(name: "Safari", policy: .reject),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("PROCESS-NAME,Safari,REJECT"))
    }

    @Test("generates GEOSITE rule correctly")
    func testGenerateGeoSiteRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .geoSite(code: "google", category: "", policy: .direct),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("GEOSITE,google,DIRECT"))
    }

    @Test("generates RULE-SET rule correctly")
    func testGenerateRuleSetRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .ruleSet(name: "my-rule-set", policy: .reject),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("RULE-SET,my-rule-set,REJECT"))
    }

    @Test("generates MATCH rule correctly for matchAll")
    func testGenerateMatchAllRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [.matchAll]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("MATCH,DIRECT"))
    }

    @Test("generates NOT rule correctly")
    func testGenerateNotRule() throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [
                .not(ruleType: "DOMAIN", value: "example.com", policy: .reject),
                .final(policy: .direct)
            ]
        )
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("NOT,DOMAIN,example.com,REJECT"))
    }

    // MARK: - Edge cases

    @Test("empty config generates minimal valid YAML")
    func testEmptyConfig() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(mode: .systemProxy)
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("proxies:"))
        #expect(yaml.contains("rules:"))
        #expect(yaml.contains("MATCH,DIRECT"))
        // No proxy-groups section when empty
        #expect(!yaml.contains("proxy-groups:"))
    }

    @Test("TUN mode apiPort is reflected in external-controller")
    func testTUNModeAPIPort() throws {
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .tun,
            mixedPort: 7890,
            apiPort: 9091
        )
        let yaml = MihomoConfigGenerator.generate(config: config, options: options)
        #expect(yaml.contains("mixed-port: 7890"))
        #expect(yaml.contains("external-controller: 127.0.0.1:9091"))
        #expect(yaml.contains("enable: true"))
        #expect(yaml.contains("auto-route: true"))
        #expect(yaml.contains("strict-route: true"))
    }

    @Test("proxy reference consistency between definition and group reference")
    func testProxyReferenceConsistency() throws {
        let proxy = ProxyNode(
            name: "my-proxy:name",
            kind: .shadowsocks,
            server: "1.2.3.4",
            port: 443,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let group = ProxyGroup(
            id: "AutoSelect",
            kind: .urlTest,
            proxies: ["my-proxy:name"],
            interval: 300,
            tolerance: 100
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [proxy],
            rules: [.final(policy: .proxyNode(name: "AutoSelect"))],
            proxyGroups: [group]
        )
        let options = MihomoConfigGenerator.GenerationOptions(
            mode: .systemProxy,
            mixedPort: 6152
        )

        let yaml = MihomoConfigGenerator.generate(config: config, options: options)

        // Colon does not require quoting in this context
        // Verify both the proxy definition and group reference use consistent escaping
        #expect(yaml.contains("name: my-proxy:name"))
        #expect(yaml.contains("- my-proxy:name"))
    }
}
