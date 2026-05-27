import Foundation
@testable import Riptide

let isGitHubActionsRuntime = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"

private actor GoCoreTestLock {
    static let shared = GoCoreTestLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

func withExclusiveGoCore<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
    await GoCoreTestLock.shared.acquire()
    await GoCoreBridge.shared.stop()

    do {
        let result = try await operation()
        await GoCoreBridge.shared.stop()
        await GoCoreTestLock.shared.release()
        return result
    } catch {
        await GoCoreBridge.shared.stop()
        await GoCoreTestLock.shared.release()
        throw error
    }
}
