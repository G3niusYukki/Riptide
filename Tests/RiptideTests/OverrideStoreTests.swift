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

    @Test("get returns the override by id")
    func getReturnsOverride() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-get-\(suffix)")
        let created = try await store.create(name: "test", rawYAML: "mode: rule\n")

        let fetched = try await store.get(id: created.id)
        #expect(fetched.id == created.id)
        #expect(fetched.name == "test")
    }

    @Test("get missing id throws notFound")
    func getMissingIDThrowsNotFound() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-get-missing-\(suffix)")
        await #expect(throws: OverrideStoreError.self) {
            _ = try await store.get(id: UUID())
        }
    }

    @Test("update replaces YAML and bumps updatedAt")
    func updateReplacesYAMLAndBumpsUpdatedAt() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-update-\(suffix)")
        let created = try await store.create(name: "a", rawYAML: "mode: rule\n")
        let originalUpdatedAt = created.updatedAt

        // Sleep briefly so updatedAt can advance
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let updated = try await store.update(id: created.id, name: nil, rawYAML: "mode: global\n")
        #expect(updated.rawYAML == "mode: global\n")
        #expect(updated.name == "a", "name not passed should be preserved")
        #expect(updated.updatedAt > originalUpdatedAt)
    }

    @Test("update only name does not touch YAML file content")
    func updateOnlyNameDoesNotTouchYAML() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-update-name-\(suffix)")
        let originalYAML = "mode: rule\n"
        let created = try await store.create(name: "old-name", rawYAML: originalYAML)

        let updated = try await store.update(id: created.id, name: "new-name", rawYAML: nil)
        #expect(updated.name == "new-name")
        #expect(updated.rawYAML == originalYAML, "rawYAML should be unchanged when nil is passed")
    }

    @Test("delete removes both files and sidecar entry")
    func deleteRemovesBothFiles() async throws {
        let suffix = UUID().uuidString
        let store = try OverrideStore(directoryName: "test-delete-\(suffix)")
        let created = try await store.create(name: "a", rawYAML: "mode: rule\n")

        try await store.delete(id: created.id)
        let all = try await store.list()
        #expect(all.isEmpty)
    }

    @Test("init loads existing overrides from sidecar")
    func initLoadsExisting() async throws {
        let suffix = UUID().uuidString
        let dir = "test-reload-\(suffix)"

        let store1 = try OverrideStore(directoryName: dir)
        _ = try await store1.create(name: "a", rawYAML: "mode: rule\n")
        _ = try await store1.create(name: "b", rawYAML: "mode: global\n")

        let store2 = try OverrideStore(directoryName: dir)
        let reloaded = try await store2.list()
        #expect(reloaded.count == 2)
        let names = reloaded.map { $0.name }.sorted()
        #expect(names == ["a", "b"])
    }
}
