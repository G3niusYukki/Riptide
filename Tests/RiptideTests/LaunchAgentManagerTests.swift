import Foundation
import Testing
@testable import Riptide

// MARK: - LaunchAgentManager Tests

@Suite("LaunchAgentManager Tests")
struct LaunchAgentManagerTests {

    // MARK: - Test Helpers

    /// Test-only process recorder. Replaces the real `Process` invocation.
    final class ProcessRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [RecordedCall] = []
        private var _nextOutput: LaunchAgentManager.ProcessOutput

        struct RecordedCall: Equatable, Sendable {
            let executable: String
            let arguments: [String]
        }

        init(nextOutput: LaunchAgentManager.ProcessOutput = .init(terminationStatus: 0)) {
            self._nextOutput = nextOutput
        }

        var calls: [RecordedCall] {
            lock.lock()
            defer { lock.unlock() }
            return _calls
        }

        func reset() {
            lock.lock()
            _calls.removeAll()
            lock.unlock()
        }

        var nextOutput: LaunchAgentManager.ProcessOutput {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _nextOutput
            }
            set {
                lock.lock()
                _nextOutput = newValue
                lock.unlock()
            }
        }

        func record(executable: String, arguments: [String]) {
            lock.lock()
            _calls.append(RecordedCall(executable: executable, arguments: arguments))
            lock.unlock()
        }

        /// Builds a `LaunchAgentManager.ProcessRunner` closure that records into this recorder.
        var runner: LaunchAgentManager.ProcessRunner {
            return { [weak self] executable, arguments in
                guard let self else {
                    throw RiptideError.launchAgentRegistrationFailed("Recorder deallocated")
                }
                self.record(executable: executable, arguments: arguments)
                return self.nextOutput
            }
        }
    }

    /// Creates a temporary LaunchAgents directory and returns its URL + a teardown closure.
    static func makeTempLaunchAgentsDirectory() throws -> (URL, () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-launchagent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (tempDir, {
            try? FileManager.default.removeItem(at: tempDir)
        })
    }

    /// Builds a manager wired to a temp directory and the supplied process recorder.
    static func makeManager(
        directory: URL,
        recorder: ProcessRecorder,
        plistLabel: String = "com.riptide.test",
        executablePath: String = "/tmp/fake-riptide"
    ) -> LaunchAgentManager {
        LaunchAgentManager(
            fileManager: .default,
            plistLabel: plistLabel,
            executablePath: executablePath,
            launchAgentsDirectory: directory,
            launchctlPath: "/bin/launchctl",
            processRunner: recorder.runner
        )
    }

    // MARK: - isRegistered

    @Test("isRegistered returns false when plist does not exist")
    func isRegisteredInitiallyFalse() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        let registered = await manager.isRegistered()
        #expect(registered == false)
    }

    @Test("isRegistered returns true after plist exists on disk")
    func isRegisteredReflectsExistingPlist() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        try Data("fake-plist".utf8).write(to: plistURL)

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        let registered = await manager.isRegistered()
        #expect(registered == true)
    }

    // MARK: - register

    @Test("register creates plist file in LaunchAgents directory")
    func registerCreatesPlistFile() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        try await manager.register()

        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        #expect(FileManager.default.fileExists(atPath: plistURL.path))
    }

    @Test("register creates LaunchAgents directory if missing")
    func registerCreatesDirectoryIfMissing() async throws {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-launchagent-dirtest-\(UUID().uuidString)", isDirectory: true)
        let launchAgents = baseDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        // Verify precondition: directory does not exist yet
        #expect(FileManager.default.fileExists(atPath: launchAgents.path) == false)

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: launchAgents, recorder: recorder)

        try await manager.register()

        #expect(FileManager.default.fileExists(atPath: launchAgents.path))
    }

    @Test("register writes well-formed plist with required keys")
    func registerWritesWellFormedPlist() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(
            directory: dir,
            recorder: recorder,
            plistLabel: "com.riptide.test",
            executablePath: "/tmp/fake-riptide-binary"
        )

        try await manager.register()

        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        let data = try Data(contentsOf: plistURL)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]

        #expect(parsed != nil)
        #expect(parsed?["Label"] as? String == "com.riptide.test")
        #expect(parsed?["RunAtLoad"] as? Bool == true)
        #expect(parsed?["ProcessType"] as? String == "Interactive")

        let programArgs = parsed?["ProgramArguments"] as? [String]
        #expect(programArgs == ["/tmp/fake-riptide-binary"])
    }

    @Test("register invokes launchctl load -w with plist path")
    func registerInvokesLaunchctlLoad() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(
            directory: dir,
            recorder: recorder,
            plistLabel: "com.riptide.test"
        )

        try await manager.register()

        let expectedPlistPath = dir.appendingPathComponent("com.riptide.test.plist").path
        #expect(recorder.calls == [
            .init(executable: "/bin/launchctl", arguments: ["load", "-w", expectedPlistPath])
        ])
    }

    @Test("register throws when launchctl exits non-zero")
    func registerFailsWhenLaunchctlFails() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder(
            nextOutput: .init(terminationStatus: 1, stderr: "service not found")
        )
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        await #expect(throws: RiptideError.self) {
            try await manager.register()
        }

        // Plist should have been written even if launchctl failed
        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        #expect(FileManager.default.fileExists(atPath: plistURL.path))
    }

    @Test("register is idempotent: second call does not overwrite plist")
    func registerIsIdempotent() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(
            directory: dir,
            recorder: recorder,
            plistLabel: "com.riptide.test",
            executablePath: "/tmp/fake-riptide"
        )

        try await manager.register()
        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        let firstData = try Data(contentsOf: plistURL)

        // Modify plist externally to verify it isn't overwritten
        let modifiedData = Data("modified".utf8)
        try modifiedData.write(to: plistURL)
        let afterModification = try Data(contentsOf: plistURL)
        #expect(afterModification == modifiedData)

        try await manager.register()
        let afterSecondRegister = try Data(contentsOf: plistURL)
        #expect(afterSecondRegister == modifiedData, "Second register must not overwrite the existing plist")
        #expect(afterSecondRegister != firstData)
    }

    @Test("register does not throw on second call (idempotent success)")
    func registerSecondCallSucceeds() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        try await manager.register()
        try await manager.register()
    }

    // MARK: - unregister

    @Test("unregister removes existing plist file")
    func unregisterRemovesPlist() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        try await manager.register()
        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        #expect(FileManager.default.fileExists(atPath: plistURL.path))

        try await manager.unregister()
        #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    }

    @Test("unregister invokes launchctl unload with plist path")
    func unregisterInvokesLaunchctlUnload() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(
            directory: dir,
            recorder: recorder,
            plistLabel: "com.riptide.test"
        )

        try await manager.register()
        recorder.nextOutput = .init(terminationStatus: 0)
        recorder.reset()

        try await manager.unregister()

        let expectedPlistPath = dir.appendingPathComponent("com.riptide.test.plist").path
        #expect(recorder.calls == [
            .init(executable: "/bin/launchctl", arguments: ["unload", expectedPlistPath])
        ])
    }

    @Test("unregister is a no-op when plist does not exist")
    func unregisterIsIdempotent() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        // Should not throw
        try await manager.unregister()
        #expect(recorder.calls.isEmpty, "unregister on missing plist must not invoke launchctl")
    }

    @Test("unregister still removes plist when launchctl unload fails")
    func unregisterCleansUpEvenIfLaunchctlFails() async throws {
        let (dir, cleanup) = try Self.makeTempLaunchAgentsDirectory()
        defer { cleanup() }

        let recorder = ProcessRecorder()
        let manager = Self.makeManager(directory: dir, recorder: recorder)

        try await manager.register()
        recorder.nextOutput = .init(terminationStatus: 64, stderr: "service not loaded")
        recorder.reset()

        try await manager.unregister()
        let plistURL = dir.appendingPathComponent("com.riptide.test.plist")
        #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    }

    // MARK: - RiptideError

    @Test("RiptideError.launchAgentRegistrationFailed carries reason")
    func errorCarriesReason() {
        let error = RiptideError.launchAgentRegistrationFailed("disk full")
        #expect(error.errorDescription?.contains("disk full") == true)
        #expect(error.category == "应用")
    }
}
