import Foundation
import Testing

@testable import Riptide

@Suite("App group state store")
struct AppGroupStateStoreTests {
    @Test("store round-trips runtime snapshots and recent errors")
    func roundTripsRuntimeState() async throws {
        let store = try AppGroupStateStore(appGroupIdentifier: "nonexistent-group")

        let status = TunnelRuntimeStatus(bytesUp: 1024, bytesDown: 2048, activeConnections: 5)
        let error = RuntimeErrorSnapshot(code: "E_TEST", message: "test error")
        let state = RuntimeSharedState(
            status: status,
            mode: .tun,
            recentErrors: [error]
        )

        try await store.write(state)
        let read = try await store.read()

        #expect(read != nil)
        #expect(read?.status.bytesUp == 1024)
        #expect(read?.status.bytesDown == 2048)
        #expect(read?.mode == .tun)
        #expect(read?.recentErrors.count == 1)
        #expect(read?.recentErrors.first?.code == "E_TEST")
    }

    @Test("store update modifies specific fields")
    func partialUpdate() async throws {
        let store = try AppGroupStateStore(appGroupIdentifier: "nonexistent-group")

        let initial = RuntimeSharedState()
        try await store.write(initial)

        let updated = TunnelRuntimeStatus(bytesUp: 100, bytesDown: 200, activeConnections: 3)
        try await store.update(status: updated)

        let read = try await store.read()
        #expect(read?.status.bytesUp == 100)
        #expect(read?.status.bytesDown == 200)
        #expect(read?.mode == .systemProxy) // unchanged
    }

    @Test("runtime shared state is equatable and codable")
    func stateIsEquatableAndCodable() throws {
        let status = TunnelRuntimeStatus(bytesUp: 1, bytesDown: 2, activeConnections: 3)
        let error = RuntimeErrorSnapshot(code: "E_X", message: "y")
        let state = RuntimeSharedState(
            status: status,
            mode: .tun,
            recentErrors: [error]
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeSharedState.self, from: encoded)
        #expect(decoded == state)
        #expect(decoded.status.bytesUp == 1)
        #expect(decoded.mode == .tun)
    }
}
