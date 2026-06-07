//! Share URI parser
//!
//! Parses proxy share links (ss://, trojan://, vless://, vmess://) into mihomo-compatible
//! ClashRawProxy structs, so users can import individual nodes via a share link.

use crate::config::parser::ClashRawProxy;
use std::collections::HashMap;

/// Errors that can occur when parsing a share URI
#[derive(Debug, thiserror::Error)]
pub enum UriParseError {
    #[error("Invalid URI scheme: {0}")]
    InvalidScheme(String),
    #[error("Invalid base64 encoding: {0}")]
    Base64Error(String),
    #[error("Missing required field: {0}")]
    MissingField(String),
    #[error("Invalid port: {0}")]
    InvalidPort(String),
    #[error("URL parse error: {0}")]
    UrlParseError(String),
    #[error("Unsupported protocol: {0}")]
    UnsupportedProtocol(String),
}

/// Parse a share URI into a ClashRawProxy
pub fn parse_share_uri(uri: &str) -> Result<ClashRawProxy, UriParseError> {
    let uri = uri.trim();

    if let Some(rest) = uri.strip_prefix("ss://") {
        parse_shadowsocks(rest)
    } else if let Some(rest) = uri.strip_prefix("trojan://") {
        parse_trojan(rest)
    } else if let Some(rest) = uri.strip_prefix("vless://") {
        parse_vless(rest)
    } else if let Some(rest) = uri.strip_prefix("vmess://") {
        parse_vmess(rest)
    } else     if let Some(rest) = uri.strip_prefix("hysteria2://") {
        parse_hysteria2(rest)
    } else if let Some(rest) = uri.strip_prefix("tuic://") {
        parse_tuic(rest)
    } else {
        Err(UriParseError::InvalidScheme(
            uri.chars()
                .take_while(|c| *c != ':')
                .collect::<String>(),
        ))
    }
}

/// Base64 decode helper (supports both standard and URL-safe Base64)
fn decode_base64(s: &str) -> Result<String, UriParseError> {
    let s = s
        .replace('-', "+")
        .replace('_', "/");

    // Pad if needed
    let padded = match s.len() % 4 {
        2 => format!("{}==", s),
        3 => format!("{}=", s),
        _ => s,
    };

    let bytes = base64_decode_bytes(&padded)
        .ok_or_else(|| UriParseError::Base64Error("Failed to decode base64".into()))?;
    String::from_utf8(bytes).map_err(|e| UriParseError::Base64Error(e.to_string()))
}

/// Simple base64 decode without external crate
fn base64_decode_bytes(input: &str) -> Option<Vec<u8>> {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = Vec::new();
    let mut buffer = 0u32;
    let mut bits = 0;

    for ch in input.chars() {
        if ch == '=' {
            break;
        }
        let idx = CHARS.iter().position(|&c| c == ch as u8)?;
        buffer = (buffer << 6) | idx as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            result.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    Some(result)
}

/// Parse Shadowsocks URI. Two shapes are accepted:
///
/// - SIP002 (modern): `ss://BASE64(method:password)@server:port[#name]`.
///   The base64 part contains no `@` (the base64 alphabet is
///   `[A-Za-z0-9+/=]`-style), so we can detect this format by spotting
///   a literal `@` in the undecoded remainder.
/// - Legacy: `ss://BASE64(method:password@server:port)[#name]`. The
///   base64 part is the *whole* `method:password@server:port` blob and
///   we split it on the *last* `@` after decoding.
fn parse_shadowsocks(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let (encoded, name) = split_fragment(rest);

    // SIP002 detection: a literal `@` in the undecoded remainder means
    // the base64 part is everything before it. We deliberately check
    // `find('@')` (not `rfind`) because the SIP002 grammar has exactly
    // one `@` and any extra `@` in a base64 blob would be a malformed
    // URL anyway.
    if let Some(at) = encoded.find('@') {
        let userinfo_b64 = &encoded[..at];
        let server_port = &encoded[at + 1..];
        let userinfo = decode_base64(userinfo_b64)?;
        return parse_ss_userinfo_and_server(&userinfo, server_port, name);
    }

    // Legacy: base64-encode the whole `method:password@server:port` blob.
    let decoded = decode_base64(encoded)?;
    let (userinfo, server_port) = decoded
        .rfind('@')
        .map(|at| (decoded[..at].to_string(), decoded[at + 1..].to_string()))
        .ok_or_else(|| UriParseError::UrlParseError("Invalid SS URI format".into()))?;
    parse_ss_userinfo_and_server(&userinfo, &server_port, name)
}

/// Build a `ClashRawProxy` from an already-decoded SS userinfo and the
/// undecoded `server:port` tail. Shared between the SIP002 and legacy
/// branches of `parse_shadowsocks`.
fn parse_ss_userinfo_and_server(
    userinfo: &str,
    server_port: &str,
    name: Option<String>,
) -> Result<ClashRawProxy, UriParseError> {
    let (method, password) = userinfo
        .split_once(':')
        .ok_or_else(|| UriParseError::MissingField("cipher:password".into()))?;
    let (server, port_str) = server_port
        .split_once(':')
        .ok_or_else(|| UriParseError::MissingField("server:port".into()))?;
    let port: u16 = port_str
        .parse()
        .map_err(|_| UriParseError::InvalidPort(port_str.into()))?;
    Ok(ClashRawProxy {
        name: name.unwrap_or_else(|| format!("SS-{}-{}", server, port)),
        server: Some(server.to_string()),
        port: Some(port),
        proxy_type: Some("ss".into()),
        cipher: Some(method.to_string()),
        password: Some(password.to_string()),
        udp: Some(true),
        ..Default::default()
    })
}

/// Parse Trojan URI: trojan://password@server:port?query#name
fn parse_trojan(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let (body, name) = split_fragment(rest);

    let without_scheme = body;
    let (password_raw, rest) = without_scheme
        .split_once('@')
        .ok_or_else(|| UriParseError::MissingField("password@server:port".into()))?;

    // The serializer percent-encodes the password before emitting the
    // URI, so we must decode it back to get the original plaintext
    // (e.g. `p%40ss` → `p@ss`, `pwd%21` → `pwd!`).
    let password = urlencoding::decode(password_raw)
        .map(|s| s.into_owned())
        .unwrap_or_else(|_| password_raw.to_string());

    let (host_port, query) = rest.split_once('?').unwrap_or((rest, ""));

    let (server, port_str) = host_port
        .split_once(':')
        .ok_or_else(|| UriParseError::MissingField("server:port".into()))?;
    let port: u16 = port_str
        .parse()
        .map_err(|_| UriParseError::InvalidPort(port_str.into()))?;

    let params = parse_query_params(query);
    let sni = params.get("sni").cloned();
    let skip_cert_verify = params
        .get("allowInsecure")
        .map(|v| v == "1")
        .or_else(|| params.get("allow_insecure").map(|v| v == "1"));

    Ok(ClashRawProxy {
        name: name.unwrap_or_else(|| format!("Trojan-{}-{}", server, port)),
        server: Some(server.to_string()),
        port: Some(port),
        proxy_type: Some("trojan".into()),
        password: Some(password),
        sni: sni.or_else(|| Some(server.to_string())),
        skip_cert_verify,
        udp: Some(true),
        ..Default::default()
    })
}

/// Parse VLESS URI: vless://uuid@server:port?query#name
fn parse_vless(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let (body, name) = split_fragment(rest);

    let (uuid, host_rest) = body
        .split_once('@')
        .ok_or_else(|| UriParseError::MissingField("uuid@server:port".into()))?;

    let (host_port, query) = host_rest.split_once('?').unwrap_or((host_rest, ""));

    let (server, port_str) = host_port
        .split_once(':')
        .ok_or_else(|| UriParseError::MissingField("server:port".into()))?;
    let port: u16 = port_str
        .parse()
        .map_err(|_| UriParseError::InvalidPort(port_str.into()))?;

    let params = parse_query_params(query);
    let security = params.get("security").cloned();
    let sni = params.get("sni").cloned();
    let flow = params.get("flow").cloned();
    let fingerprint = params.get("fp").cloned();
    let pbk = params.get("pbk").cloned();
    let sid = params.get("sid").cloned();

    // Determine network type
    let network = match params.get("type").map(|s| s.as_str()) {
        Some("ws") => Some("ws".into()),
        Some("grpc") => Some("grpc".into()),
        Some("h2") => Some("h2".into()),
        Some("quic") => Some("quic".into()),
        _ => None,
    };

    Ok(ClashRawProxy {
        name: name.unwrap_or_else(|| format!("VLESS-{}-{}", server, port)),
        server: Some(server.to_string()),
        port: Some(port),
        proxy_type: Some("vless".into()),
        uuid: Some(uuid.to_string()),
        network,
        security,
        sni,
        flow,
        fingerprint,
        pbk,
        sid,
        udp: Some(true),
        ..Default::default()
    })
}

/// Parse VMess URI: vmess://base64(json_object)
fn parse_vmess(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let decoded = decode_base64(rest)?;

    #[derive(serde::Deserialize)]
    struct VmessConfig {
        ps: Option<String>,
        add: String,
        port: serde_json::Value,
        id: String,
        aid: Option<serde_json::Value>,
        net: Option<String>,
        #[serde(rename = "type")]
        scy_type: Option<String>,
        host: Option<String>,
        path: Option<String>,
        tls: Option<String>,
        sni: Option<String>,
        fp: Option<String>,
    }

    let config: VmessConfig =
        serde_json::from_str(&decoded).map_err(|e| UriParseError::UrlParseError(e.to_string()))?;

    let port = match &config.port {
        serde_json::Value::Number(n) => n.as_u64().unwrap_or(0) as u16,
        serde_json::Value::String(s) => s.parse().unwrap_or(0),
        _ => return Err(UriParseError::InvalidPort("port not a number".into())),
    };

    let network = match config.net.as_deref() {
        Some("ws") => Some("ws".into()),
        Some("grpc") => Some("grpc".into()),
        Some("h2") => Some("h2".into()),
        Some("quic") => Some("quic".into()),
        _ => None,
    };

    let tls = match config.tls.as_deref() {
        Some("tls") => Some(true),
        _ => None,
    };

    Ok(ClashRawProxy {
        name: config
            .ps
            .unwrap_or_else(|| format!("VMess-{}-{}", config.add, port)),
        server: Some(config.add),
        port: Some(port),
        proxy_type: Some("vmess".into()),
        uuid: Some(config.id),
        alter_id: config.aid.and_then(|v| v.as_u64().map(|n| n as u32)),
        cipher: config.scy_type,
        network,
        ws_path: config.path,
        ws_headers: config.host.map(|h| {
            let mut m = HashMap::new();
            m.insert("Host".into(), h);
            m
        }),
        tls,
        sni: config.sni,
        fingerprint: config.fp,
        udp: Some(true),
        ..Default::default()
    })
}

/// Parse Hysteria2 URI: hysteria2://password@server:port?query#name
fn parse_hysteria2(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let (body, name) = split_fragment(rest);

    let (password_raw, host_rest) = body
        .split_once('@')
        .ok_or_else(|| UriParseError::MissingField("password@server:port".into()))?;

    // Percent-decode the password for symmetry with `parse_trojan` and
    // `parse_tuic`. The serializer encodes it before emit, and a
    // password like `p@ss` would otherwise round-trip as `p%40ss`.
    let password = urlencoding::decode(password_raw)
        .map(|s| s.into_owned())
        .unwrap_or_else(|_| password_raw.to_string());

    let (host_port, query) = host_rest.split_once('?').unwrap_or((host_rest, ""));

    let (server, port_str) = host_port
        .split_once(':')
        .ok_or_else(|| UriParseError::MissingField("server:port".into()))?;
    let port: u16 = port_str
        .parse()
        .map_err(|_| UriParseError::InvalidPort(port_str.into()))?;

    let params = parse_query_params(query);
    let sni = params.get("sni").cloned();
    let skip_cert_verify = params.get("insecure").map(|v| v == "1");

    Ok(ClashRawProxy {
        name: name.unwrap_or_else(|| format!("Hy2-{}-{}", server, port)),
        server: Some(server.to_string()),
        port: Some(port),
        proxy_type: Some("hysteria2".into()),
        password: Some(password),
        sni,
        skip_cert_verify,
        udp: Some(true),
        ..Default::default()
    })
}

/// Parse TUIC URI: tuic://uuid:password@server:port?query#name
fn parse_tuic(rest: &str) -> Result<ClashRawProxy, UriParseError> {
    let (body, name) = split_fragment(rest);
    let (userinfo, host_rest) = body.split_once('@')
        .ok_or_else(|| UriParseError::MissingField("uuid:password@server:port".into()))?;
    let (uuid, password_raw) = userinfo.split_once(':')
        .ok_or_else(|| UriParseError::MissingField("uuid:password".into()))?;
    // The serializer percent-encodes the password before emitting the
    // URI, so decode it back. We try the full URL decode first; if that
    // fails (e.g. legacy share links that pre-date the encoding), fall
    // back to the raw value.
    let password = urlencoding::decode(password_raw)
        .map(|s| s.into_owned())
        .unwrap_or_else(|_| password_raw.to_string());
    let (host_port, query) = host_rest.split_once('?').unwrap_or((host_rest, ""));
    let (server, port_str) = host_port.split_once(':')
        .ok_or_else(|| UriParseError::MissingField("server:port".into()))?;
    let port: u16 = port_str.parse().map_err(|_| UriParseError::InvalidPort(port_str.into()))?;
    let params = parse_query_params(query);
    let sni = params.get("sni").cloned();
    let skip_cert_verify = params.get("allowInsecure").map(|v| v == "1");
    Ok(ClashRawProxy {
        name: name.unwrap_or_else(|| format!("TUIC-{}-{}", server, port)),
        server: Some(server.to_string()),
        port: Some(port),
        proxy_type: Some("tuic".into()),
        uuid: Some(uuid.to_string()),
        password: Some(password),
        sni,
        skip_cert_verify,
        udp: Some(true),
        ..Default::default()
    })
}

/// Split URI on '#' to separate name fragment
fn split_fragment(s: &str) -> (&str, Option<String>) {
    if let Some(idx) = s.rfind('#') {
        let name = urlencoding::decode(&s[idx + 1..])
            .ok()
            .map(|s| s.into_owned());
        (&s[..idx], name)
    } else {
        (s, None)
    }
}

/// Parse query string parameters
fn parse_query_params(query: &str) -> HashMap<String, String> {
    let mut params = HashMap::new();
    if query.is_empty() {
        return params;
    }
    for part in query.split('&') {
        if let Some((k, v)) = part.split_once('=') {
            params.insert(
                k.to_string(),
                urlencoding::decode(v)
                    .map(|s| s.into_owned())
                    .unwrap_or_else(|_| v.to_string()),
            );
        }
    }
    params
}

// Need to add `Default` for ClashRawProxy since we use it in convenience constructors.
// The derive is already on ClashRawProxy in parser.rs.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_empty() {
        assert!(parse_share_uri("").is_err());
    }

    #[test]
    fn test_invalid_scheme() {
        assert!(parse_share_uri("http://example.com").is_err());
    }

    #[test]
    fn test_parse_trojan() {
        let result = parse_share_uri("trojan://abc123@1.2.3.4:443?sni=example.com#MyNode");
        assert!(result.is_ok());
        let proxy = result.unwrap();
        assert_eq!(proxy.proxy_type, Some("trojan".into()));
        assert_eq!(proxy.server, Some("1.2.3.4".into()));
        assert_eq!(proxy.port, Some(443));
        assert_eq!(proxy.name, "MyNode");
    }

    #[test]
    fn test_parse_vless() {
        let result = parse_share_uri(
            "vless://some-uuid@5.6.7.8:8080?type=ws&security=reality&sni=example.com#VLNode",
        );
        assert!(result.is_ok());
        let proxy = result.unwrap();
        assert_eq!(proxy.proxy_type, Some("vless".into()));
        assert_eq!(proxy.network, Some("ws".into()));
        assert_eq!(proxy.name, "VLNode");
    }

    #[test]
    fn test_parse_hysteria2() {
        let result = parse_share_uri("hysteria2://pass123@9.9.9.9:30000?sni=example.com#HyNode");
        assert!(result.is_ok());
        let proxy = result.unwrap();
        assert_eq!(proxy.proxy_type, Some("hysteria2".into()));
        assert_eq!(proxy.port, Some(30000));
    }

    #[test]
    fn test_parse_shadowsocks() {
        // Base64 encode "aes-256-gcm:password" = YWVzLTI1Ni1nY206cGFzc3dvcmQ=
        let b64 = "YWVzLTI1Ni1nY206cGFzc3dvcmQ";
        let result =
            parse_share_uri(&format!("ss://{}@1.2.3.4:8388#SSNode", b64));
        assert!(result.is_ok());
        let proxy = result.unwrap();
        assert_eq!(proxy.proxy_type, Some("ss".into()));
        assert_eq!(proxy.cipher, Some("aes-256-gcm".into()));
        assert_eq!(proxy.password, Some("password".into()));
    }
}
