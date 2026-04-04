import Foundation

public struct SubscriptionUpdate: Sendable {
    public let nodes: [ProxyNode]
    public let updatedAt: Date
    public let source: URL

    public init(nodes: [ProxyNode], updatedAt: Date = Date(), source: URL) {
        self.nodes = nodes
        self.updatedAt = updatedAt
        self.source = source
    }
}

public enum SubscriptionError: Error, Sendable {
    case invalidURL
    case fetchFailed(String)
    case parseFailed(String)
    case noNodes
}

public actor SubscriptionManager {
    private var subscriptions: [URL: SubscriptionUpdate]

    public init() {
        self.subscriptions = [:]
    }

    public func fetchSubscription(url: URL) async throws -> SubscriptionUpdate {
        guard let scheme = url.scheme, scheme == "https" || scheme == "http" else {
            throw SubscriptionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Clash Verge Rev/2.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SubscriptionError.fetchFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let nodes: [ProxyNode]

        if contentType.contains("yaml") || contentType.contains("text/plain") {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.hasPrefix("proxy") || text.contains("proxies:") {
                nodes = try parseClashYAML(text)
            } else {
                nodes = try parseBase64URIList(text)
            }
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            nodes = try parseBase64URIList(text)
        }

        guard !nodes.isEmpty else { throw SubscriptionError.noNodes }

        let update = SubscriptionUpdate(nodes: nodes, source: url)
        subscriptions[url] = update
        return update
    }

    public func getSubscription(_ url: URL) -> SubscriptionUpdate? {
        subscriptions[url]
    }

    public func allSubscriptions() -> [URL: SubscriptionUpdate] {
        subscriptions
    }

    private func parseBase64URIList(_ text: String) throws -> [ProxyNode] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SubscriptionError.parseFailed("empty content") }

        let decoded: String
        if let base64 = Data(base64Encoded: trimmed) {
            decoded = String(data: base64, encoding: .utf8) ?? trimmed
        } else {
            decoded = trimmed
        }

        var nodes: [ProxyNode] = []
        var index = 0
        for line in decoded.components(separatedBy: "\n") {
            let uri = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard uri.hasPrefix("ss://") || uri.hasPrefix("vmess://") ||
                  uri.hasPrefix("vless://") || uri.hasPrefix("trojan://") else { continue }
            if let node = ProxyURIParser.parse(uri) {
                nodes.append(ProxyNode(
                    name: node.name.isEmpty ? "node-\(index)" : node.name,
                    kind: node.kind, server: node.server, port: node.port,
                    cipher: node.cipher, password: node.password
                ))
                index += 1
            }
        }
        return nodes
    }

    private func parseClashYAML(_ yaml: String) throws -> [ProxyNode] {
        do {
            let (config, _) = try ClashConfigParser.parse(yaml: yaml)
            return config.proxies
        } catch {
            throw SubscriptionError.parseFailed(String(describing: error))
        }
    }
}

public enum ProxyURIParser {
    public struct ParsedProxy {
        let name: String
        let kind: ProxyKind
        let server: String
        let port: Int
        let cipher: String?
        let password: String?
    }

    public static func parse(_ uri: String) -> ParsedProxy? {
        guard let (rest, fragment) = extractFragment(uri) else { return nil }

        if rest.hasPrefix("ss://") { return parseSS(rest.dropFirst(5), fragment: fragment) }
        if rest.hasPrefix("vmess://") { return parseVMess(rest.dropFirst(8), fragment: fragment) }
        if rest.hasPrefix("vless://") { return parseVLESS(rest.dropFirst(8), fragment: fragment) }
        if rest.hasPrefix("trojan://") { return parseTrojan(rest.dropFirst(9), fragment: fragment) }
        return nil
    }

    private static func extractFragment(_ uri: String) -> (String, String)? {
        guard let hashIdx = uri.firstIndex(of: "#") else { return (uri, "") }
        let rest = String(uri[..<hashIdx])
        let fragment = String(uri[uri.index(after: hashIdx)...])
        return (rest, fragment)
    }

    private static func parseSS(_ body: Substring, fragment: String) -> ParsedProxy? {
        let str = String(body)
        let serverAndParams: String
        var method = ""
        var password = ""

        if let atIdx = str.firstIndex(of: "@") {
            let userInfo = String(str[..<atIdx])
            serverAndParams = String(str[str.index(after: atIdx)...])
            if let base64Data = Data(base64Encoded: userInfo.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
               let decoded = String(data: base64Data, encoding: .utf8),
               let colonIdx = decoded.firstIndex(of: ":") {
                method = String(decoded[..<colonIdx])
                password = String(decoded[decoded.index(after: colonIdx)...])
            }
        } else {
            if let base64Data = Data(base64Encoded: str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
               let decoded = String(data: base64Data, encoding: .utf8),
               let atIdx = decoded.firstIndex(of: "@") {
                let userInfo = String(decoded[..<atIdx])
                serverAndParams = String(decoded[decoded.index(after: atIdx)...])
                if let colonIdx = userInfo.firstIndex(of: ":") {
                    method = String(userInfo[..<colonIdx])
                    password = String(userInfo[userInfo.index(after: colonIdx)...])
                }
            } else {
                return nil
            }
        }

        guard let colonIdx = serverAndParams.firstIndex(of: ":") else { return nil }
        let host = String(serverAndParams[..<colonIdx])
        let portStr = String(serverAndParams[serverAndParams.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .shadowsocks, server: host, port: port, cipher: method, password: password)
    }

    private static func parseVMess(_ body: Substring, fragment: String) -> ParsedProxy? {
        guard let base64Data = Data(base64Encoded: String(body).padding(toLength: ((String(body).count + 3) / 4) * 4, withPad: "=", startingAt: 0)),
              let decoded = String(data: base64Data, encoding: .utf8) else { return nil }

        guard let data = decoded.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let host = json["add"] as? String,
              let port = json["port"] as? Int else { return nil }

        return ParsedProxy(
            name: json["ps"] as? String ?? fragment,
            kind: .vmess, server: host, port: port,
            cipher: json["scy"] as? String,
            password: json["id"] as? String
        )
    }

    private static func parseVLESS(_ body: Substring, fragment: String) -> ParsedProxy? {
        let str = String(body)
        guard let atIdx = str.firstIndex(of: "@") else { return nil }
        let uuid = String(str[..<atIdx])
        let serverAndPort = String(str[str.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .vless, server: host, port: port, cipher: nil, password: uuid)
    }

    private static func parseTrojan(_ body: Substring, fragment: String) -> ParsedProxy? {
        let str = String(body)
        guard let atIdx = str.firstIndex(of: "@") else { return nil }
        let password = String(str[..<atIdx])
        let serverAndPort = String(str[str.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .trojan, server: host, port: port, cipher: nil, password: password)
    }
}
