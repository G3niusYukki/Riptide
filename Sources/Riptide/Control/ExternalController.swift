import Foundation
import Network

public struct APIResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public actor ExternalController {
    private let runtime: LiveTunnelRuntime
    private let config: RiptideConfig
    private var listener: NWListener?
    private var activeConnections: [UUID: ConnectionContext]
    private var requestLog: [APIRequestLog]
    private var currentMode: RuntimeMode
    private let maxLogs: Int = 1000

    private struct ConnectionContext: Sendable {
        let id: UUID
        let target: ConnectionTarget
        let policy: RoutingPolicy
        let startTime: ContinuousClock.Instant
    }

    public struct APIRequestLog: Sendable {
        public let id: UUID
        public let target: ConnectionTarget
        public let policy: String
        public let startTime: ContinuousClock.Instant
        public let endTime: ContinuousClock.Instant?
        public var bytesUp: UInt64 = 0
        public var bytesDown: UInt64 = 0

        public init(id: UUID, target: ConnectionTarget, policy: String) {
            self.id = id
            self.target = target
            self.policy = policy
            self.startTime = ContinuousClock.now
            self.endTime = nil
        }
    }

    public init(runtime: LiveTunnelRuntime, config: RiptideConfig) {
        self.runtime = runtime
        self.config = config
        self.activeConnections = [:]
        self.requestLog = []
        self.currentMode = .systemProxy
    }

    public func start(host: String = "127.0.0.1", port: UInt16 = 9090) async throws -> String {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TransportError.dialFailed("invalid port")
        }

        let listener = try NWListener(using: .tcp, on: nwPort)

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleRequest(connection) }
        }

        listener.start(queue: .global())
        self.listener = listener
        return "\(host):\(port)"
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    public func snapshot(mode: RuntimeMode) async -> TunnelStatusSnapshot {
        currentMode = mode
        let status = await runtime.status()
        return TunnelStatusSnapshot(
            state: .stopped,
            activeProfileName: nil,
            bytesUp: status.bytesUp,
            bytesDown: status.bytesDown,
            activeConnections: status.activeConnections,
            lastError: nil
        )
    }

    private func handleRequest(_ connection: NWConnection) async {
        connection.start(queue: .global())

        var buffer = Data()
        while true {
            do {
                let chunk = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume(returning: data ?? Data())
                        }
                    }
                }
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)

                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = Data(buffer[..<range.lowerBound])
                    guard let headerText = String(data: headerData, encoding: .utf8) else { return }
                    let lines = headerText.components(separatedBy: "\r\n")
                    guard let requestLine = lines.first else { return }

                    let parts = requestLine.split(separator: " ")
                    guard parts.count >= 2 else { return }
                    let method = String(parts[0])
                    let path = String(parts[1])

                    let contentLength = lines.compactMap { line -> Int? in
                        guard line.lowercased().hasPrefix("content-length:") else { return nil }
                        return Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces))
                    }.first ?? 0

                    let bodyStart = range.upperBound
                    var body = Data()
                    if bodyStart + contentLength <= buffer.count {
                        body = Data(buffer[bodyStart..<(bodyStart + contentLength)])
                        buffer = Data(buffer.dropFirst(bodyStart + contentLength))
                    }

                    let response = await routeRequest(method: method, path: path, body: body)
                    let httpResponse = "HTTP/1.1 \(response.statusCode) OK\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\n\r\n"
                    var responseData = Data(httpResponse.utf8)
                    responseData.append(response.body)

                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        connection.send(content: responseData, completion: .contentProcessed { error in
                            if let error { cont.resume(throwing: error) }
                            else { cont.resume() }
                        })
                    }
                }
            } catch {
                return
            }
        }
    }

    private func routeRequest(method: String, path: String, body: Data) async -> APIResponse {
        switch (method, path) {
        case ("GET", "/version"):
            return json(200, ["version": "1.0.0", "name": "Riptide"])

        case ("GET", "/configs"):
            return json(200, [
                "mode": config.mode.rawValue,
                "proxy-count": config.proxies.count,
                "rule-count": config.rules.count
            ])

        case ("GET", "/proxies"):
            var proxies: [[String: Any]] = []
            for proxy in config.proxies {
                proxies.append([
                    "name": proxy.name,
                    "type": proxyKindString(proxy.kind),
                    "server": proxy.server,
                    "port": proxy.port
                ])
            }
            return json(200, ["proxies": proxies])

        case ("GET", "/rules"):
            var rules: [[String: Any]] = []
            for (index, rule) in config.rules.enumerated() {
                rules.append([
                    "index": index,
                    "type": ruleTypeString(rule),
                    "payload": rulePayload(rule)
                ])
            }
            return json(200, ["rules": rules])

        case ("GET", "/connections"):
            var conns: [[String: Any]] = []
            for (_, ctx) in activeConnections {
                conns.append([
                    "id": ctx.id.uuidString,
                    "target": "\(ctx.target.host):\(ctx.target.port)",
                    "policy": policyString(ctx.policy)
                ])
            }
            return json(200, ["connections": conns, "count": conns.count])

        case ("GET", "/traffic"):
            let status = await runtime.status()
            return json(200, [
                "up": status.bytesUp,
                "down": status.bytesDown
            ])

        case ("GET", "/logs"):
            var logs: [[String: Any]] = []
            for log in requestLog.suffix(50) {
                logs.append([
                    "id": log.id.uuidString,
                    "target": "\(log.target.host):\(log.target.port)",
                    "policy": log.policy
                ])
            }
            return json(200, ["logs": logs])

        default:
            return json(404, ["error": "not found"])
        }
    }

    private func json(_ statusCode: Int, _ value: Any) -> APIResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) else {
            return APIResponse(statusCode: 500, body: Data("{\"error\":\"serialization failed\"}".utf8))
        }
        return APIResponse(statusCode: statusCode, body: data)
    }

    private func proxyKindString(_ kind: ProxyKind) -> String {
        switch kind {
        case .http: return "HTTP"
        case .socks5: return "SOCKS5"
        case .shadowsocks: return "Shadowsocks"
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .hysteria2: return "Hysteria2"
        case .relay: return "Relay"
        }
    }

    private func ruleTypeString(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain: return "DOMAIN"
        case .domainSuffix: return "DOMAIN-SUFFIX"
        case .domainKeyword: return "DOMAIN-KEYWORD"
        case .ipCIDR: return "IP-CIDR"
        case .ipCIDR6: return "IP-CIDR6"
        case .srcIPCIDR: return "SRC-IP-CIDR"
        case .srcPort: return "SRC-PORT"
        case .dstPort: return "DST-PORT"
        case .processName: return "PROCESS-NAME"
        case .geoIP: return "GEOIP"
        case .ipASN: return "IP-ASN"
        case .geoSite: return "GEOSITE"
        case .ruleSet: return "RULE-SET"
        case .matchAll: return "MATCH"
        case .final: return "FINAL"
        }
    }

    private func rulePayload(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain(let d, _): return d
        case .domainSuffix(let s, _): return s
        case .domainKeyword(let k, _): return k
        case .ipCIDR(let c, _): return c
        case .ipCIDR6(let c, _): return c
        case .srcIPCIDR(let c, _): return c
        case .srcPort(let p, _): return "\(p)"
        case .dstPort(let p, _): return "\(p)"
        case .processName(let n, _): return n
        case .geoIP(let c, _): return c
        case .ipASN(let a, _): return "\(a)"
        case .geoSite(let c, let cat, _): return "\(c),\(cat)"
        case .ruleSet(let n, _): return n
        case .matchAll: return "*"
        case .final: return ""
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
