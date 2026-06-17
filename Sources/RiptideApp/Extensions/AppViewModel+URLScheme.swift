import Foundation
import Riptide

// MARK: - Node Order & URL Scheme Support

extension AppViewModel {

    // MARK: - Node Order (drag/drop persistence)

    /// Returns the persisted node-name order for a group, or an empty array
    /// if the user has not yet reordered the group.
    public func nodeOrder(for groupID: String) -> [String] {
        nodeOrder[groupID] ?? []
    }

    /// Persists a new node-name order for a group and updates the in-memory
    /// state. Saving is best-effort; a JSON encode failure is silently
    /// ignored (the in-memory change still applies for the current session).
    public func setNodeOrder(_ order: [String], for groupID: String) {
        nodeOrder[groupID] = order
        saveNodeOrder()
    }

    /// Reads the persisted node-order map from UserDefaults. Missing or
    /// undecodable data is treated as "no persisted order".
    public func loadNodeOrder() {
        guard let data = UserDefaults.standard.data(forKey: "riptide.proxyGroup.nodeOrder"),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        nodeOrder = decoded
    }

    private func saveNodeOrder() {
        guard let data = try? JSONEncoder().encode(nodeOrder) else { return }
        UserDefaults.standard.set(data, forKey: "riptide.proxyGroup.nodeOrder")
    }

    // MARK: - URL Scheme Support
    //
    // Methods below are entry points used by `URLSchemeHandler` to route
    // `riptide://...` commands. They delegate to existing runtime APIs.
    // (Stored properties `pendingImportURL` / `urlSchemeError` live in the
    // main type body — Swift forbids stored properties in extensions.)

    /// Activates the proxy group with the given id and selects its first
    /// available node. Fails explicitly (via `urlSchemeError`) if the group
    /// is not present in the active profile — no silent fallback.
    public func selectGroup(named name: String) async {
        guard let profile = activeProfile else {
            urlSchemeError = "Cannot switch group: no active profile"
            return
        }
        guard let group = profile.config.proxyGroups.first(where: { $0.id == name }) else {
            urlSchemeError = "Proxy group '\(name)' not found"
            return
        }
        guard let firstNode = group.proxies.first else {
            urlSchemeError = "Proxy group '\(name)' has no nodes"
            return
        }
        await selectProxy(groupID: group.id, nodeName: firstNode)
    }

    /// Selects a node by name in whichever group contains it. Fails
    /// explicitly if the node is not present in the active profile.
    public func selectNode(named name: String) async {
        guard let profile = activeProfile else {
            urlSchemeError = "Cannot select node: no active profile"
            return
        }
        guard let group = profile.config.proxyGroups.first(where: { $0.proxies.contains(name) }) else {
            urlSchemeError = "Node '\(name)' not found in any group"
            return
        }
        await selectProxy(groupID: group.id, nodeName: name)
    }

    /// Switches the connection mode from a URL value. Accepts
    /// `"tun"`, `"system"`, and `"off"`. If the tunnel is currently running
    /// and a non-`off` value is given, the runtime is restarted in the new
    /// mode. Unknown values set `urlSchemeError` and are otherwise ignored.
    public func setMode(fromString value: String) async {
        let normalized = value.lowercased()
        let wasRunning = tunnelState == .running
        switch normalized {
        case "tun":
            connectionMode = .tun
        case "system":
            connectionMode = .systemProxy
        case "off":
            if wasRunning {
                await stop()
            }
            return
        default:
            urlSchemeError = "Unknown mode '\(value)' (expected: tun, system, off)"
            return
        }
        if wasRunning {
            await stop()
            await start()
        }
    }

    /// Generates a diagnostic report from the runtime and stores it in
    /// `lastError` for now (a dedicated diagnostics sheet can be wired up
    /// later by the UI layer). Returns the JSON-encoded report.
    @discardableResult
    public func runDiagnostics() async -> String {
        let report = await modeCoordinator.generateDiagnosticReport()
        // Surface a concise one-line summary so the UI shows something even
        // before a dedicated diagnostics sheet is implemented.
        let summary = "diagnostics: mihomo=\(report.mihomoRunning ? "running" : "stopped")"
        lastError = summary
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(report))
            .flatMap { String(data: $0, encoding: .utf8) } ?? summary
    }
}
