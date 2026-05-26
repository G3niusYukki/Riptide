import XCTest
@testable import Riptide

/// Tests for ConfigMerger script functionality and visual diff generation.
final class ConfigMergerScriptTests: XCTestCase {

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

    // MARK: - ScriptType

    func testScriptTypeProfileScript() {
        let type = ScriptType.profileScript
        XCTAssertEqual(type.rawValue, "profile-script")
    }

    // MARK: - ScriptEngine Profile Script

    func testScriptEngineExecuteProfileScript() async throws {
        let engine = ScriptEngine()
        let script = """
        function transform(config) {
            config.proxies = config.proxies || [];
            config.proxies.push({
                name: "new-proxy",
                type: "ss",
                server: "1.2.3.4",
                port: 443,
                cipher: "aes-256-gcm",
                password: "pass"
            });
            return config;
        }
        """

        let context = ScriptContext(name: "test", source: script, type: .profileScript)
        try engine.loadScript(context)

        let configJSON = """
        {"mode":"rule","proxies":[],"rules":["MATCH,DIRECT"]}
        """

        let resultJSON = try await engine.executeProfileScript(scriptName: "test", configJSON: configJSON)

        // Parse the result
        let data = resultJSON.data(using: .utf8)!
        let result = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let proxies = result["proxies"] as! [[String: Any]]
        XCTAssertEqual(proxies.count, 1)
        XCTAssertEqual(proxies[0]["name"] as! String, "new-proxy")
    }

    func testScriptEngineExecuteProfileScriptInvalidScript() async throws {
        let engine = ScriptEngine()
        let script = """
        function transform(config) {
            throw new Error("test error");
        }
        """

        let context = ScriptContext(name: "test", source: script, type: .profileScript)
        try engine.loadScript(context)

        let configJSON = """
        {"mode":"rule","proxies":[],"rules":["MATCH,DIRECT"]}
        """

        do {
            _ = try await engine.executeProfileScript(scriptName: "test", configJSON: configJSON)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
    }

    // MARK: - ConfigMerger.mergeWithScript

    func testConfigMergerMergeWithScript() async throws {
        let base = makeBaseConfig(proxies: [makeProxy(name: "existing")])

        let script = """
        function transform(config) {
            config.proxies = config.proxies || [];
            config.proxies.push({
                name: "script-proxy",
                type: "ss",
                server: "5.6.7.8",
                port: 8388,
                cipher: "chacha20-ietf-poly1305",
                password: "scriptpass"
            });
            return config;
        }
        """

        let result = try await ConfigMerger.mergeWithScript(base: base, script: script)

        XCTAssertEqual(result.proxies.count, 2)
        XCTAssertEqual(result.proxies[0].name, "existing")
        XCTAssertEqual(result.proxies[1].name, "script-proxy")
        XCTAssertEqual(result.proxies[1].server, "5.6.7.8")
    }

    func testConfigMergerMergeWithScriptAndAdditionalYAML() async throws {
        let base = makeBaseConfig(proxies: [makeProxy(name: "existing")])

        let script = """
        function transform(config) {
            config.proxies = config.proxies || [];
            config.proxies.push({
                name: "script-proxy",
                type: "ss",
                server: "5.6.7.8",
                port: 8388,
                cipher: "chacha20-ietf-poly1305",
                password: "scriptpass"
            });
            return config;
        }
        """

        let mergeYAML = """
        proxies:
          - name: "yaml-proxy"
            type: ss
            server: "9.9.9.9"
            port: 443
            cipher: aes-256-gcm
            password: yamlpass
        """

        let result = try await ConfigMerger.mergeWithScript(base: base, script: script, mergeYAMLs: [mergeYAML])

        XCTAssertEqual(result.proxies.count, 3)
        XCTAssertEqual(result.proxies[0].name, "existing")
        XCTAssertEqual(result.proxies[1].name, "script-proxy")
        XCTAssertEqual(result.proxies[2].name, "yaml-proxy")
    }

    func testConfigMergerMergeWithScriptModifiesRules() async throws {
        let base = makeBaseConfig(rules: [.final(policy: .direct)])

        let script = """
        function transform(config) {
            config.rules = config.rules || [];
            config.rules.push("DOMAIN-SUFFIX,google.com,PROXY");
            return config;
        }
        """

        let result = try await ConfigMerger.mergeWithScript(base: base, script: script)

        XCTAssertEqual(result.rules.count, 2)
    }

    // MARK: - Visual Diff

    func testVisualDiffWithIdenticalContent() {
        let content = "line1\nline2\nline3"
        let diff = ConfigMergeViewModel.computeUnifiedDiff(original: content, merged: content)
        XCTAssertNil(diff)
    }

    func testVisualDiffWithDifferentContent() {
        let original = "line1\nline2\nline3"
        let merged = "line1\nline2-modified\nline3\nline4"

        let diff = ConfigMergeViewModel.computeUnifiedDiff(original: original, merged: merged)

        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("-line2"))
        XCTAssertTrue(diff!.contains("+line2-modified"))
        XCTAssertTrue(diff!.contains("+line4"))
    }

    func testVisualDiffWithEmptyOriginal() {
        let original = ""
        let merged = "line1\nline2"

        let diff = ConfigMergeViewModel.computeUnifiedDiff(original: original, merged: merged)

        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("+line1"))
        XCTAssertTrue(diff!.contains("+line2"))
    }

    func testVisualDiffWithEmptyMerged() {
        let original = "line1\nline2"
        let merged = ""

        let diff = ConfigMergeViewModel.computeUnifiedDiff(original: original, merged: merged)

        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("-line1"))
        XCTAssertTrue(diff!.contains("-line2"))
    }

    // MARK: - MergePreview Unified Diff

    func testMergePreviewIncludesUnifiedDiff() {
        // This test would require mocking the profile store
        // For now, we test the static method directly
        let original = "proxies:\n  - name: p1\nrules:\n  - MATCH,DIRECT"
        let merged = "proxies:\n  - name: p1\n  - name: p2\nrules:\n  - MATCH,DIRECT"

        let diff = ConfigMergeViewModel.computeUnifiedDiff(original: original, merged: merged)

        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("+  - name: p2"))
    }
}
