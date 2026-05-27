import Foundation
import Testing
@testable import Riptide

private actor EventLatch {
    private var isFulfilled = false
    private var continuation: CheckedContinuation<Void, Never>?
    
    func fulfill() {
        if !isFulfilled {
            isFulfilled = true
            continuation?.resume()
            continuation = nil
        }
    }
    
    func wait() async {
        if isFulfilled { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelWait() {
        continuation?.resume()
        continuation = nil
    }

    func wait(timeoutNanoseconds: UInt64) async -> Bool {
        if isFulfilled { return true }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.wait()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            if !result {
                self.cancelWait()
            }
            group.cancelAll()
            return result
        }
    }
}

@Suite("GoCoreTunnelRuntime Tests", .serialized)
struct GoCoreTunnelRuntimeTests {

    @Test("Test lifecycle of GoCoreTunnelRuntime")
    func testRuntimeLifecycle() async throws {
        try await withExclusiveGoCore {
            let runtime = GoCoreTunnelRuntime()

            #expect(await runtime.isRunning == false)
            #expect(await runtime.currentMode == nil)
            #expect(await runtime.currentProfile == nil)

            // Mock profile and mode
            let dummyConfig = RiptideConfig(mode: .direct, proxies: [], rules: [])
            let dummyProfile = TunnelProfile(name: "TestProfile", config: dummyConfig)

            let latch = EventLatch()
            await runtime.setEventHandler { event in
                if case .stateChanged(let state) = event, state == .running {
                    Task {
                        await latch.fulfill()
                    }
                }
            }

            try await runtime.setup()
            try await runtime.start(mode: .systemProxy, profile: dummyProfile)

            #expect(await runtime.isRunning == true)
            #expect(await runtime.currentMode == .systemProxy)

            let didReceiveRunningEvent = await latch.wait(timeoutNanoseconds: 2_000_000_000)
            #expect(didReceiveRunningEvent)

            let traffic = try await runtime.getTraffic()
            #expect(traffic.up == 102456)
            #expect(traffic.down == 509210)

            let status = try await runtime.getProxyStatus()
            #expect(status.count == 2)

            try await runtime.stop()

            #expect(await runtime.isRunning == false)
            #expect(await runtime.currentMode == nil)
        }
    }
}
