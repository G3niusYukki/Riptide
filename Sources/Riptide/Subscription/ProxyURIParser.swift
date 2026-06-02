import Foundation

/// Parser for proxy URIs (ss://, vmess://, vless://, trojan://)
public enum ProxyURIParser {
    public struct ParsedProxy {
        public let name: String
        public let kind: ProxyKind
        public let server: String
        public let port: Int
        public let cipher: String?
        public let password: String?

        public init(name: String, kind: ProxyKind, server: String, port: Int, cipher: String? = nil, password: String? = nil) {
            self.name = name
            self.kind = kind
            self.server = server
            self.port = port
            self.cipher = cipher
            self.password = password
        }
    }

    public static func parse(_ uri: String) -> ParsedProxy? {
        guard let (rest, fragment) = extractFragment(uri) else { return nil }

        if rest.hasPrefix("ss://") { return parseSS(String(rest.dropFirst(5)), fragment: fragment) }
        if rest.hasPrefix("vmess://") { return parseVMess(String(rest.dropFirst(8)), fragment: fragment) }
        if rest.hasPrefix("vless://") { return parseVLESS(String(rest.dropFirst(8)), fragment: fragment) }
        if rest.hasPrefix("trojan://") { return parseTrojan(String(rest.dropFirst(9)), fragment: fragment) }
        if rest.hasPrefix("hysteria2://") { return parseHysteria2(String(rest.dropFirst(12)), fragment: fragment) }
        if rest.hasPrefix("tuic://") { return parseTUIC(String(rest.dropFirst(7)), fragment: fragment) }
        return nil
    }

    private static func extractFragment(_ uri: String) -> (String, String)? {
        guard let hashIdx = uri.firstIndex(of: "#") else { return (uri, "") }
        let rest = String(uri[..<hashIdx])
        let fragment = String(uri[uri.index(after: hashIdx)...])
        return (rest, fragment)
    }

    private static func parseSS(_ body: String, fragment: String) -> ParsedProxy? {
        let str = body
        let serverAndParams: String
        var method = ""
        var password = ""

        if let atIdx = str.firstIndex(of: "@") {
            let userInfo = String(str[..<atIdx])
            serverAndParams = String(str[str.index(after: atIdx)...])
            if let base64Data = decodeURLSafeBase64(userInfo),
               let decoded = String(data: base64Data, encoding: .utf8),
               let colonIdx = decoded.firstIndex(of: ":") {
                method = String(decoded[..<colonIdx])
                password = String(decoded[decoded.index(after: colonIdx)...])
            }
        } else {
            if let base64Data = decodeURLSafeBase64(str),
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

        guard let colonIdx = serverAndParams.lastIndex(of: ":") else { return nil }
        let host = String(serverAndParams[..<colonIdx])
        let portStr = String(serverAndParams[serverAndParams.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .shadowsocks, server: host, port: port, cipher: method, password: password)
    }

    private static func parseVMess(_ body: String, fragment: String) -> ParsedProxy? {
        let padded = body.padding(toLength: ((body.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        guard let base64Data = Data(base64Encoded: padded),
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

    private static func parseVLESS(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let uuid = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .vless, server: host, port: port, cipher: nil, password: uuid)
    }

    private static func parseTrojan(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let password = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .trojan, server: host, port: port, cipher: nil, password: password)
    }

    private static func parseHysteria2(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let password = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<colonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: colonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .hysteria2, server: host, port: port, cipher: nil, password: password)
    }

    private static func parseTUIC(_ body: String, fragment: String) -> ParsedProxy? {
        guard let atIdx = body.firstIndex(of: "@") else { return nil }
        let userInfo = String(body[..<atIdx])
        let serverAndPort = String(body[body.index(after: atIdx)...])

        guard let colonIdx = userInfo.firstIndex(of: ":") else { return nil }
        let uuid = String(userInfo[..<colonIdx])

        guard let portColonIdx = serverAndPort.lastIndex(of: ":") else { return nil }
        let host = String(serverAndPort[..<portColonIdx])
        let portStr = String(serverAndPort[serverAndPort.index(after: portColonIdx)...])
        let port = Int(portStr.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? "") ?? 443

        return ParsedProxy(name: fragment, kind: .tuic, server: host, port: port, cipher: nil, password: uuid)
    }

    // MARK: - Helpers

    /// Decode a URL-safe base64 string (RFC 4648 §5: '-' for '+', '_' for '/',
    /// optional padding). Adds `=` padding before decoding.
    private static func decodeURLSafeBase64(_ string: String) -> Data? {
        let standard = string.replacingOccurrences(of: "-", with: "+")
                             .replacingOccurrences(of: "_", with: "/")
        let padded = standard.padding(toLength: ((standard.count + 3) / 4) * 4,
                                      withPad: "=", startingAt: 0)
        return Data(base64Encoded: padded)
    }
}
