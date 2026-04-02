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
}
