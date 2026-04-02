import Foundation
import Testing

@testable import Riptide
@testable import RiptideCLI

@Suite("CLI command helpers")
struct CLICommandTests {
    @Test("validate command succeeds with valid config")
    func validateSuccess() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,my-socks
        """

        let summary = try CLICommandRunner.validateConfig(yamlContent: yaml, profileName: "test")
        #expect(summary.contains("mode=rule"))
        #expect(summary.contains("proxies=1"))
        #expect(summary.contains("rules=1"))
    }

    @Test("validate command fails with invalid config")
    func validateFailure() {
        #expect(throws: ClashConfigError.self) {
            _ = try CLICommandRunner.validateConfig(yamlContent: "not: [valid", profileName: "test")
        }
    }

    @Test("run command reports running state")
    func runReportsRunningState() async throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,my-socks
        """

        let text = try await CLICommandRunner.runConfig(
            yamlContent: yaml,
            profileName: "test"
        )
        #expect(text.contains("state=running"))
        #expect(text.contains("profile=test"))
    }

    @Test("smoke command helper reports success text")
    func smokeReportsSuccess() async throws {
        let yaml = """
        mode: rule
        proxies:
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,my-socks
        """
        let session = MockCLISession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let mockDialer = CLITestMockDialer(sessions: [session])

        let text = try await CLICommandRunner.smokeConfig(
            yamlContent: yaml,
            profileName: "test",
            targetHost: "example.com",
            targetPort: 443,
            proxyDialer: mockDialer,
            directDialer: mockDialer
        )
        #expect(text.contains("smoke=ok"))
    }
}
