import Foundation
import Riptide

public enum CLICommandRunner {
    public static func validateConfig(yamlContent: String, profileName: String) throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let config = imported.profile.config
        return "mode=\(config.mode.rawValue) proxies=\(config.proxies.count) rules=\(config.rules.count)"
    }

    public static func runConfig(yamlContent: String, profileName: String) async throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let runtime = CLIMockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        try await manager.start(profile: imported.profile)
        let snapshot = await manager.status()
        return "state=\(snapshot.state) profile=\(snapshot.activeProfileName ?? "none") up=\(snapshot.bytesUp) down=\(snapshot.bytesDown) conn=\(snapshot.activeConnections)"
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
            directDialer: TCPTransportDialer()
        )
    }

    public static func smokeConfig(
        yamlContent: String,
        profileName: String,
        targetHost: String,
        targetPort: Int,
        proxyDialer: any TransportDialer,
        directDialer: any TransportDialer
    ) async throws -> String {
        let imported = try ConfigImportService().importProfile(name: profileName, yaml: yamlContent)
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)
        try await runtime.start(profile: imported.profile)

        do {
            _ = try await runtime.openConnection(target: ConnectionTarget(host: targetHost, port: targetPort))
            return "smoke=ok target=\(targetHost):\(targetPort)"
        } catch {
            return "smoke=error target=\(targetHost):\(targetPort) reason=\(String(describing: error))"
        }
    }
}
