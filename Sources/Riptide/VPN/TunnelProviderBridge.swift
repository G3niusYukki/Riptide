import Foundation
import NetworkExtension

/// Bidirectional communication channel between the main app and the tunnel extension.
/// Uses NETunnelProviderSession for app→extension and Darwin notifications for extension→app.
public actor TunnelProviderBridge {
    private var session: NETunnelProviderSession?
    private var connectionEventContinuation: AsyncStream<TunnelBridgeEvent>.Continuation?

    public static let appGroupIdentifier = "group.com.riptide.app"
    public static let commandFileName = "tunnel_command.json"
    public static let eventFileName = "tunnel_event.json"

    public init() {}

    /// Connect to a configured VPN manager.
    public func connect() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "com.riptide.tunnel"
        }) else {
            throw TunnelBridgeError.managerNotFound
        }
        guard manager.connection.status == .connected else {
            throw TunnelBridgeError.notConnected
        }
        self.session = manager.connection as? NETunnelProviderSession
    }

    /// Send a command to the running tunnel extension.
    public func sendCommand(_ command: TunnelBridgeCommand) async throws {
        guard let session = session else {
            throw TunnelBridgeError.notConnected
        }
        let data = try JSONEncoder().encode(command)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try session.sendProviderMessage(data) { _ in
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Stream of events from the extension (status changes, traffic updates, logs).
    public func events() -> AsyncStream<TunnelBridgeEvent> {
        AsyncStream { continuation in
            self.connectionEventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    private func clearContinuation() {
        connectionEventContinuation = nil
    }

    /// Post an event from the extension side (called by extension).
    public nonisolated func postEvent(_ event: TunnelBridgeEvent) {
        // Extension side writes event to shared app group file
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else { return }
        let fileURL = containerURL.appendingPathComponent(Self.eventFileName)
        if let data = try? JSONEncoder().encode(event) {
            try? data.write(to: fileURL)
        }
        // Post CoreFoundation Darwin notification to wake the app
        let notificationName = TunnelBridgeEvent.notificationName as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
    }
}

// MARK: - Commands (app → extension)

public enum TunnelBridgeCommand: Codable, Equatable {
    case start(configYAML: String)
    case stop
    case switchConfig(configYAML: String)
    case selectProxy(groupID: String, nodeName: String)
    case updateDNS(policy: String)
}

// MARK: - Events (extension → app)

public enum TunnelBridgeEvent: Codable, Equatable {
    case tunnelStarted
    case tunnelStopped(reason: String)
    case trafficUpdated(up: UInt64, down: UInt64, connections: Int)
    case logEntry(level: String, message: String)
    case error(message: String)

    public static let notificationName = "com.riptide.tunnel.event"

    private enum CodingKeys: String, CodingKey {
        case tunnelStarted, tunnelStopped, trafficUpdated, logEntry, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.tunnelStarted) {
            self = .tunnelStarted
        } else if let stopped = try container.decodeIfPresent(TunnelStoppedPayload.self, forKey: .tunnelStopped) {
            self = .tunnelStopped(reason: stopped.reason)
        } else if let traffic = try container.decodeIfPresent(TrafficPayload.self, forKey: .trafficUpdated) {
            self = .trafficUpdated(up: traffic.up, down: traffic.down, connections: traffic.connections)
        } else if let log = try container.decodeIfPresent(LogPayload.self, forKey: .logEntry) {
            self = .logEntry(level: log.level, message: log.message)
        } else if let err = try container.decodeIfPresent(ErrorPayload.self, forKey: .error) {
            self = .error(message: err.message)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown event type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tunnelStarted:
            try container.encode(true as Bool, forKey: .tunnelStarted)
        case .tunnelStopped(let reason):
            try container.encode(TunnelStoppedPayload(reason: reason), forKey: .tunnelStopped)
        case .trafficUpdated(let up, let down, let connections):
            try container.encode(TrafficPayload(up: up, down: down, connections: connections), forKey: .trafficUpdated)
        case .logEntry(let level, let message):
            try container.encode(LogPayload(level: level, message: message), forKey: .logEntry)
        case .error(let message):
            try container.encode(ErrorPayload(message: message), forKey: .error)
        }
    }

    private struct TunnelStoppedPayload: Codable { let reason: String }
    private struct TrafficPayload: Codable { let up: UInt64; let down: UInt64; let connections: Int }
    private struct LogPayload: Codable { let level: String; let message: String }
    private struct ErrorPayload: Codable { let message: String }
}

// MARK: - Errors

public enum TunnelBridgeError: Error, LocalizedError {
    case managerNotFound
    case notConnected
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .managerNotFound: return "VPN manager not found"
        case .notConnected: return "Tunnel not connected"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        }
    }
}
