import Foundation
import Observation
import AppKit
import Riptide

/// ViewModel for MITM settings, bridging the MITMManager to SwiftUI.
@MainActor
@Observable
public final class MITMSettingsViewModel {
    public var enabled: Bool = false
    public var hosts: [String] = []
    public var excludeHosts: [String] = []
    public var isCAInstalled: Bool = false
    public var interceptLog: [String] = []
    public var httpFlowRecords: [MITMHTTPFlowRecord] = []

    private let mitmManager: MITMManager

    public init(mitmManager: MITMManager = MITMManager()) {
        self.mitmManager = mitmManager
        Task { await loadConfig() }
    }

    private func loadConfig() async {
        let config = await mitmManager.getConfig()
        enabled = config.enabled
        hosts = config.hosts
        excludeHosts = config.excludeHosts
        isCAInstalled = await mitmManager.isCAInstalled()
        httpFlowRecords = await mitmManager.recentHTTPFlowRecords()

        // Set up interception logging
        await mitmManager.setOnRequestIntercepted { [weak self] method, host in
            Task { @MainActor in
                self?.interceptLog.append("[\(Date().formatted(date: .omitted, time: .standard))] \(method) → \(host)")
                // Keep log manageable
                if self?.interceptLog.count ?? 0 > 200 {
                    self?.interceptLog.removeFirst(50)
                }
            }
        }

        await mitmManager.setOnHTTPFlowUpdated { [weak self] record in
            Task { @MainActor in
                self?.upsertHTTPFlowRecord(record)
            }
        }
    }

    public func enableMITM() {
        Task {
            await mitmManager.enable(hosts: hosts, excludeHosts: excludeHosts)
            enabled = true
        }
    }

    public func disableMITM() {
        Task {
            await mitmManager.disable()
            enabled = false
        }
    }

    public func addHost(_ pattern: String) {
        hosts.append(pattern)
        Task {
            await mitmManager.enable(hosts: hosts, excludeHosts: excludeHosts)
        }
    }

    public func removeHost(_ pattern: String) {
        hosts.removeAll { $0 == pattern }
        Task {
            await mitmManager.enable(hosts: hosts, excludeHosts: excludeHosts)
        }
    }

    public func addExcludeHost(_ pattern: String) {
        excludeHosts.append(pattern)
        Task {
            await mitmManager.enable(hosts: hosts, excludeHosts: excludeHosts)
        }
    }

    public func removeExcludeHost(_ pattern: String) {
        excludeHosts.removeAll { $0 == pattern }
        Task {
            await mitmManager.enable(hosts: hosts, excludeHosts: excludeHosts)
        }
    }

    public func installCertificate() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Utilities/Keychain Access.app"))
    }

    public func clearHTTPFlowRecords() {
        Task {
            await mitmManager.clearHTTPFlowRecords()
            httpFlowRecords.removeAll()
        }
    }

    private func upsertHTTPFlowRecord(_ record: MITMHTTPFlowRecord) {
        if let index = httpFlowRecords.firstIndex(where: { $0.id == record.id }) {
            httpFlowRecords[index] = record
        } else {
            httpFlowRecords.append(record)
        }

        if httpFlowRecords.count > 200 {
            httpFlowRecords.removeFirst(httpFlowRecords.count - 200)
        }
    }
}
