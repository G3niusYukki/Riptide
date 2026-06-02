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
}
