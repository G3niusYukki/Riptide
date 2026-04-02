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
}
