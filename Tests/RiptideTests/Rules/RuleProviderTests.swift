import Foundation
import Testing

@testable import Riptide

@Suite("Rule Provider")
struct RuleProviderTests {

    // MARK: - RuleProviderConfig Tests

    @Test("RuleProviderConfig initializes with all fields")
    func ruleProviderConfigFullInit() throws {
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test-provider",
            type: .http,
            url: url,
            path: nil,
            updateInterval: 3600
        )

        #expect(config.name == "test-provider")
        #expect(config.type == .http)
        #expect(config.url == url)
        #expect(config.path == nil)
        #expect(config.updateInterval == 3600)
    }

    @Test("RuleProviderConfig with file type")
    func ruleProviderConfigFileType() throws {
        let config = RuleProviderConfig(
            name: "file-provider",
            type: .file,
            url: nil,
            path: "/etc/rules.yaml",
            updateInterval: nil
        )

        #expect(config.name == "file-provider")
        #expect(config.type == .file)
        #expect(config.url == nil)
        #expect(config.path == "/etc/rules.yaml")
        #expect(config.updateInterval == nil)
    }

    @Test("RuleProviderConfig Equatable")
    func ruleProviderConfigEquatable() throws {
        let url1 = URL(string: "https://example.com/rules1.yaml")!
        let url2 = URL(string: "https://example.com/rules1.yaml")!

        let config1 = RuleProviderConfig(
            name: "test",
            type: .http,
            url: url1,
            path: nil,
            updateInterval: 3600
        )

        let config2 = RuleProviderConfig(
            name: "test",
            type: .http,
            url: url2,
            path: nil,
            updateInterval: 3600
        )

        #expect(config1 == config2)
    }

    // MARK: - RuleProvider Actor Tests

    @Test("RuleProvider initializes with empty rules before start")
    func initializesWithEmptyRules() async throws {
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test",
            type: .http,
            url: url,
            updateInterval: 3600
        )
        let provider = RuleProvider(config: config)

        let rules = await provider.getRules()
        #expect(rules.isEmpty)
    }

    @Test("RuleProvider stops periodic refresh")
    func stopsPeriodicRefresh() async throws {
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test-stop",
            type: .http,
            url: url,
            updateInterval: 1
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        await provider.stop()

        // Calling stop should cancel the update task without error.
        let rules = await provider.getRules()
        #expect(rules.count == 0)
    }

    @Test("RuleProvider parses domain rules from file")
    func parsesDomainRulesFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("rule-provider-test-\(UUID().uuidString).txt")

        let ruleContent = """
        DOMAIN,example.com,Proxy
        DOMAIN-SUFFIX,example.org,Proxy
        DOMAIN-KEYWORD,test,Direct
        """

        try ruleContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(
            name: "file-test",
            type: .file,
            url: nil,
            path: testFile.path,
            updateInterval: nil
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        let rules = await provider.getRules()

        #expect(rules.count == 3)
        #expect(rules.contains { rule in
            if case .domain(let domain, _) = rule {
                return domain == "example.com"
            }
            return false
        })
        #expect(rules.contains { rule in
            if case .domainSuffix(let suffix, _) = rule {
                return suffix == "example.org"
            }
            return false
        })
        #expect(rules.contains { rule in
            if case .domainKeyword(let keyword, _) = rule {
                return keyword == "test"
            }
            return false
        })
    }

    @Test("RuleProvider parses IP-CIDR rules from file")
    func parsesIPCIDRRulesFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("rule-provider-ip-\(UUID().uuidString).txt")

        let ruleContent = """
        IP-CIDR,10.0.0.0/8,Direct
        IP-CIDR6,2001:db8::/32,Proxy
        """

        try ruleContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(
            name: "ip-test",
            type: .file,
            url: nil,
            path: testFile.path,
            updateInterval: nil
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        let rules = await provider.getRules()

        #expect(rules.count == 2)
        #expect(rules.contains { rule in
            if case .ipCIDR(let cidr, _) = rule {
                return cidr == "10.0.0.0/8"
            }
            return false
        })
        #expect(rules.contains { rule in
            if case .ipCIDR6(let cidr, _) = rule {
                return cidr == "2001:db8::/32"
            }
            return false
        })
    }

    @Test("RuleProvider parses GEOIP rules from file")
    func parsesGeoIPRulesFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("rule-provider-geoip-\(UUID().uuidString).txt")

        let ruleContent = """
        GEOIP,CN,Proxy
        GEOIP,US,Direct
        """

        try ruleContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(
            name: "geoip-test",
            type: .file,
            url: nil,
            path: testFile.path,
            updateInterval: nil
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        let rules = await provider.getRules()

        #expect(rules.count == 2)
        #expect(rules.contains { rule in
            if case .geoIP(let countryCode, _) = rule {
                return countryCode == "CN"
            }
            return false
        })
    }

    @Test("RuleProvider parses port rules from file")
    func parsesPortRulesFromFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("rule-provider-port-\(UUID().uuidString).txt")

        let ruleContent = """
        SRC-PORT,80,Direct
        DST-PORT,443,Proxy
        """

        try ruleContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(
            name: "port-test",
            type: .file,
            url: nil,
            path: testFile.path,
            updateInterval: nil
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        let rules = await provider.getRules()

        #expect(rules.count == 2)
        #expect(rules.contains { rule in
            if case .srcPort(let port, _) = rule {
                return port == 80
            }
            return false
        })
        #expect(rules.contains { rule in
            if case .dstPort(let port, _) = rule {
                return port == 443
            }
            return false
        })
    }

    @Test("RuleProvider skips empty lines and comments")
    func skipsEmptyLinesAndComments() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("rule-provider-skip-\(UUID().uuidString).txt")

        let ruleContent = """
        # This is a comment
        DOMAIN,example.com,Proxy

        DOMAIN-SUFFIX,example.org,Proxy
        """

        try ruleContent.write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(
            name: "skip-test",
            type: .file,
            url: nil,
            path: testFile.path,
            updateInterval: nil
        )
        let provider = RuleProvider(config: config)

        await provider.start()
        let rules = await provider.getRules()

        #expect(rules.count == 2)
    }

    @Test("RuleProvider lastUpdateTime returns nil before refresh")
    func lastUpdateTimeNilBeforeRefresh() async throws {
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test",
            type: .http,
            url: url,
            updateInterval: 3600
        )
        let provider = RuleProvider(config: config)

        let lastUpdated = await provider.lastUpdateTime()
        #expect(lastUpdated == nil)
    }
}

// MARK: - RuleProviderManager Tests

@Suite("Rule Provider Manager")
struct RuleProviderManagerTests {

    @Test("RuleProviderManager adds and retrieves provider")
    func addAndRetrieveProvider() async throws {
        let manager = RuleProviderManager()
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test-provider",
            type: .http,
            url: url,
            updateInterval: 3600
        )

        let providerID = await manager.addProvider(config)
        let retrieved = await manager.getProvider(id: providerID)

        #expect(retrieved != nil)
    }

    @Test("RuleProviderManager removes provider")
    func removeProvider() async throws {
        let manager = RuleProviderManager()
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test-provider",
            type: .http,
            url: url,
            updateInterval: 3600
        )

        let providerID = await manager.addProvider(config)
        await manager.removeProvider(id: providerID)
        let retrieved = await manager.getProvider(id: providerID)

        #expect(retrieved == nil)
    }

    @Test("RuleProviderManager getAllProviders returns all providers")
    func getAllProviders() async throws {
        let manager = RuleProviderManager()
        let url1 = URL(string: "https://example.com/rules1.yaml")!

        let config1 = RuleProviderConfig(name: "provider1", type: .http, url: url1, updateInterval: 3600)
        let config2 = RuleProviderConfig(name: "provider2", type: .file, path: "/tmp/rules.yaml", updateInterval: nil)

        _ = await manager.addProvider(config1)
        _ = await manager.addProvider(config2)

        let allProviders = await manager.getAllProviders()
        #expect(allProviders.count == 2)
    }

    @Test("RuleProviderManager getAllRules aggregates rules from all providers")
    func getAllRulesAggregatesFromAllProviders() async throws {
        let manager = RuleProviderManager()
        let tempDir = FileManager.default.temporaryDirectory

        let testFile1 = tempDir.appendingPathComponent("rules-agg-1-\(UUID().uuidString).txt")
        let testFile2 = tempDir.appendingPathComponent("rules-agg-2-\(UUID().uuidString).txt")

        try "DOMAIN,example.com,Proxy".write(to: testFile1, atomically: true, encoding: .utf8)
        try "DOMAIN,test.com,Direct".write(to: testFile2, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile1)
            try? FileManager.default.removeItem(at: testFile2)
        }

        let config1 = RuleProviderConfig(name: "agg1", type: .file, path: testFile1.path, updateInterval: nil)
        let config2 = RuleProviderConfig(name: "agg2", type: .file, path: testFile2.path, updateInterval: nil)

        _ = await manager.addProvider(config1)
        _ = await manager.addProvider(config2)

        await manager.startAll()
        let allRules = await manager.getAllRules()

        #expect(allRules.count == 2)
    }

    @Test("RuleProviderManager stopAll stops all providers")
    func stopAllStopsAllProviders() async throws {
        let manager = RuleProviderManager()
        let url = URL(string: "https://example.com/rules.yaml")!
        let config = RuleProviderConfig(
            name: "test-provider",
            type: .http,
            url: url,
            updateInterval: 1
        )

        _ = await manager.addProvider(config)
        await manager.startAll()
        await manager.stopAll()

        // Should complete without error
    }

    @Test("RuleProviderManager updateProvider triggers refresh")
    func updateProviderTriggersRefresh() async throws {
        let manager = RuleProviderManager()
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("update-test-\(UUID().uuidString).txt")

        try "DOMAIN,example.com,Proxy".write(to: testFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        let config = RuleProviderConfig(name: "update-test", type: .file, path: testFile.path, updateInterval: nil)
        let providerID = await manager.addProvider(config)

        try await manager.updateProvider(id: providerID)

        let provider = await manager.getProvider(id: providerID)
        let rules = await provider?.getRules()
        #expect(rules?.count == 1)
    }
}
