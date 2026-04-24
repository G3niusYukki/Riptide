import Testing
@testable import Riptide

@Suite("SudoMihomoLauncher Tests")
struct SudoMihomoLauncherTests {

    @Test("Initial state is not running with nil pid")
    func initialState() async {
        let launcher = SudoMihomoLauncher()
        #expect(await launcher.isRunning == false)
        #expect(await launcher.pid == nil)
    }

    @Test("Launch with nonexistent binary throws binaryNotFound")
    func launchInvalidBinary() async {
        let launcher = SudoMihomoLauncher()
        await #expect(throws: SudoMihomoLauncher.SudoLaunchError.binaryNotFound("/nonexistent/mihomo")) {
            try await launcher.launch(binaryPath: "/nonexistent/mihomo", configPath: "/tmp/config.yaml")
        }
    }

    @Test("Terminate when not running throws notRunning")
    func terminateNotRunning() async {
        let launcher = SudoMihomoLauncher()
        await #expect(throws: SudoMihomoLauncher.SudoLaunchError.notRunning) {
            try await launcher.terminate()
        }
    }

    @Test("Failed launch does not leave launcher in running state")
    func failedLaunchDoesNotMarkRunning() async {
        let launcher = SudoMihomoLauncher()
        // Attempt launch with invalid binary — should fail with binaryNotFound
        try? await launcher.launch(binaryPath: "/nonexistent/mihomo", configPath: "/tmp/config.yaml")
        // Launcher should still report not running
        #expect(await launcher.isRunning == false)
        #expect(await launcher.pid == nil)
    }
}
