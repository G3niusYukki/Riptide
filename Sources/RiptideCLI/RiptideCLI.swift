import ArgumentParser
import Foundation

@main
struct RiptideCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "riptide",
        abstract: "Riptide CLI",
        subcommands: [Validate.self, Run.self]
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
}
