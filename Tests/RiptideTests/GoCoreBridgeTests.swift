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

@Suite("GoCoreBridge Tests", .serialized)
struct GoCoreBridgeTests {
    
    @Test("Test start, stop and event callback")
    func testStartStopAndCallback() async throws {
        guard isGitHubActionsRuntime == false else {
            return
        }

        try await withExclusiveGoCore {
            let bridge = GoCoreBridge.shared
            let latch = EventLatch()

            try await bridge.start(configJSON: "{}") { type, data in
                if type == "status" && data == "running" {
                    Task {
                        await latch.fulfill()
                    }
                }
            }

            let didReceiveRunningEvent = await latch.wait(timeoutNanoseconds: 2_000_000_000)
            #expect(didReceiveRunningEvent)

            // Verify traffic getters
            let traffic = await bridge.getTraffic()
            #expect(traffic.up == 102456)
            #expect(traffic.down == 509210)

            // Stop bridge
            await bridge.stop()
        }
    }
    
    @Test("Test switchProxy")
    func testSwitchProxy() async throws {
        try await withExclusiveGoCore {
            let bridge = GoCoreBridge.shared
            try await bridge.switchProxy(group: "GLOBAL", name: "Direct")
        }
    }
}
