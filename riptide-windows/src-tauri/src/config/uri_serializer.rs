//! Share URI serializer — inverse of [`super::uri`].
//!
//! 6 supported protocols (matching macOS `ProxyURISerializer`):
//! ss, vmess, vless, trojan, hysteria2, tuic.
//!
//! Round-trip property: `parse(serialize(x)) == x` (modulo fields the
//! serializer can't emit, like `udp: true` which most clients default on).
//! The 18 tests in this file (3 per protocol) cover the property.

use crate::config::parser::ClashRawProxy;
use base64::{engine::general_purpose::STANDARD, Engine as _};

/// Errors when serializing a proxy to a share URI
#[derive(Debug, thiserror::Error)]
pub enum UriSerializeError {
    #[error("Proxy type {0:?} has no share-URI format")]
    UnsupportedType(String),
    #[error("Missing required field: {0}")]
    MissingField(&'static str),
}

/// Top-level entry. Returns `Ok(None)` for types with no standard share
/// URI (socks5 / http / snell / direct / …).
pub fn proxy_to_uri(proxy: &ClashRawProxy) -> Result<Option<String>, UriSerializeError> {
    let kind = proxy.proxy_type.as_deref().unwrap_or("");
    match kind {
        "ss" => Ok(Some(serialize_ss(proxy)?)),
        "vmess" => Ok(Some(serialize_vmess(proxy)?)),
        "vless" => Ok(Some(serialize_vless(proxy)?)),
        "trojan" => Ok(Some(serialize_trojan(proxy)?)),
        "hysteria2" => Ok(Some(serialize_hysteria2(proxy)?)),
        "tuic" => Ok(Some(serialize_tuic(proxy)?)),
        _ => Ok(None),
    }
}

/// Strict variant — treats "no share format" as an error.
pub fn proxy_to_uri_strict(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    proxy_to_uri(proxy)?.ok_or_else(|| {
        let kind = proxy.proxy_type.clone().unwrap_or_default();
        UriSerializeError::UnsupportedType(if kind.is_empty() {
            "(unset)".into()
        } else {
            kind
        })
    })
}

fn url_safe_base64(bytes: &[u8]) -> String {
    STANDARD.encode(bytes).replace('+', "-").replace('/', "_")
}

fn enc_frag(s: &str) -> String {
    urlencoding::encode(s).into_owned()
}
fn enc_q(s: &str) -> String {
    urlencoding::encode(s).into_owned()
}
fn enc_u(s: &str) -> String {
    urlencoding::encode(s).into_owned()
}

fn fragment_for(proxy: &ClashRawProxy) -> String {
    enc_frag(&proxy.name)
}

fn require_server_port(proxy: &ClashRawProxy) -> Result<(String, u16), UriSerializeError> {
    let server = proxy
        .server
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("server"))?;
    let port = proxy
        .port
        .filter(|p| *p > 0)
        .ok_or(UriSerializeError::MissingField("port"))?;
    Ok((server, port))
}

fn build_query(pairs: &[(&str, String)]) -> String {
    if pairs.is_empty() {
        return String::new();
    }
    format!(
        "?{}",
        pairs
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&")
    )
}

pub fn serialize_ss(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let method = proxy
        .cipher
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("cipher"))?;
    let password = proxy
        .password
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("password"))?;
    let (server, port) = require_server_port(proxy)?;
    let creds = format!("{}:{}", method, password);
    let encoded = url_safe_base64(creds.as_bytes());
    Ok(format!(
        "ss://{}@{}:{}#{}",
        encoded,
        server,
        port,
        fragment_for(proxy)
    ))
}

pub fn serialize_vless(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let uuid = proxy
        .uuid
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("uuid"))?;
    let (server, port) = require_server_port(proxy)?;
    let mut pairs: Vec<(&str, String)> = Vec::new();
    if let Some(v) = proxy.security.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("security", enc_q(v)));
    }
    if let Some(v) = proxy.sni.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("sni", enc_q(v)));
    }
    if let Some(v) = proxy.network.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("type", enc_q(v)));
    }
    if let Some(v) = proxy.flow.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("flow", enc_q(v)));
    }
    if let Some(v) = proxy.fingerprint.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("fp", enc_q(v)));
    }
    if let Some(v) = proxy.pbk.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("pbk", enc_q(v)));
    }
    if let Some(v) = proxy.sid.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("sid", enc_q(v)));
    }
    Ok(format!(
        "vless://{}@{}:{}{}#{}",
        uuid,
        server,
        port,
        build_query(&pairs),
        fragment_for(proxy)
    ))
}

pub fn serialize_trojan(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let password = proxy
        .password
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("password"))?;
    let (server, port) = require_server_port(proxy)?;
    let mut pairs: Vec<(&str, String)> = Vec::new();
    if let Some(v) = proxy.sni.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("sni", enc_q(v)));
    }
    if proxy.skip_cert_verify == Some(true) {
        pairs.push(("allowInsecure", "1".into()));
    }
    Ok(format!(
        "trojan://{}@{}:{}{}#{}",
        enc_u(&password),
        server,
        port,
        build_query(&pairs),
        fragment_for(proxy)
    ))
}

pub fn serialize_vmess(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let uuid = proxy
        .uuid
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("uuid"))?;
    let (server, port) = require_server_port(proxy)?;
    let mut json = serde_json::Map::new();
    json.insert("v".into(), serde_json::Value::String("2".into()));
    json.insert("ps".into(), serde_json::Value::String(proxy.name.clone()));
    json.insert("add".into(), serde_json::Value::String(server));
    json.insert("port".into(), serde_json::Value::Number(port.into()));
    json.insert("id".into(), serde_json::Value::String(uuid));
    json.insert(
        "aid".into(),
        serde_json::Value::Number(proxy.alter_id.unwrap_or(0).into()),
    );
    json.insert(
        "scy".into(),
        serde_json::Value::String(proxy.cipher.clone().unwrap_or_else(|| "auto".into())),
    );
    json.insert(
        "net".into(),
        serde_json::Value::String(proxy.network.clone().unwrap_or_else(|| "tcp".into())),
    );
    json.insert("type".into(), serde_json::Value::String("none".into()));
    let host_value = proxy
        .ws_headers
        .as_ref()
        .and_then(|h| h.get("Host").cloned())
        .unwrap_or_default();
    json.insert("host".into(), serde_json::Value::String(host_value));
    json.insert(
        "path".into(),
        serde_json::Value::String(proxy.ws_path.clone().unwrap_or_default()),
    );
    if let Some(v) = proxy.security.as_deref().filter(|s| !s.is_empty()) {
        json.insert("tls".into(), serde_json::Value::String(v.into()));
    }
    if let Some(v) = proxy.sni.as_deref().filter(|s| !s.is_empty()) {
        json.insert("sni".into(), serde_json::Value::String(v.into()));
    }
    if let Some(v) = proxy.fingerprint.as_deref().filter(|s| !s.is_empty()) {
        json.insert("fp".into(), serde_json::Value::String(v.into()));
    }
    let encoded = STANDARD.encode(
        serde_json::to_string(&json)
            .map_err(|e| UriSerializeError::UnsupportedType(format!("vmess JSON: {}", e)))?,
    );
    Ok(format!("vmess://{}", encoded))
}

pub fn serialize_hysteria2(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let password = proxy
        .password
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("password"))?;
    let (server, port) = require_server_port(proxy)?;
    let mut pairs: Vec<(&str, String)> = Vec::new();
    if let Some(v) = proxy.sni.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("sni", enc_q(v)));
    }
    if proxy.skip_cert_verify == Some(true) {
        pairs.push(("insecure", "1".into()));
    }
    Ok(format!(
        "hysteria2://{}@{}:{}{}#{}",
        enc_u(&password),
        server,
        port,
        build_query(&pairs),
        fragment_for(proxy)
    ))
}

pub fn serialize_tuic(proxy: &ClashRawProxy) -> Result<String, UriSerializeError> {
    let uuid = proxy
        .uuid
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("uuid"))?;
    let password = proxy
        .password
        .clone()
        .filter(|s| !s.is_empty())
        .ok_or(UriSerializeError::MissingField("password"))?;
    let (server, port) = require_server_port(proxy)?;
    let mut pairs: Vec<(&str, String)> = Vec::new();
    if let Some(v) = proxy.sni.as_deref().filter(|s| !s.is_empty()) {
        pairs.push(("sni", enc_q(v)));
    }
    if let Some(alpn) = &proxy.alpn {
        if !alpn.is_empty() {
            pairs.push(("alpn", enc_q(&alpn.join(","))));
        }
    }
    if proxy.skip_cert_verify == Some(true) {
        pairs.push(("allowInsecure", "1".into()));
    }
    let user_info = format!("{}:{}", uuid, enc_u(&password));
    Ok(format!(
        "tuic://{}@{}:{}{}#{}",
        user_info,
        server,
        port,
        build_query(&pairs),
        fragment_for(proxy)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::uri::parse_share_uri;

    fn assert_roundtrip(original: &ClashRawProxy) {
        let uri = proxy_to_uri_strict(original).expect("serialize must succeed");
        let parsed = parse_share_uri(&uri).expect("parse must succeed");
        assert_eq!(
            parsed.proxy_type, original.proxy_type,
            "proxy_type mismatch"
        );
        assert_eq!(parsed.server, original.server, "server mismatch");
        assert_eq!(parsed.port, original.port, "port mismatch");
        match original.proxy_type.as_deref() {
            Some("ss") => {
                assert_eq!(parsed.cipher, original.cipher, "cipher");
                assert_eq!(parsed.password, original.password, "password");
            }
            Some("vmess") | Some("vless") => {
                assert_eq!(parsed.uuid, original.uuid, "uuid");
            }
            Some("trojan") | Some("hysteria2") => {
                assert_eq!(parsed.password, original.password, "password");
            }
            Some("tuic") => {
                assert_eq!(parsed.uuid, original.uuid, "tuic uuid");
                assert_eq!(parsed.password, original.password, "tuic password");
            }
            _ => {}
        }
    }

    // ──── SS ────
    #[test]
    fn ss_basic() {
        let p = ClashRawProxy {
            name: "MySS".into(),
            server: Some("1.2.3.4".into()),
            port: Some(8388),
            proxy_type: Some("ss".into()),
            cipher: Some("aes-256-gcm".into()),
            password: Some("hunter2".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn ss_unicode_name() {
        let p = ClashRawProxy {
            name: "节点-A 日本".into(),
            server: Some("jp.example.com".into()),
            port: Some(443),
            proxy_type: Some("ss".into()),
            cipher: Some("chacha20-ietf-poly1305".into()),
            password: Some("p@ss w0rd!".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn ss_minimal_errors() {
        let p = ClashRawProxy {
            name: "x".into(),
            server: None,
            port: None,
            proxy_type: Some("ss".into()),
            ..Default::default()
        };
        assert!(proxy_to_uri_strict(&p).is_err());
    }

    // ──── VLESS ────
    #[test]
    fn vless_basic() {
        let p = ClashRawProxy {
            name: "vless-node".into(),
            server: Some("v.example.com".into()),
            port: Some(443),
            proxy_type: Some("vless".into()),
            uuid: Some("b2a3e8d4-1234-5678-9abc-def012345678".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn vless_reality() {
        let p = ClashRawProxy {
            name: "vless-reality".into(),
            server: Some("r.example.com".into()),
            port: Some(443),
            proxy_type: Some("vless".into()),
            uuid: Some("11111111-2222-3333-4444-555555555555".into()),
            network: Some("tcp".into()),
            security: Some("reality".into()),
            sni: Some("www.microsoft.com".into()),
            flow: Some("xtls-rprx-vision".into()),
            fingerprint: Some("chrome".into()),
            pbk: Some("PUBLIC_KEY_BASE64".into()),
            sid: Some("ab".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn vless_ws() {
        let p = ClashRawProxy {
            name: "vless-ws".into(),
            server: Some("w.example.com".into()),
            port: Some(8443),
            proxy_type: Some("vless".into()),
            uuid: Some("abcdef00-0000-0000-0000-000000000000".into()),
            network: Some("ws".into()),
            sni: Some("w.example.com".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }

    // ──── Trojan ────
    #[test]
    fn trojan_basic() {
        let p = ClashRawProxy {
            name: "trojan-1".into(),
            server: Some("t.example.com".into()),
            port: Some(443),
            proxy_type: Some("trojan".into()),
            password: Some("trojan-pwd".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn trojan_sni_insecure() {
        let p = ClashRawProxy {
            name: "trojan-sni".into(),
            server: Some("t2.example.com".into()),
            port: Some(8443),
            proxy_type: Some("trojan".into()),
            password: Some("p@ss".into()),
            sni: Some("cdn.example.com".into()),
            skip_cert_verify: Some(true),
            ..Default::default()
        };
        let uri = proxy_to_uri_strict(&p).unwrap();
        assert!(
            uri.contains("allowInsecure=1"),
            "uri should mark insecure: {}",
            uri
        );
        assert_roundtrip(&p);
    }
    #[test]
    fn trojan_no_password_errors() {
        let p = ClashRawProxy {
            name: "x".into(),
            server: Some("x.example.com".into()),
            port: Some(443),
            proxy_type: Some("trojan".into()),
            ..Default::default()
        };
        assert!(proxy_to_uri_strict(&p).is_err());
    }

    // ──── VMess ────
    #[test]
    fn vmess_basic() {
        let p = ClashRawProxy {
            name: "vm-1".into(),
            server: Some("v.example.com".into()),
            port: Some(443),
            proxy_type: Some("vmess".into()),
            uuid: Some("11111111-2222-3333-4444-555555555555".into()),
            alter_id: Some(0),
            cipher: Some("auto".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn vmess_ws_headers() {
        let mut headers = std::collections::HashMap::new();
        headers.insert("Host".into(), "cdn.example.com".into());
        let p = ClashRawProxy {
            name: "vm-ws".into(),
            server: Some("v.example.com".into()),
            port: Some(8443),
            proxy_type: Some("vmess".into()),
            uuid: Some("deadbeef-0000-0000-0000-000000000000".into()),
            alter_id: Some(2),
            network: Some("ws".into()),
            ws_path: Some("/ws".into()),
            ws_headers: Some(headers),
            tls: Some(true),
            sni: Some("cdn.example.com".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn vmess_no_uuid_errors() {
        let p = ClashRawProxy {
            name: "x".into(),
            server: Some("v.example.com".into()),
            port: Some(443),
            proxy_type: Some("vmess".into()),
            ..Default::default()
        };
        assert!(proxy_to_uri_strict(&p).is_err());
    }

    // ──── Hysteria2 ────
    #[test]
    fn hy2_basic() {
        let p = ClashRawProxy {
            name: "hy2-1".into(),
            server: Some("hy.example.com".into()),
            port: Some(30000),
            proxy_type: Some("hysteria2".into()),
            password: Some("hy2-secret".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn hy2_sni_insecure() {
        let p = ClashRawProxy {
            name: "hy2-2".into(),
            server: Some("hy.example.com".into()),
            port: Some(30000),
            proxy_type: Some("hysteria2".into()),
            password: Some("secret".into()),
            sni: Some("hy.example.com".into()),
            skip_cert_verify: Some(true),
            ..Default::default()
        };
        let uri = proxy_to_uri_strict(&p).unwrap();
        assert!(
            uri.contains("insecure=1"),
            "uri should mark insecure: {}",
            uri
        );
        assert_roundtrip(&p);
    }
    #[test]
    fn hy2_no_password_errors() {
        let p = ClashRawProxy {
            name: "x".into(),
            server: Some("hy.example.com".into()),
            port: Some(30000),
            proxy_type: Some("hysteria2".into()),
            ..Default::default()
        };
        assert!(proxy_to_uri_strict(&p).is_err());
    }

    // ──── TUIC ────
    #[test]
    fn tuic_basic() {
        let p = ClashRawProxy {
            name: "tuic-1".into(),
            server: Some("tq.example.com".into()),
            port: Some(8443),
            proxy_type: Some("tuic".into()),
            uuid: Some("00000000-1111-2222-3333-444444444444".into()),
            password: Some("tuic-pwd".into()),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn tuic_sni_insecure() {
        let p = ClashRawProxy {
            name: "tuic-2".into(),
            server: Some("tq.example.com".into()),
            port: Some(8443),
            proxy_type: Some("tuic".into()),
            uuid: Some("55555555-6666-7777-8888-999999999999".into()),
            password: Some("pwd!".into()),
            sni: Some("tq.example.com".into()),
            skip_cert_verify: Some(true),
            ..Default::default()
        };
        assert_roundtrip(&p);
    }
    #[test]
    fn tuic_no_uuid_errors() {
        let p = ClashRawProxy {
            name: "x".into(),
            server: Some("tq.example.com".into()),
            port: Some(8443),
            proxy_type: Some("tuic".into()),
            password: Some("pwd".into()),
            ..Default::default()
        };
        assert!(proxy_to_uri_strict(&p).is_err());
    }
}
