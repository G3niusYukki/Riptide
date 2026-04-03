import Foundation
import Riptide

public enum CLICommandRunnerError: Error, Equatable, Sendable {
    case startFailed(String)
    case statusFailed(String)
    case invalidResponse(String)
}

public enum CLICommandRunner {
    public static func validateConfig(yamlContent: String, profileName: String) throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let config = imported.profile.config
        return "mode=\(config.mode.rawValue) proxies=\(config.proxies.count) rules=\(config.rules.count)"
    }

    public static func runConfig(yamlContent: String, profileName: String) async throws -> String {
        try await runConfig(
            yamlContent: yamlContent,
            profileName: profileName,
            runtime: CLIMockTunnelRuntime()
        )
    }

    public static func runConfig(
        yamlContent: String,
        profileName: String,
        runtime: any TunnelRuntime
    ) async throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)

        let startResponse = try await channel.send(.start(imported.profile))
        switch startResponse {
        case .ack:
            break
        case .error(let message):
            throw CLICommandRunnerError.startFailed(message)
        case .status(let snapshot):
            throw CLICommandRunnerError.invalidResponse(
                "unexpected status response on start: \(snapshot.state)"
            )
        }

        let statusResponse = try await channel.send(.status)
        switch statusResponse {
        case .status(let snapshot):
            return
                "state=\(snapshot.state) profile=\(snapshot.activeProfileName ?? "none") up=\(snapshot.bytesUp) down=\(snapshot.bytesDown) conn=\(snapshot.activeConnections)"
        case .error(let message):
            throw CLICommandRunnerError.statusFailed(message)
        case .ack:
            throw CLICommandRunnerError.invalidResponse("unexpected ack response on status")
        }
    }

    public static func smokeConfig(
        yamlContent: String,
        profileName: String,
        targetHost: String,
        targetPort: Int
    ) async throws -> String {
        try await smokeConfig(
            yamlContent: yamlContent,
            profileName: profileName,
            targetHost: targetHost,
            targetPort: targetPort,
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer(),
            dnsPipeline: DNSPipeline()
        )
    }

    public static func smokeConfig(
        yamlContent: String,
        profileName: String,
        targetHost: String,
        targetPort: Int,
        proxyDialer: any TransportDialer,
        directDialer: any TransportDialer,
        dnsPipeline: DNSPipeline
    ) async throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer, dnsPipeline: dnsPipeline)
        try await runtime.start(profile: imported.profile)

        do {
            _ = try await runtime.openConnection(target: ConnectionTarget(host: targetHost, port: targetPort))
            return "smoke=ok target=\(targetHost):\(targetPort)"
        } catch {
            return "smoke=error target=\(targetHost):\(targetPort) reason=\(String(describing: error))"
        }
    }
}
