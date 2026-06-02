import Foundation
import Testing
import Yams

@testable import Riptide

@Suite("Override merger")
struct OverrideMergerTests {

    @Test("merge_withEmptyOverride_returnsBase")
    func merge_withEmptyOverride_returnsBase() throws {
        let baseYAML = """
        mode: rule
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        rules:
          - MATCH,ss-1
        """

        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: "")

        // When override is empty, parsed result should match base. Yams output
        // formatting may differ slightly, so we round-trip through Yams load
        // before comparison.
        let baseMap = try Yams.load(yaml: baseYAML) as? [String: Any] ?? [:]
        let mergedMap = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        #expect(mergedMap as? NSObject == baseMap as? NSObject)
    }

    @Test("merge_appendsNewProxyToProxiesList")
    func merge_appendsNewProxyToProxiesList() throws {
        let baseYAML = """
        mode: rule
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        rules:
          - MATCH,ss-1
        """
        let overrideYAML = """
        proxies:
          - name: "ss-2"
            type: ss
            server: "5.6.7.8"
            port: 443
            cipher: "chacha20-ietf-poly1305"
            password: "pw"
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let proxies = map["proxies"] as? [[String: Any]] ?? []
        let names = proxies.compactMap { $0["name"] as? String }
        #expect(names == ["ss-1", "ss-2"])
    }

    @Test("merge_withMetaReplace_trueReplacesProxyByName")
    func merge_withMetaReplace_trueReplacesProxyByName() throws {
        let baseYAML = """
        mode: rule
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        """
        let overrideYAML = """
        meta:
          replace: true
        proxies:
          - name: "ss-1"
            type: ss
            server: "9.9.9.9"
            port: 8443
            cipher: "aes-256-gcm"
            password: "newsecret"
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let proxies = map["proxies"] as? [[String: Any]] ?? []
        #expect(proxies.count == 1)
        #expect(proxies[0]["server"] as? String == "9.9.9.9")
        #expect(proxies[0]["port"] as? Int == 8443)
        #expect(proxies[0]["password"] as? String == "newsecret")
    }

    @Test("merge_withoutMetaReplace_appendsEvenWithDuplicateName")
    func merge_withoutMetaReplace_appendsEvenWithDuplicateName() throws {
        let baseYAML = """
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        """
        let overrideYAML = """
        proxies:
          - name: "ss-1"
            type: ss
            server: "9.9.9.9"
            port: 8443
            cipher: "aes-256-gcm"
            password: "newsecret"
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let proxies = map["proxies"] as? [[String: Any]] ?? []
        #expect(proxies.count == 2, "Without meta.replace, duplicate names should be appended, not deduplicated")
    }

    @Test("merge_removedRemovesProxyByName")
    func merge_removedRemovesProxyByName() throws {
        let baseYAML = """
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
          - name: "ss-2"
            type: ss
            server: "5.6.7.8"
            port: 443
            cipher: "chacha20-ietf-poly1305"
            password: "pw"
        """
        let overrideYAML = """
        removed:
          - "ss-2"
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let proxies = map["proxies"] as? [[String: Any]] ?? []
        let names = proxies.compactMap { $0["name"] as? String }
        #expect(names == ["ss-1"])
    }

    @Test("merge_removedItemNotFound_throwsRemovedNotFound")
    func merge_removedItemNotFound_throwsRemovedNotFound() {
        let baseYAML = """
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        """
        let overrideYAML = """
        removed:
          - "nonexistent-proxy"
        """
        #expect(throws: OverrideApplyError.removedNotFound(name: "nonexistent-proxy")) {
            _ = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        }
    }

    @Test("merge_dnsMapSectionDeepMergesScalarsAndNestedMaps")
    func merge_dnsMapSectionDeepMergesScalarsAndNestedMaps() throws {
        let baseYAML = """
        dns:
          enable: true
          ipv6: false
          enhanced-mode: fake-ip
          nameserver:
            - 8.8.8.8
            - 1.1.1.1
        """
        let overrideYAML = """
        dns:
          ipv6: true
          nameserver:
            - 9.9.9.9
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let dns = map["dns"] as? [String: Any] ?? [:]
        #expect(dns["enable"] as? Bool == true, "Unspecified keys in override should be preserved from base")
        #expect(dns["ipv6"] as? Bool == true, "Scalar override should win")
        #expect(dns["enhanced-mode"] as? String == "fake-ip", "Unspecified nested key preserved")
        let nameservers = dns["nameserver"] as? [String] ?? []
        #expect(nameservers == ["8.8.8.8", "1.1.1.1", "9.9.9.9"], "Lists in map sections are appended, not replaced")
    }

    @Test("merge_modeScalarOverrideWins")
    func merge_modeScalarOverrideWins() throws {
        let baseYAML = """
        mode: rule
        proxies: []
        """
        let overrideYAML = """
        mode: global
        """
        let merged = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        #expect(map["mode"] as? String == "global")
    }

    @Test("merge_typeMismatchOnDNSSection_throwsTypeMismatch")
    func merge_typeMismatchOnDNSSection_throwsTypeMismatch() {
        let baseYAML = """
        dns: 8.8.8.8
        """
        let overrideYAML = """
        dns:
          enable: true
        """
        #expect(throws: OverrideApplyError.self) {
            _ = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        }
    }

    @Test("merge_invalidOverrideYAML_throwsInvalidYAML")
    func merge_invalidOverrideYAML_throwsInvalidYAML() {
        let baseYAML = """
        mode: rule
        """
        let overrideYAML = "this is: not: valid: yaml: at: all:"
        #expect(throws: OverrideApplyError.self) {
            _ = try OverrideMerger.merge(baseYAML: baseYAML, overrideYAML: overrideYAML)
        }
    }

    @Test("composeYAML_chainsMultipleOverridesInOrder")
    func composeYAML_chainsMultipleOverridesInOrder() throws {
        let baseYAML = """
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        """
        let o1 = Override(name: "add-node", rawYAML: """
        proxies:
          - name: "ss-2"
            type: ss
            server: "5.6.7.8"
            port: 443
            cipher: "chacha20-ietf-poly1305"
            password: "pw"
        """)
        let o2 = Override(name: "remove-node", rawYAML: """
        removed:
          - "ss-1"
        """)
        let merged = try composeYAML(baseYAML: baseYAML, overrides: [o1, o2])
        let map = try Yams.load(yaml: merged) as? [String: Any] ?? [:]
        let proxies = map["proxies"] as? [[String: Any]] ?? []
        let names = proxies.compactMap { $0["name"] as? String }
        #expect(names == ["ss-2"], "Compose applies overrides in order; ss-1 added by o1's append then removed by o2")
    }
}
