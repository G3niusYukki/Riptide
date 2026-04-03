import Foundation
import Testing

@testable import Riptide

@Suite("Profile store")
struct ProfileStoreTests {
    @Test("importProfile persists and returns profile")
    func importProfilePersists() async throws {
        let fileName = "test-import-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let yaml = sampleYAML()
        let profile = try await store.importProfile(name: "test-import", yaml: yaml)

        #expect(profile.name == "test-import")
        #expect(profile.sourceKind == .local)
        #expect(profile.rawYAML == yaml)

        let all = await store.allProfiles()
        #expect(all.count == 1)
        #expect(all.first?.id == profile.id)
    }

    @Test("importProfile sets newly imported profile as current")
    func importSetsCurrent() async throws {
        let fileName = "test-current-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let p1 = try await store.importProfile(name: "first", yaml: sampleYAML())
        let p2 = try await store.importProfile(name: "second", yaml: sampleYAML())

        let current = await store.currentProfile()
        #expect(current?.id == p2.id)
        #expect(current?.name == "second")
    }

    @Test("selectProfile switches the active profile")
    func selectProfile() async throws {
        let fileName = "test-select-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let p1 = try await store.importProfile(name: "first", yaml: sampleYAML())
        _ = try await store.importProfile(name: "second", yaml: sampleYAML())

        try await store.selectProfile(id: p1.id)
        let current = await store.currentProfile()
        #expect(current?.id == p1.id)
    }

    @Test("deleteProfile removes profile and clears current if needed")
    func deleteProfile() async throws {
        let fileName = "test-delete-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let p1 = try await store.importProfile(name: "first", yaml: sampleYAML())
        _ = try await store.importProfile(name: "second", yaml: sampleYAML())

        try await store.deleteProfile(id: p1.id)
        let remaining = await store.allProfiles()
        #expect(remaining.count == 1)
        #expect(await store.currentProfile()?.id != p1.id)
    }

    @Test("addSubscriptionProfile stores subscription URL and refresh time")
    func subscriptionProfile() async throws {
        let fileName = "test-sub-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let url = URL(string: "https://example.com/sub")!
        let profile = try await store.addSubscriptionProfile(
            name: "my-sub",
            yaml: sampleYAML(),
            subscriptionURL: url
        )

        #expect(profile.sourceKind == .subscription)
        #expect(profile.subscriptionURL == url)
        #expect(profile.lastRefresh != nil)
    }

    private func sampleYAML() -> String {
        """
        mode: rule
        proxies:
          - name: "test-proxy"
            type: socks5
            server: "1.2.3.4"
            port: 1080
        rules:
          - MATCH,test-proxy
        """
    }
}

@Suite("Profile workflow")
struct ProfileWorkflowTests {
    @Test("refreshProfile returns updated profile with new refresh timestamp")
    func refreshProfileUpdatesTimestamp() async throws {
        let fileName = "test-refresh-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let url = URL(string: "https://example.com/sub")!
        let original = try await store.addSubscriptionProfile(
            name: "sub",
            yaml: sampleYAML(),
            subscriptionURL: url
        )

        #expect(original.sourceKind == .subscription)
        #expect(original.subscriptionURL == url)

        let byID = await store.profile(id: original.id)
        #expect(byID?.name == "sub")

        let current = await store.currentProfile()
        #expect(current == nil)
    }

    @Test("selecting a subscription profile then importing a local one switches correctly")
    func switchBetweenSubscriptionAndLocal() async throws {
        let fileName = "test-switch-\(UUID().uuidString).json"
        let store = try ProfileStore(fileName: fileName)
        let subURL = URL(string: "https://example.com/sub")!
        let subProfile = try await store.addSubscriptionProfile(
            name: "my-sub",
            yaml: sampleYAML(),
            subscriptionURL: subURL
        )

        try await store.selectProfile(id: subProfile.id)
        let localProfile = try await store.importProfile(name: "local", yaml: sampleYAML())

        let current = await store.currentProfile()
        #expect(current?.id == localProfile.id)

        try await store.selectProfile(id: subProfile.id)
        let switched = await store.currentProfile()
        #expect(switched?.id == subProfile.id)
    }

    private func sampleYAML() -> String {
        """
        mode: rule
        proxies:
          - name: "test-proxy"
            type: socks5
            server: "1.2.3.4"
            port: 1080
        rules:
          - MATCH,test-proxy
        """
    }
}
