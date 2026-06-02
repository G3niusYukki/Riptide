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
}
