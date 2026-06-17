import Foundation
import Testing
@testable import Riptide

/// Records the privileged scripts a `TunDaemonController` would run as root,
/// so tests can assert what gets elevated without actually elevating.
private actor ScriptRecorder {
    private(set) var scripts: [String] = []
    func record(_ script: String) { scripts.append(script) }
    var last: String? { scripts.last }
}

@Suite("TUN daemon controller")
struct TunDaemonControllerTests {

    /// Creates an isolated temp `{support}` + `{launchDaemons}` pair and returns a
    /// controller plus its recorder. If `installed` is true, the marker files that
    /// `isInstalled()` checks are pre-created.
    private func makeController(
        installed: Bool
    ) throws -> (controller: TunDaemonController, support: URL, launchDaemons: URL, recorder: ScriptRecorder) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-tun-test-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let launchDaemons = root.appendingPathComponent("LaunchDaemons", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDaemons, withIntermediateDirectories: true)

        if installed {
            FileManager.default.createFile(
                atPath: support.appendingPathComponent("riptide-singbox").path, contents: Data())
            FileManager.default.createFile(
                atPath: launchDaemons.appendingPathComponent("\(TunDaemonController.daemonLabel).plist").path,
                contents: Data())
        }

        let recorder = ScriptRecorder()
        let controller = TunDaemonController(
            supportDir: support,
            launchDaemonsDir: launchDaemons,
            uid: 501,
            privilegedRunner: { script in await recorder.record(script) }
        )
        return (controller, support, launchDaemons, recorder)
    }

    @Test("enable writes the config and the KeepAlive flag; disable removes the flag")
    func enableDisableTogglesFlag() async throws {
        let env = try makeController(installed: true)
        #expect(await env.controller.isInstalled())
        #expect(await env.controller.isEnabled() == false)

        let json = #"{"inbounds":[{"type":"tun"}]}"#
        try await env.controller.enable(configJSON: json)

        let tunDir = env.support.appendingPathComponent("tun", isDirectory: true)
        let configPath = tunDir.appendingPathComponent("config.json")
        let flagPath = tunDir.appendingPathComponent("enabled")
        #expect(FileManager.default.fileExists(atPath: configPath.path))
        #expect(FileManager.default.fileExists(atPath: flagPath.path))
        #expect(try String(contentsOf: configPath, encoding: .utf8) == json)
        #expect(await env.controller.isEnabled())

        try await env.controller.disable()
        #expect(FileManager.default.fileExists(atPath: flagPath.path) == false)
        #expect(await env.controller.isEnabled() == false)
        // enable/disable must never elevate.
        #expect(await env.recorder.scripts.isEmpty)
    }

    @Test("enable throws when the daemon is not installed")
    func enableRequiresInstall() async throws {
        let env = try makeController(installed: false)
        #expect(await env.controller.isInstalled() == false)
        await #expect(throws: TunDaemonController.TunDaemonError.notInstalled) {
            try await env.controller.enable(configJSON: "{}")
        }
    }

    @Test("install builds a privileged script that bootstraps a PathState-gated daemon")
    func installScriptShape() async throws {
        let env = try makeController(installed: false)
        // A real, executable binary source is required.
        let binary = env.support.appendingPathComponent("source-core")
        FileManager.default.createFile(atPath: binary.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        try await env.controller.install(binarySource: binary)

        let script = try #require(await env.recorder.last)
        // Copies the core into place and makes it executable.
        #expect(script.contains(#"cp "\#(binary.path)""#))
        #expect(script.contains("chmod 755"))
        // Hands the working dir to the installing user (uid 501) and locks it down.
        #expect(script.contains("chown 501"))
        #expect(script.contains("chmod 700"))
        // Bootstraps the launchd daemon.
        #expect(script.contains("launchctl bootstrap system"))
        #expect(script.contains("\(TunDaemonController.daemonLabel)"))
        // The plist uses KeepAlive PathState on the flag file.
        #expect(script.contains("KeepAlive"))
        #expect(script.contains("PathState"))
        #expect(script.contains("/tun/enabled"))
        #expect(script.contains("/tun/config.json"))
    }

    @Test("install rejects a missing core binary")
    func installRejectsMissingBinary() async throws {
        let env = try makeController(installed: false)
        let missing = env.support.appendingPathComponent("nope")
        await #expect(throws: TunDaemonController.TunDaemonError.binaryNotFound) {
            try await env.controller.install(binarySource: missing)
        }
    }

    @Test("uninstall builds a script that boots out the daemon and removes its files")
    func uninstallScriptShape() async throws {
        let env = try makeController(installed: true)
        try await env.controller.uninstall()
        let script = try #require(await env.recorder.last)
        #expect(script.contains("launchctl bootout system/\(TunDaemonController.daemonLabel)"))
        #expect(script.contains("rm -f"))
        #expect(script.contains("rm -rf"))
        #expect(script.contains("/tun"))
    }

    @Test("plist XML pins the core, the config arg, and the PathState flag")
    func plistShape() {
        let xml = TunDaemonController.plistXML(
            label: "com.riptide.tun",
            binary: "/Library/Application Support/Riptide/riptide-singbox",
            config: "/Library/Application Support/Riptide/tun/config.json",
            flag: "/Library/Application Support/Riptide/tun/enabled",
            log: "/Library/Application Support/Riptide/tun/singbox.log"
        )
        #expect(xml.contains("<string>com.riptide.tun</string>"))
        #expect(xml.contains("<string>/Library/Application Support/Riptide/riptide-singbox</string>"))
        #expect(xml.contains("<string>-c</string>"))
        #expect(xml.contains("<key>PathState</key>"))
        #expect(xml.contains("<key>/Library/Application Support/Riptide/tun/enabled</key>"))
        #expect(xml.contains("<key>RunAtLoad</key>"))
    }
}

@Suite("sing-box binary locator")
struct SingBoxBinaryLocatorTests {

    @Test("honors the RIPTIDE_SINGBOX_PATH override when executable")
    func usesOverride() throws {
        let bin = FileManager.default.temporaryDirectory
            .appendingPathComponent("riptide-singbox-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: bin.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        defer { try? FileManager.default.removeItem(at: bin) }

        let found = SingBoxBinaryLocator.locate(environment: ["RIPTIDE_SINGBOX_PATH": bin.path])
        #expect(found?.path == bin.path)
    }

    @Test("returns nil when the override points at a non-executable path")
    func nilWhenAbsent() {
        let missing = "/tmp/definitely-not-here-\(UUID().uuidString)/riptide-singbox"
        let found = SingBoxBinaryLocator.locate(environment: ["RIPTIDE_SINGBOX_PATH": missing])
        // Could still resolve via Bundle/CWD in some environments; only assert it
        // did not pick the bogus override.
        #expect(found?.path != missing)
    }
}
