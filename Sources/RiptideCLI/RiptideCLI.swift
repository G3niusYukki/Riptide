import ArgumentParser
import Foundation

@main
struct RiptideCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "riptide",
        abstract: "Riptide CLI",
        subcommands: [Validate.self, Run.self, Smoke.self]
    )

    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Validate a clash config file")

        @Option(name: [.short, .long], help: "Path to yaml config")
        var config: String

        mutating func run() async throws {
            let content = try String(contentsOfFile: config, encoding: .utf8)
            let summary = try CLICommandRunner.validateConfig(yamlContent: content, profileName: "cli")
            print("VALID \(summary)")
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run lifecycle simulation with config")

        @Option(name: [.short, .long], help: "Path to yaml config")
        var config: String

        mutating func run() async throws {
            let content = try String(contentsOfFile: config, encoding: .utf8)
            let summary = try await CLICommandRunner.runConfig(yamlContent: content, profileName: "cli")
            print("RUNNING \(summary)")
        }
    }

    struct Smoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run live connectivity smoke check")

        @Option(name: [.short, .long], help: "Path to yaml config")
        var config: String

        @Option(name: .long, help: "Target host for smoke check")
        var host: String = "example.com"

        @Option(name: .long, help: "Target port for smoke check")
        var port: Int = 443

        mutating func run() async throws {
            let content = try String(contentsOfFile: config, encoding: .utf8)
            let summary = try await CLICommandRunner.smokeConfig(
                yamlContent: content,
                profileName: "cli",
                targetHost: host,
                targetPort: port
            )
            print("SMOKE \(summary)")
        }
    }
}
