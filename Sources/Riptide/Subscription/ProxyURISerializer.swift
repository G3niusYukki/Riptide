import Foundation

/// Serializer for proxy share URIs.
/// Complements `ProxyURIParser` (URI → ProxyNode) by going the other
/// direction (ProxyNode → URI). Returns `nil` for kinds without an
/// industry-standard share URI format.
public enum ProxyURISerializer {
    public static func makeURI(from node: ProxyNode) -> String? {
        switch node.kind {
        case .shadowsocks:
            return makeSSURI(node)
        case .vless:
            return makeVLESSURI(node)
        case .trojan:
            return makeTrojanURI(node)
        default:
            return nil
        }
    }

    // MARK: - SS
    // Format: ss://BASE64(method:password)@host:port#name
    // Base64 is URL-safe (RFC 4648 §5: '-' for '+', '_' for '/'), no padding.
    private static func makeSSURI(_ node: ProxyNode) -> String? {
        guard let password = node.password,
              let cipher = node.cipher,
              node.port > 0,
              !node.server.isEmpty else { return nil }
        let creds = "\(cipher):\(password)"
        guard let data = creds.data(using: .utf8) else { return nil }
        let encoded = urlSafeBase64(data)
        let name = urlFragmentEncode(node.name)
        return "ss://\(encoded)@\(node.server):\(node.port)#\(name)"
    }

    // MARK: - VLESS
    // Format: vless://UUID@host:port?KEY=VAL&KEY=VAL#name
    // Only emit non-nil query params.
    private static func makeVLESSURI(_ node: ProxyNode) -> String? {
        guard let uuid = node.uuid,
              node.port > 0,
              !node.server.isEmpty else { return nil }
        var query: [String] = []
        if let security = node.security, !security.isEmpty {
            query.append("security=\(security)")
        }
        if let sni = node.sni, !sni.isEmpty {
            query.append("sni=\(urlQueryValue(sni))")
        }
        if let alpn = node.alpn, !alpn.isEmpty {
            query.append("alpn=\(urlQueryValue(alpn.joined(separator: ",")))")
        }
        if let network = node.network, !network.isEmpty {
            query.append("type=\(network)")
        }
        if let wsPath = node.wsPath, !wsPath.isEmpty {
            query.append("path=\(urlQueryValue(wsPath))")
        }
        if let wsHost = node.wsHost, !wsHost.isEmpty {
            query.append("host=\(urlQueryValue(wsHost))")
        }
        if let flow = node.flow, !flow.isEmpty {
            query.append("flow=\(urlQueryValue(flow))")
        }
        let queryString = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        let name = urlFragmentEncode(node.name)
        return "vless://\(uuid)@\(node.server):\(node.port)\(queryString)#\(name)"
    }

    // MARK: - Trojan
    // Format: trojan://password@host:port?KEY=VAL#name
    private static func makeTrojanURI(_ node: ProxyNode) -> String? {
        guard let password = node.password,
              node.port > 0,
              !node.server.isEmpty else { return nil }
        var query: [String] = []
        if let sni = node.sni, !sni.isEmpty {
            query.append("sni=\(urlQueryValue(sni))")
        }
        if let alpn = node.alpn, !alpn.isEmpty {
            query.append("alpn=\(urlQueryValue(alpn.joined(separator: ",")))")
        }
        if node.skipCertVerify == true {
            query.append("allowInsecure=1")
        }
        let queryString = query.isEmpty ? "" : "?" + query.joined(separator: "&")
        let name = urlFragmentEncode(node.name)
        return "trojan://\(urlUserInfoEncode(password))@\(node.server):\(node.port)\(queryString)#\(name)"
    }

    // MARK: - Helpers

    /// Standard base64, then swap + → - and / → _ per RFC 4648 §5 (URL-safe).
    private static func urlSafeBase64(_ data: Data) -> String {
        let b64 = data.base64EncodedString()
        return b64.replacingOccurrences(of: "+", with: "-")
                  .replacingOccurrences(of: "/", with: "_")
                  .replacingOccurrences(of: "=", with: "")
    }

    /// Percent-encode per RFC 3986 for use inside a URI fragment.
    /// Preserves ASCII alphanumerics and `- _ . ~`, encodes everything else.
    private static func urlFragmentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    /// Percent-encode a value for use inside a URI query string.
    /// `&`, `=`, and `+` MUST be encoded so they don't break query parsing.
    private static func urlQueryValue(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    /// Percent-encode a value for use in the userinfo section of a URI
    /// (`scheme://USER:PASS@host`). Encodes everything except unreserved chars.
    private static func urlUserInfoEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
