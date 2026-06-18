import Foundation
import Riptide

// MARK: - Status & Polling

extension AppViewModel {

    internal func startStatsPolling() {
        statsTask = Task {
            var logCounter = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshStats()
                // Refresh logs every 3 polling cycles (3 seconds)
                logCounter += 1
                if logCounter >= 3 {
                    logCounter = 0
                    await fetchLogs()
                }
            }
        }
    }

    internal func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
        currentSpeedUp = 0
        currentSpeedDown = 0
    }

    public func refreshStats() async {
        let traffic = await modeCoordinator.getTraffic()
        let connections = await modeCoordinator.getConnections()

        await MainActor.run {
            currentSpeedUp = traffic.up
            currentSpeedDown = traffic.down
            totalTrafficUp += traffic.up
            totalTrafficDown += traffic.down

            // Map enriched backend ConnectionInfo to app-level ConnectionInfo
            let mapped = connections.map { conn in
                let meta = conn.metadata
                return ConnectionInfo(
                    id: UUID(uuidString: conn.id) ?? UUID(),
                    backendId: conn.id,
                    host: meta.host ?? meta.destinationIP ?? "unknown",
                    port: Int(meta.destinationPort ?? "") ?? 0,
                    protocol: meta.network.uppercased(),
                    proxyName: conn.chains.last ?? "Direct",
                    connectionCount: 1,
                    sourceIP: meta.sourceIP,
                    sourcePort: meta.sourcePort,
                    destinationIP: meta.destinationIP,
                    destinationPort: meta.destinationPort,
                    matchedRule: conn.rule,
                    rulePayload: conn.rulePayload,
                    chain: conn.chains,
                    startTime: conn.start,
                    uploadBytes: conn.upload,
                    downloadBytes: conn.download,
                    networkType: meta.type
                )
            }
            activeConnections = mapped
        }
    }
}
