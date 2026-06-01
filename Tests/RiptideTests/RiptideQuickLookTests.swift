import Foundation
import XCTest
@testable import RiptideQuickLook

final class YAMLPreviewStatsTests: XCTestCase {
    func testEmptyStatsHaveZeroCounts() {
        let stats = YAMLPreviewStats.empty
        XCTAssertEqual(stats.proxyCount, 0)
        XCTAssertEqual(stats.groupCount, 0)
        XCTAssertEqual(stats.ruleCount, 0)
        XCTAssertTrue(stats.protocolBreakdown.isEmpty)
        XCTAssertTrue(stats.firstNodes.isEmpty)
        XCTAssertNil(stats.sanitizedSubscriptionURL)
        XCTAssertNil(stats.updatedAt)
        XCTAssertFalse(stats.isSubscription)
    }

    func testStatsAreEquatable() {
        let a = YAMLPreviewStats(
            proxyCount: 3,
            groupCount: 2,
            ruleCount: 5,
            protocolBreakdown: ["ss": 2, "vmess": 1],
            firstNodes: [YAMLPreviewNode(name: "n1", type: "ss", server: "1.1.1.1")],
            sanitizedSubscriptionURL: "https://example.com/sub",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isSubscription: true
        )
        let b = YAMLPreviewStats(
            proxyCount: 3,
            groupCount: 2,
            ruleCount: 5,
            protocolBreakdown: ["ss": 2, "vmess": 1],
            firstNodes: [YAMLPreviewNode(name: "n1", type: "ss", server: "1.1.1.1")],
            sanitizedSubscriptionURL: "https://example.com/sub",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isSubscription: true
        )
        XCTAssertEqual(a, b)
    }
}

final class YAMLPreviewParserTests: XCTestCase {
    func testParseEmptyYAML() {
        let stats = YAMLPreviewParser.parse(yaml: "")
        XCTAssertEqual(stats.proxyCount, 0)
        XCTAssertEqual(stats.groupCount, 0)
        XCTAssertEqual(stats.ruleCount, 0)
    }

    func testParseCountsProxies() {
        let yaml = """
        proxies:
          - {name: "p1", type: ss, server: 1.1.1.1, port: 8388}
          - {name: "p2", type: ss, server: 1.1.1.2, port: 8388}
          - {name: "p3", type: vmess, server: 1.1.1.3, port: 443}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.proxyCount, 3)
    }

    func testParseCountsProxyGroups() {
        let yaml = """
        proxy-groups:
          - name: "Auto"
            type: url-test
            proxies: [p1, p2]
          - name: "Manual"
            type: select
            proxies: [p1, p2]
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.groupCount, 2)
    }

    func testParseCountsRules() {
        let yaml = """
        rules:
          - DOMAIN,example.com,DIRECT
          - DOMAIN-SUFFIX,google.com,Proxy
          - IP-CIDR,10.0.0.0/8,DIRECT
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.ruleCount, 3)
    }

    func testProtocolBreakdownTalliesTypes() {
        let yaml = """
        proxies:
          - {name: "p1", type: ss, server: 1.1.1.1, port: 8388}
          - {name: "p2", type: ss, server: 1.1.1.2, port: 8388}
          - {name: "p3", type: vmess, server: 1.1.1.3, port: 443}
          - {name: "p4", type: trojan, server: 1.1.1.4, port: 443}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.protocolBreakdown["ss"], 2)
        XCTAssertEqual(stats.protocolBreakdown["vmess"], 1)
        XCTAssertEqual(stats.protocolBreakdown["trojan"], 1)
    }

    func testProtocolBreakdownMissingTypesAreSkipped() {
        let yaml = """
        proxies:
          - {name: "p1", server: 1.1.1.1, port: 8388}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertTrue(stats.protocolBreakdown.isEmpty)
    }

    func testFirstNodesCaptured() {
        let yaml = """
        proxies:
          - {name: "Hong Kong - 01", type: ss, server: hk1.example.com, port: 8388}
          - {name: "Tokyo - 02", type: vmess, server: tk2.example.com, port: 443}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.firstNodes.count, 2)
        XCTAssertEqual(stats.firstNodes[0].name, "Hong Kong - 01")
        XCTAssertEqual(stats.firstNodes[0].rawType, "ss")
        XCTAssertEqual(stats.firstNodes[0].server, "hk1.example.com")
        XCTAssertEqual(stats.firstNodes[1].name, "Tokyo - 02")
        XCTAssertEqual(stats.firstNodes[1].rawType, "vmess")
    }

    func testFirstNodesTruncatedToLimit() {
        let yamlEntries = (1...20).map { idx in
            "  - {name: \"p\(idx)\", type: ss, server: 1.1.1.\(idx), port: 8388}"
        }.joined(separator: "\n")
        let yaml = "proxies:\n\(yamlEntries)\n"
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertEqual(stats.firstNodes.count, YAMLPreviewParser.previewNodeLimit)
        XCTAssertEqual(stats.firstNodes.first?.name, "p1")
    }

    func testIsSubscriptionDetectedByURLMarker() {
        let yaml = """
        # subscription: https://provider.example.com/api/v1?token=secret
        proxies:
          - {name: "p1", type: ss, server: 1.1.1.1, port: 8388}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertTrue(stats.isSubscription)
        XCTAssertNotNil(stats.sanitizedSubscriptionURL)
    }

    func testIsSubscriptionFalseForLocalFiles() {
        let yaml = """
        proxies:
          - {name: "p1", type: ss, server: 1.1.1.1, port: 8388}
        """
        let stats = YAMLPreviewParser.parse(yaml: yaml)
        XCTAssertFalse(stats.isSubscription)
        XCTAssertNil(stats.sanitizedSubscriptionURL)
    }

    func testInvalidYAMLReturnsEmpty() {
        let stats = YAMLPreviewParser.parse(yaml: "this: is: not: valid: yaml: [")
        XCTAssertEqual(stats.proxyCount, 0)
        XCTAssertEqual(stats.groupCount, 0)
        XCTAssertEqual(stats.ruleCount, 0)
    }

    func testNonMappingRootReturnsEmpty() {
        let stats = YAMLPreviewParser.parse(yaml: "- 1\n- 2\n")
        XCTAssertEqual(stats.proxyCount, 0)
        XCTAssertEqual(stats.groupCount, 0)
        XCTAssertEqual(stats.ruleCount, 0)
    }

    func testParseFileURLReadsContents() throws {
        let yaml = """
        proxies:
          - {name: "p1", type: ss, server: 1.1.1.1, port: 8388}
        rules:
          - DOMAIN,example.com,DIRECT
        """
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-quicklook-\(UUID().uuidString).yaml")
        try yaml.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }

        let stats = try YAMLPreviewParser.parse(fileURL: temp)
        XCTAssertEqual(stats.proxyCount, 1)
        XCTAssertEqual(stats.ruleCount, 1)
        XCTAssertNotNil(stats.updatedAt)
    }

    func testParseMissingFileThrows() {
        let missing = URL(fileURLWithPath: "/tmp/riptide-does-not-exist-\(UUID().uuidString).yaml")
        XCTAssertThrowsError(try YAMLPreviewParser.parse(fileURL: missing))
    }
}

final class SubscriptionURLSanitizerTests: XCTestCase {
    func testRedactsUserInfo() {
        let sanitized = YAMLPreviewParser.sanitizeSubscriptionURL("https://user:pass@provider.example.com/sub?token=secret")
        XCTAssertFalse(sanitized.contains("user"))
        XCTAssertFalse(sanitized.contains("pass"))
        XCTAssertFalse(sanitized.contains("secret"))
        XCTAssertTrue(sanitized.contains("provider.example.com"))
    }

    func testRedactsQueryParametersWithSensitiveNames() {
        let sanitized = YAMLPreviewParser.sanitizeSubscriptionURL("https://provider.example.com/sub?token=abc&password=xyz&foo=bar")
        XCTAssertFalse(sanitized.contains("abc"))
        XCTAssertFalse(sanitized.contains("xyz"))
        XCTAssertTrue(sanitized.contains("foo=bar"))
    }

    func testNonSensitiveURLPassesThrough() {
        let original = "https://provider.example.com/sub"
        let sanitized = YAMLPreviewParser.sanitizeSubscriptionURL(original)
        XCTAssertEqual(sanitized, original)
    }

    func testInvalidURLReturnsOriginal() {
        // An empty string cannot be parsed as a URL.
        let original = ""
        let sanitized = YAMLPreviewParser.sanitizeSubscriptionURL(original)
        XCTAssertEqual(sanitized, original)
    }
}

final class PreviewNodeDescriptionTests: XCTestCase {
    func testDisplayTypeFromRawType() {
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "ss"), "Shadowsocks")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "vmess"), "VMess")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "vless"), "VLESS")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "trojan"), "Trojan")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "hysteria2"), "Hysteria2")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "snell"), "Snell")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "tuic"), "TUIC")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "wireguard"), "WireGuard")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "http"), "HTTP")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "socks5"), "SOCKS5")
        XCTAssertEqual(YAMLPreviewParser.displayType(forRawType: "ssm"), "Shadowsocks")
    }
}
