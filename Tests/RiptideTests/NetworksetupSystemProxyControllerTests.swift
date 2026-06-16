import Foundation
import Testing

@testable import Riptide

@Suite("Networksetup system proxy controller")
struct NetworksetupSystemProxyControllerTests {

    /// Records every command the controller issues, and serves a canned
    /// `-listallnetworkservices` response.
    actor Recorder {
        private(set) var calls: [[String]] = []
        private(set) var paths: [String] = []
        var serviceList = "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\nEthernet"

        func record(path: String, args: [String]) {
            paths.append(path)
            calls.append(args)
        }

        func setServiceList(_ list: String) { serviceList = list }
    }

    private func makeController(
        _ recorder: Recorder,
        proxyExitCode: Int32 = 0
    ) -> NetworksetupSystemProxyController {
        NetworksetupSystemProxyController(runner: { path, args in
            await recorder.record(path: path, args: args)
            if args.first == "-listallnetworkservices" {
                return .init(exitCode: 0, output: await recorder.serviceList)
            }
            return .init(exitCode: proxyExitCode, output: proxyExitCode == 0 ? "" : "boom")
        })
    }

    @Test("enable never shells out to sudo — only direct networksetup")
    func enableNeverUsesSudo() async throws {
        let recorder = Recorder()
        let controller = makeController(recorder)

        try await controller.enable(httpPort: 6152, socksPort: 6152)

        let paths = await recorder.paths
        #expect(!paths.isEmpty)
        #expect(paths.allSatisfy { $0 == "/usr/sbin/networksetup" })
        #expect(!paths.contains { $0.contains("sudo") })
    }

    @Test("enable issues web/secure/socks proxy commands to 127.0.0.1 with the port")
    func enableIssuesProxyCommands() async throws {
        let recorder = Recorder()
        let controller = makeController(recorder)

        try await controller.enable(httpPort: 6152, socksPort: 6152)

        let calls = await recorder.calls
        #expect(calls.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "6152"]))
        #expect(calls.contains(["-setsecurewebproxy", "Wi-Fi", "127.0.0.1", "6152"]))
        #expect(calls.contains(["-setsocksfirewallproxy", "Wi-Fi", "127.0.0.1", "6152"]))
    }

    @Test("enable updates currentState")
    func enableUpdatesState() async throws {
        let recorder = Recorder()
        let controller = makeController(recorder)

        #expect(controller.currentState() == .disabled)
        try await controller.enable(httpPort: 6152, socksPort: 6152)
        #expect(controller.currentState() == .enabled(httpPort: 6152, socksPort: 6152))
    }

    @Test("disable turns every proxy type off and clears state")
    func disableTurnsOff() async throws {
        let recorder = Recorder()
        let controller = makeController(recorder)

        try await controller.enable(httpPort: 6152, socksPort: 6152)
        try await controller.disable()

        let calls = await recorder.calls
        #expect(calls.contains(["-setwebproxystate", "Wi-Fi", "off"]))
        #expect(calls.contains(["-setsecurewebproxystate", "Wi-Fi", "off"]))
        #expect(calls.contains(["-setsocksfirewallproxystate", "Wi-Fi", "off"]))
        #expect(controller.currentState() == .disabled)
    }

    @Test("enable throws when networksetup fails")
    func enableThrowsOnFailure() async {
        let recorder = Recorder()
        let controller = makeController(recorder, proxyExitCode: 1)

        await #expect(throws: SystemProxyError.self) {
            try await controller.enable(httpPort: 6152, socksPort: 6152)
        }
    }

    @Test("service detection skips disabled (*) services and the header line")
    func serviceDetectionSkipsDisabled() {
        let output = "An asterisk (*) denotes that a network service is disabled.\n*Old Ethernet\nWi-Fi\nThunderbolt Bridge"
        #expect(NetworksetupSystemProxyController.firstActiveService(from: output) == "Wi-Fi")
    }

    @Test("service detection returns nil when only disabled services exist")
    func serviceDetectionAllDisabled() {
        let output = "An asterisk (*) denotes that a network service is disabled.\n*Wi-Fi\n*Ethernet"
        #expect(NetworksetupSystemProxyController.firstActiveService(from: output) == nil)
    }

    @Test("enable with nil socks port omits the socks command")
    func enableWithoutSocks() async throws {
        let recorder = Recorder()
        let controller = makeController(recorder)

        try await controller.enable(httpPort: 6152, socksPort: nil)

        let calls = await recorder.calls
        #expect(calls.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "6152"]))
        #expect(!calls.contains { $0.first == "-setsocksfirewallproxy" })
    }

    @Test("parseEnabledPort returns the port only when the proxy is enabled")
    func parseEnabledPort() {
        let enabled = "Enabled: Yes\nServer: 127.0.0.1\nPort: 6152\nAuthenticated Proxy Enabled: 0"
        #expect(NetworksetupSystemProxyController.parseEnabledPort(from: enabled) == 6152)

        let disabled = "Enabled: No\nServer: 127.0.0.1\nPort: 6152"
        #expect(NetworksetupSystemProxyController.parseEnabledPort(from: disabled) == nil)
    }

    @Test("activeHTTPProxyPort reads the live port via networksetup -getwebproxy")
    func activeHTTPProxyPort() async {
        let recorder = Recorder()
        let controller = NetworksetupSystemProxyController(runner: { path, args in
            await recorder.record(path: path, args: args)
            switch args.first {
            case "-listallnetworkservices":
                return .init(exitCode: 0, output: await recorder.serviceList)
            case "-getwebproxy":
                return .init(exitCode: 0, output: "Enabled: Yes\nServer: 127.0.0.1\nPort: 6152")
            default:
                return .init(exitCode: 0, output: "")
            }
        })
        let port = await controller.activeHTTPProxyPort()
        #expect(port == 6152)
        let paths = await recorder.paths
        #expect(paths.allSatisfy { $0 == "/usr/sbin/networksetup" })
    }
}
