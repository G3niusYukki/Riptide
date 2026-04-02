import ArgumentParser
import Foundation
import Riptide

@main
struct RiptideCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "riptide",
        abstract: "Riptide CLI",
        subcommands: [Validate.self, Run.self, Smoke.self, Serve.self]
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

    struct Serve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a local HTTP CONNECT proxy backed by the live runtime"
        )

        @Option(name: [.short, .long], help: "Path to yaml config")
        var config: String

        @Option(name: .long, help: "Listen host to advertise")
        var host: String = "127.0.0.1"

        @Option(name: .long, help: "Listen port, or 0 for an ephemeral port")
        var port: Int = 6152

        mutating func run() async throws {
            guard (0...65_535).contains(port) else {
                throw ValidationError("listen port must be between 0 and 65535")
            }

            let content = try String(contentsOfFile: config, encoding: .utf8)
            let imported = try ConfigImportService().importProfile(name: "cli", yaml: content)
            let runtime = LiveTunnelRuntime(
                proxyDialer: TCPTransportDialer(),
                directDialer: TCPTransportDialer()
            )
            try await runtime.start(profile: imported.profile)

            let server = LocalHTTPConnectProxyServer(runtime: runtime)
            let endpoint = try await server.start(host: host, port: UInt16(port))

            print("SERVING http-connect=\(endpoint.host):\(endpoint.port) profile=\(imported.profile.name)")

            while true {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }
}
