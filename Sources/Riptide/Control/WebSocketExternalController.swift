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
public actor WebSocketExternalController {
    private let runtime: LiveTunnelRuntime
    private let config: RiptideConfig
    private var listener: NWListener?
    private var activeConnections: [UUID: WebSocketConnection] = [:]

    public init(runtime: LiveTunnelRuntime, config: RiptideConfig) {
        self.runtime = runtime
        self.config = config
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
            proxies[group.id] = [
                "name": group.id,
                "type": groupTypeString(group.kind),
                "now": group.proxies.first ?? "DIRECT",
                "all": group.proxies,
                "history": []
            ]
        }

        return WebSocketResponse(id: request.id, status: "ok", data: ["proxies": proxies], error: nil)
    }

    private func handleGetProxy(_ request: WebSocketRequest) async -> WebSocketResponse {
        let name = String(request.path.dropFirst("/proxies/".count))
        // Return proxy details (simplified)
        return WebSocketResponse(id: request.id, status: "ok", data: ["name": name], error: nil)
    }

    private func handlePutProxy(_ request: WebSocketRequest) async -> WebSocketResponse {
        // Proxy selection for groups (simplified)
        return WebSocketResponse(id: request.id, status: "ok", data: nil, error: nil)
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
        case .relay: return "Relay"
        case .tuic: return "Tuic"
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
