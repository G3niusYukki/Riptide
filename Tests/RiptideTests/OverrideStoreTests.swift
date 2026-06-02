import Foundation
import Testing

@testable import Riptide

@Suite("Override store")
struct OverrideStoreTests {

    @Test("create persists YAML and sidecar")
    func createPersistsYAMLAndSidecar() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-overrides-\(suffix)")
        let yaml = """
        meta:
          replace: true
        proxies:
          - name: "ss-1"
            type: ss
            server: "1.2.3.4"
            port: 443
            cipher: "aes-256-gcm"
            password: "secret"
        """
        let ovr = try await store.create(name: "add-node", rawYAML: yaml)

        #expect(ovr.name == "add-node")
        #expect(ovr.rawYAML == yaml)
        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all.first?.id == ovr.id)
    }
}
