import Foundation
import Network

/// Actor that provides a WebSocket-based external controller compatible with Clash REST API.
///
/// Endpoints:
/// - GET /configs — return current config
/// - PUT /configs — update config
/// - GET /proxies — return proxy list
/// - GET /proxies/{name} — return proxy status
/// - PUT /proxies/{name} — select proxy (for selector groups)
/// - GET /rules — return current rules
/// - GET /connections — return active connections
/// - DELETE /connections/{id} — close a connection
/// - GET /traffic — return traffic stats (WebSocket streaming)
/// - GET /proxies/{name}/delay — test proxy latency
public actor WebSocketExternalController {
    private let runtime: LiveTunnelRuntime
    private let config: RiptideConfig
    private let healthChecker: HealthChecker?
    private var listener: NWListener?
    private var activeConnections: [UUID: WebSocketConnection] = [:]
    /// Current group selections, keyed by group name.
    private var groupSelections: [String: String] = [:]
    /// Cached delay results, keyed by proxy name.
    private var delayCache: [String: DelayHistory] = [:]

    public struct DelayHistory: Sendable {
        public var history: [DelayEntry]
        public var delay: Int?

        public init(history: [DelayEntry] = [], delay: Int? = nil) {
            self.history = history
            self.delay = delay
        }
    }

    public struct DelayEntry: Sendable, Encodable {
        public let time: String
        public let delay: Int

        public init(time: String = ISO8601DateFormatter().string(from: Date()), delay: Int) {
            self.time = time
            self.delay = delay
        }
    }

    public init(runtime: LiveTunnelRuntime, config: RiptideConfig, healthChecker: HealthChecker? = nil) {
        self.runtime = runtime
        self.config = config
        self.healthChecker = healthChecker
        // Initialize group selections from config
        for group in config.proxyGroups {
            if let first = group.proxies.first {
                groupSelections[group.id] = first
            }
        }
    }

    /// Start the WebSocket controller on the specified host and port.
    public func start(host: String = "127.0.0.1", port: UInt16 = 9090) async throws -> String {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TransportError.dialFailed("invalid port")
        }

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters, on: nwPort)

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        listener.start(queue: .global())
        self.listener = listener
        return "ws://\(host):\(port)"
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for (_, conn) in activeConnections {
            conn.nwConnection.cancel()
        }
        activeConnections.removeAll()
    }

    private func handleConnection(_ connection: NWConnection) async {
        let connId = UUID()
        let wsConn = WebSocketConnection(id: connId, nwConnection: connection)
        activeConnections[connId] = wsConn

        connection.start(queue: .global())

        do {
            try await handleWebSocketMessages(wsConn)
        } catch {
            // Connection closed or error
        }

        activeConnections.removeValue(forKey: connId)
        connection.cancel()
    }

    private func handleWebSocketMessages(_ connection: WebSocketConnection) async throws {
        while true {
            let (data, metadata) = try await receiveWebSocketMessage(connection.nwConnection)

            guard let data = data,
                  metadata.opcode == .text || metadata.opcode == .binary else { continue }

            // Parse JSON request
            guard let request = try? JSONDecoder().decode(WebSocketRequest.self, from: data) else {
                try await sendError(connection, id: nil, message: "Invalid JSON request")
                continue
            }

            // Handle request
            let response = await handleRequest(request)
            try await sendResponse(connection, response: response)
        }
    }

    private func receiveWebSocketMessage(_ connection: NWConnection) async throws -> (Data?, NWProtocolWebSocket.Metadata) {
        return try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, context, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let context else {
                    continuation.resume(throwing: TransportError.receiveFailed("No context"))
                    return
                }
                guard let metadata = context.protocolMetadata.first(where: { $0 is NWProtocolWebSocket.Metadata }) as? NWProtocolWebSocket.Metadata else {
                    continuation.resume(throwing: TransportError.receiveFailed("No WebSocket metadata"))
                    return
                }
                continuation.resume(returning: (data, metadata))
            }
        }
    }

    private func sendResponse(_ connection: WebSocketConnection, response: WebSocketResponse) async throws {
        let data = try JSONEncoder().encode(response)
        try await sendWebSocketData(connection.nwConnection, data: data)
    }

    private func sendError(_ connection: WebSocketConnection, id: String?, message: String) async throws {
        let response = WebSocketResponse(
            id: id,
            status: "error",
            data: nil,
            error: message
        )
        try await sendResponse(connection, response: response)
    }

    private func sendWebSocketData(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "message", metadata: [metadata])

            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func handleRequest(_ request: WebSocketRequest) async -> WebSocketResponse {
        switch (request.method, request.path) {
        case ("GET", "/configs"):
            return await handleGetConfigs(request)
        case ("PUT", "/configs"):
            return await handlePutConfigs(request)
        case ("GET", "/proxies"):
            return await handleGetProxies(request)
        case ("GET", _) where request.path.hasPrefix("/proxies/") && request.path.hasSuffix("/delay"):
            return await handleGetProxyDelay(request)
        case ("GET", _) where request.path.hasPrefix("/proxies/"):
            return await handleGetProxy(request)
        case ("PUT", _) where request.path.hasPrefix("/proxies/"):
            return await handlePutProxy(request)
        case ("GET", "/rules"):
            return await handleGetRules(request)
        case ("GET", "/connections"):
            return await handleGetConnections(request)
        case ("DELETE", _) where request.path.hasPrefix("/connections/"):
            return await handleDeleteConnection(request)
        case ("GET", "/traffic"):
            return await handleGetTraffic(request)
        case ("GET", "/version"):
            return handleGetVersion(request)
        default:
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Not found")
        }
    }

    private func handleGetConfigs(_ request: WebSocketRequest) async -> WebSocketResponse {
        let data: [String: Any] = [
            "port": 7890,
            "socks-port": 7891,
            "mode": config.mode.rawValue,
            "log-level": "info"
        ]
        return WebSocketResponse(id: request.id, status: "ok", data: data, error: nil)
    }

    private func handlePutConfigs(_ request: WebSocketRequest) async -> WebSocketResponse {
        // Config update not implemented in this version
        return WebSocketResponse(id: request.id, status: "ok", data: nil, error: nil)
    }

    private func handleGetProxies(_ request: WebSocketRequest) async -> WebSocketResponse {
        var proxies: [String: [String: Any]] = [:]

        // Add direct and reject
        proxies["DIRECT"] = ["name": "DIRECT", "type": "Direct", "history": []]
        proxies["REJECT"] = ["name": "REJECT", "type": "Reject", "history": []]

        // Add configured proxies
        for proxy in config.proxies {
            proxies[proxy.name] = [
                "name": proxy.name,
                "type": proxyTypeString(proxy.kind),
                "server": proxy.server,
                "port": proxy.port,
                "history": []
            ]
        }

        // Add proxy groups
        for group in config.proxyGroups {
            let currentSelection = groupSelections[group.id] ?? group.proxies.first ?? "DIRECT"
            proxies[group.id] = [
                "name": group.id,
                "type": groupTypeString(group.kind),
                "now": currentSelection,
                "all": group.proxies,
                "history": []
            ]
        }

        return WebSocketResponse(id: request.id, status: "ok", data: ["proxies": proxies], error: nil)
    }

    private func handleGetProxy(_ request: WebSocketRequest) async -> WebSocketResponse {
        let name = String(request.path.dropFirst("/proxies/".count))

        // Check if it's a group
        if let group = config.proxyGroups.first(where: { $0.id == name }) {
            let currentSelection = groupSelections[name] ?? group.proxies.first ?? "DIRECT"
            let history = group.proxies.compactMap { proxyName in
                delayCache[proxyName]?.history.last.map { entry -> [String: Any] in
                    ["time": entry.time, "delay": entry.delay]
                }
            }

            var proxyDetails: [String: [String: Any]] = [:]
            for proxyName in group.proxies {
                if let node = config.proxies.first(where: { $0.name == proxyName }) {
                    let delayInfo = delayCache[proxyName]
                    proxyDetails[proxyName] = [
                        "name": proxyName,
                        "type": proxyTypeString(node.kind),
                        "server": node.server,
                        "port": node.port,
                        "history": delayInfo?.history.map { ["time": $0.time, "delay": $0.delay] } ?? []
                    ]
                } else if proxyName == "DIRECT" {
                    proxyDetails[proxyName] = ["name": "DIRECT", "type": "Direct", "history": []]
                } else if proxyName == "REJECT" {
                    proxyDetails[proxyName] = ["name": "REJECT", "type": "Reject", "history": []]
                }
            }

            return WebSocketResponse(
                id: request.id,
                status: "ok",
                data: [
                    "name": name,
                    "type": groupTypeString(group.kind),
                    "now": currentSelection,
                    "all": group.proxies,
                    "history": history,
                    "proxies": proxyDetails
                ],
                error: nil
            )
        }

        // It's a direct proxy node
        if let node = config.proxies.first(where: { $0.name == name }) {
            let delayInfo = delayCache[name]
            return WebSocketResponse(
                id: request.id,
                status: "ok",
                data: [
                    "name": name,
                    "type": proxyTypeString(node.kind),
                    "server": node.server,
                    "port": node.port,
                    "history": delayInfo?.history.map { ["time": $0.time, "delay": $0.delay] } ?? []
                ],
                error: nil
            )
        }

        // DIRECT / REJECT
        if name == "DIRECT" {
            return WebSocketResponse(id: request.id, status: "ok", data: ["name": "DIRECT", "type": "Direct", "history": []], error: nil)
        }
        if name == "REJECT" {
            return WebSocketResponse(id: request.id, status: "ok", data: ["name": "REJECT", "type": "Reject", "history": []], error: nil)
        }

        return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Proxy not found: \(name)")
    }

    private func handlePutProxy(_ request: WebSocketRequest) async -> WebSocketResponse {
        // Parse request body for proxy selection
        // Expected format: { "name": "<group-name>" } in the URL path is the group,
        // and the body contains { "name": "<proxy-name>" } for the selection
        let groupName = String(request.path.dropFirst("/proxies/".count))

        guard let group = config.proxyGroups.first(where: { $0.id == groupName }) else {
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Group not found: \(groupName)")
        }

        guard group.kind == .select else {
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Only 'select' groups support proxy switching")
        }

        // Extract proxy name from request body
        let proxyName: String
        if let body = request.body,
           let nameValue = body["name"],
           let str = nameValue.value as? String {
            proxyName = str
        } else {
            // Fall back to the URL path after the group name (e.g., /proxies/GLOBAL?name=Proxy1)
            proxyName = ""
        }

        guard !proxyName.isEmpty, group.proxies.contains(proxyName) else {
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Proxy '\(proxyName)' not found in group '\(groupName)'")
        }

        // Update the group selection
        groupSelections[groupName] = proxyName

        return WebSocketResponse(
            id: request.id,
            status: "ok",
            data: [
                "name": groupName,
                "now": proxyName
            ],
            error: nil
        )
    }

    private func handleGetProxyDelay(_ request: WebSocketRequest) async -> WebSocketResponse {
        // Extract proxy name from path: /proxies/{name}/delay
        let basePath = String(request.path.dropFirst("/proxies/".count)) // "{name}/delay"
        let proxyName = String(basePath.dropLast("/delay".count)) // "{name}"

        // Parse query parameters from a full URL
        let testURLString = "http://localhost" + request.path
        let components = URLComponents(string: testURLString)
        let urlString = components?.queryItems?.first(where: { $0.name == "url" })?.value ?? "http://www.gstatic.com/generate_204"
        let timeout = Int(components?.queryItems?.first(where: { $0.name == "timeout" })?.value ?? "5000") ?? 5000

        guard let testURL = URL(string: urlString) else {
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Invalid test URL")
        }

        guard let node = config.proxies.first(where: { $0.name == proxyName }) else {
            return WebSocketResponse(id: request.id, status: "error", data: nil, error: "Proxy not found: \(proxyName)")
        }

        // Perform delay test
        let delayMs: Int
        if let healthChecker {
            let result = await healthChecker.check(node: node, testURL: testURL, timeout: .milliseconds(timeout))
            delayMs = result.latency ?? -1

            // Update delay cache
            let entry = DelayEntry(delay: result.alive ? (result.latency ?? -1) : -1)
            var history = delayCache[proxyName] ?? DelayHistory()
            history.history.append(entry)
            if history.history.count > 10 { history.history.removeFirst(history.history.count - 10) }
            history.delay = result.alive ? result.latency : nil
            delayCache[proxyName] = history
        } else {
            delayMs = -1
        }

        return WebSocketResponse(
            id: request.id,
            status: "ok",
            data: ["delay": delayMs],
            error: nil
        )
    }

    private func handleGetRules(_ request: WebSocketRequest) async -> WebSocketResponse {
        let rulesData = config.rules.map { rule -> [String: Any] in
            switch rule {
            case .domain(let d, let p):
                return ["type": "DOMAIN", "payload": d, "policy": policyString(p)]
            case .domainSuffix(let s, let p):
                return ["type": "DOMAIN-SUFFIX", "payload": s, "policy": policyString(p)]
            case .domainKeyword(let k, let p):
                return ["type": "DOMAIN-KEYWORD", "payload": k, "policy": policyString(p)]
            case .ipCIDR(let c, let p):
                return ["type": "IP-CIDR", "payload": c, "policy": policyString(p)]
            case .geoIP(let cc, let p):
                return ["type": "GEOIP", "payload": cc, "policy": policyString(p)]
            case .final(let p):
                return ["type": "MATCH", "payload": "", "policy": policyString(p)]
            default:
                return ["type": "UNKNOWN", "payload": "", "policy": "DIRECT"]
            }
        }
        return WebSocketResponse(id: request.id, status: "ok", data: ["rules": rulesData], error: nil)
    }

    private func handleGetConnections(_ request: WebSocketRequest) async -> WebSocketResponse {
        let status = await runtime.status()
        return WebSocketResponse(
            id: request.id,
            status: "ok",
            data: ["activeConnections": status.activeConnections],
            error: nil
        )
    }

    private func handleDeleteConnection(_ request: WebSocketRequest) async -> WebSocketResponse {
        let idStr = String(request.path.dropFirst("/connections/".count))
        if let uuid = UUID(uuidString: idStr) {
            await runtime.closeConnection(id: uuid)
        }
        return WebSocketResponse(id: request.id, status: "ok", data: nil, error: nil)
    }

    private func handleGetTraffic(_ request: WebSocketRequest) async -> WebSocketResponse {
        let status = await runtime.status()
        return WebSocketResponse(
            id: request.id,
            status: "ok",
            data: [
                "up": status.bytesUp,
                "down": status.bytesDown
            ],
            error: nil
        )
    }

    private func handleGetVersion(_ request: WebSocketRequest) -> WebSocketResponse {
        return WebSocketResponse(
            id: request.id,
            status: "ok",
            data: [
                "version": "1.0.0",
                "premium": false
            ],
            error: nil
        )
    }

    private func proxyTypeString(_ kind: ProxyKind) -> String {
        switch kind {
        case .http: return "Http"
        case .socks5: return "Socks5"
        case .shadowsocks: return "Shadowsocks"
        case .vmess: return "Vmess"
        case .vless: return "Vless"
        case .trojan: return "Trojan"
        case .hysteria2: return "Hysteria2"
        case .snell: return "Snell"
        case .tuic: return "TUIC"
        case .relay: return "Relay"
        }
    }

    private func groupTypeString(_ kind: ProxyGroupKind) -> String {
        switch kind {
        case .select: return "Selector"
        case .urlTest: return "URLTest"
        case .fallback: return "Fallback"
        case .loadBalance: return "LoadBalance"
        }
    }

    private func policyString(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .direct: return "DIRECT"
        case .reject: return "REJECT"
        case .proxyNode(let name): return name
        }
    }
}

// MARK: - Supporting Types

private struct WebSocketConnection {
    let id: UUID
    let nwConnection: NWConnection
}

private struct WebSocketRequest: Codable {
    let id: String?
    let method: String
    let path: String
    let body: [String: AnyCodable]?
}

/// WebSocketResponse only needs encoding (sending to client), not decoding
private struct WebSocketResponse: Encodable {
    let id: String?
    let status: String
    let data: [String: Any]?
    let error: String?

    init(id: String?, status: String, data: [String: Any]?, error: String?) {
        self.id = id
        self.status = status
        self.data = data
        self.error = error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(error, forKey: .error)

        // Encode data as JSON object
        if let data = data {
            var dataContainer = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
            for (key, value) in data {
                guard let codingKey = DynamicCodingKeys(stringValue: key) else { continue }
                try encodeAny(value, forKey: codingKey, to: &dataContainer)
            }
        }
    }

    private func encodeAny(_ value: Any, forKey key: DynamicCodingKeys, to container: inout KeyedEncodingContainer<DynamicCodingKeys>) throws {
        if let string = value as? String {
            try container.encode(string, forKey: key)
        } else if let int = value as? Int {
            try container.encode(int, forKey: key)
        } else if let bool = value as? Bool {
            try container.encode(bool, forKey: key)
        } else if let uint64 = value as? UInt64 {
            try container.encode(uint64, forKey: key)
        } else if let array = value as? [Any] {
            // Simplified: encode as string array
            let stringArray = array.map { String(describing: $0) }
            try container.encode(stringArray, forKey: key)
        } else if let dict = value as? [String: Any] {
            var nested = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: key)
            for (nestedKey, nestedValue) in dict {
                guard let codingKey = DynamicCodingKeys(stringValue: nestedKey) else { continue }
                try encodeAny(nestedValue, forKey: codingKey, to: &nested)
            }
        } else {
            try container.encode(String(describing: value), forKey: key)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, status, data, error
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
}

// Simple AnyCodable for request body
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encode(String(describing: value))
        }
    }
}
