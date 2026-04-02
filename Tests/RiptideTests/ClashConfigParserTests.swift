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

        let config = try ClashConfigParser.parse(yaml: yaml)

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
}
