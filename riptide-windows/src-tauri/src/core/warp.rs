//! Cloudflare WARP integration.
//!
//! Registers a fresh anonymous WARP peer and saves it as a mihomo profile
//! using mihomo's `wireguard` proxy type. The flow:
//!
//!   1. Generate a Curve25519 keypair locally (private key never leaves disk).
//!   2. POST our public key to Cloudflare's registration endpoint.
//!   3. Decode the `client_id` to derive the 3-byte `reserved` field that
//!      WARP requires on every packet.
//!   4. Materialise a Clash YAML profile with the assigned address, peer
//!      public key, endpoint, and reserved bytes.
//!
//! This calls Cloudflare's *unofficial* registration API — it can change
//! without notice. On failure we surface the HTTP status / body so the user
//! gets a real signal rather than a generic "registration failed".

use crate::cmds::config::AppState;
#[cfg(target_os = "windows")]
use crate::config::profiles::storage;
use crate::config::profiles::Profile;
use base64::Engine;
use rand::rngs::OsRng;
use serde::Deserialize;
use tauri::State;
use x25519_dalek::{PublicKey, StaticSecret};

const REGISTER_URL: &str = "https://api.cloudflareclient.com/v0a2158/reg";
const CLIENT_VERSION: &str = "a-6.30-3596";
const USER_AGENT: &str = "okhttp/3.12.1";

#[derive(Debug, Deserialize)]
struct RegisterResponse {
    #[allow(dead_code)]
    id: Option<String>,
    config: ResponseConfig,
}

#[derive(Debug, Deserialize)]
struct ResponseConfig {
    client_id: String,
    peers: Vec<ResponsePeer>,
    interface: ResponseInterface,
}

#[derive(Debug, Deserialize)]
struct ResponsePeer {
    public_key: String,
    endpoint: ResponseEndpoint,
}

#[derive(Debug, Deserialize)]
struct ResponseEndpoint {
    host: String,
}

#[derive(Debug, Deserialize)]
struct ResponseInterface {
    addresses: ResponseAddresses,
}

#[derive(Debug, Deserialize)]
struct ResponseAddresses {
    v4: String,
    v6: String,
}

fn generate_keypair() -> (StaticSecret, PublicKey) {
    let secret = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);
    (secret, public)
}

fn encode_b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// Derive the 3-byte `reserved` field WARP expects from the base64 `client_id`.
fn reserved_from_client_id(client_id: &str) -> Result<[u8; 3], String> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(client_id)
        .map_err(|e| format!("Invalid client_id base64: {}", e))?;
    if bytes.len() < 3 {
        return Err(format!(
            "client_id too short: expected ≥3 bytes, got {}",
            bytes.len()
        ));
    }
    Ok([bytes[0], bytes[1], bytes[2]])
}

fn split_host_port(host_port: &str) -> Result<(String, u16), String> {
    // Handle "host:port" and "[v6]:port".
    let trimmed = host_port.trim();
    if let Some(rest) = trimmed.strip_prefix('[') {
        let (h, rest) = rest
            .split_once(']')
            .ok_or_else(|| format!("Malformed IPv6 endpoint: {}", host_port))?;
        let port_str = rest.trim_start_matches(':');
        let port = port_str
            .parse::<u16>()
            .map_err(|e| format!("Bad port in endpoint '{}': {}", host_port, e))?;
        Ok((h.to_string(), port))
    } else {
        let (h, p) = trimmed
            .rsplit_once(':')
            .ok_or_else(|| format!("Endpoint missing port: {}", host_port))?;
        let port = p
            .parse::<u16>()
            .map_err(|e| format!("Bad port in endpoint '{}': {}", host_port, e))?;
        Ok((h.to_string(), port))
    }
}

/// Build the mihomo Clash YAML for a single WARP wireguard proxy plus a
/// minimal proxy-group + rules block so the profile is immediately usable.
fn build_warp_profile_yaml(
    name: &str,
    private_key_b64: &str,
    peer_public_key: &str,
    endpoint_host: &str,
    endpoint_port: u16,
    ipv4: &str,
    ipv6: &str,
    reserved: [u8; 3],
) -> String {
    // Strip CIDR mask if present — mihomo wants bare addresses.
    let ipv4 = ipv4.split('/').next().unwrap_or(ipv4);
    let ipv6 = ipv6.split('/').next().unwrap_or(ipv6);
    format!(
        r#"mode: rule
proxies:
  - name: "{name}"
    type: wireguard
    server: {server}
    port: {port}
    ip: {ipv4}
    ipv6: {ipv6}
    private-key: "{private_key}"
    public-key: "{public_key}"
    reserved: [{r0}, {r1}, {r2}]
    udp: true
    mtu: 1280
    dns:
      - 1.1.1.1
      - 1.0.0.1
proxy-groups:
  - name: "WARP"
    type: select
    proxies:
      - "{name}"
      - DIRECT
rules:
  - MATCH,WARP
"#,
        name = name,
        server = endpoint_host,
        port = endpoint_port,
        ipv4 = ipv4,
        ipv6 = ipv6,
        private_key = private_key_b64,
        public_key = peer_public_key,
        r0 = reserved[0],
        r1 = reserved[1],
        r2 = reserved[2],
    )
}

#[cfg(target_os = "windows")]
async fn register_anonymous_warp(public_key_b64: &str) -> Result<RegisterResponse, String> {
    let install_id = uuid::Uuid::new_v4().simple().to_string();
    let now_rfc3339 = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    let body = serde_json::json!({
        "key": public_key_b64,
        "install_id": install_id,
        "fcm_token": "",
        "tos": now_rfc3339,
        "model": "PC",
        "serial_number": install_id,
        "locale": "en_US",
    });

    let client = reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .timeout(std::time::Duration::from_secs(20))
        .build()
        .map_err(|e| format!("HTTP client build failed: {}", e))?;

    let resp = client
        .post(REGISTER_URL)
        .header("CF-Client-Version", CLIENT_VERSION)
        .header("Content-Type", "application/json; charset=UTF-8")
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("WARP registration request failed: {}", e))?;

    let status = resp.status();
    let text = resp
        .text()
        .await
        .map_err(|e| format!("Failed to read WARP response body: {}", e))?;
    if !status.is_success() {
        return Err(format!("WARP registration HTTP {}: {}", status, text));
    }
    serde_json::from_str::<RegisterResponse>(&text)
        .map_err(|e| format!("Unexpected WARP response shape: {} (body: {})", e, text))
}

/// Tauri command: register an anonymous WARP peer and save it as a profile.
/// Returns the saved profile so the UI can refresh its list and offer to activate.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn register_warp_profile(
    name: Option<String>,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    let profile_name = name
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| format!("WARP-{}", chrono::Utc::now().format("%Y%m%d-%H%M%S")));

    let (secret, public) = generate_keypair();
    let private_key_b64 = encode_b64(secret.to_bytes().as_ref());
    let public_key_b64 = encode_b64(public.as_bytes());

    log::info!("Registering anonymous WARP peer (pubkey {})", &public_key_b64);
    let response = register_anonymous_warp(&public_key_b64).await?;
    let reserved = reserved_from_client_id(&response.config.client_id)?;

    let peer = response
        .config
        .peers
        .into_iter()
        .next()
        .ok_or_else(|| "WARP response contained no peers".to_string())?;
    let (host, port) = split_host_port(&peer.endpoint.host)?;

    let yaml = build_warp_profile_yaml(
        &profile_name,
        &private_key_b64,
        &peer.public_key,
        &host,
        port,
        &response.config.interface.addresses.v4,
        &response.config.interface.addresses.v6,
        reserved,
    );

    let mut profile = Profile::new(profile_name.clone(), yaml);
    profile.set_node_count(1);
    #[cfg(target_os = "windows")]
    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save WARP profile: {}", e))?;

    state.profiles.lock().unwrap().push(profile.clone());

    log::info!(
        "WARP profile '{}' saved (assigned ip {} / endpoint {}:{})",
        profile.name,
        response.config.interface.addresses.v4,
        host,
        port
    );
    Ok(profile)
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn register_warp_profile(
    _name: Option<String>,
    _state: State<'_, AppState>,
) -> Result<Profile, String> {
    Err("WARP registration only available on Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keypair_is_nondeterministic() {
        let (a_secret, a_public) = generate_keypair();
        let (b_secret, b_public) = generate_keypair();
        assert_ne!(a_secret.to_bytes(), b_secret.to_bytes());
        assert_ne!(a_public.as_bytes(), b_public.as_bytes());
    }

    #[test]
    fn keypair_encodes_to_44char_b64() {
        let (secret, public) = generate_keypair();
        // 32 bytes → 44 chars padded base64.
        assert_eq!(encode_b64(secret.to_bytes().as_ref()).len(), 44);
        assert_eq!(encode_b64(public.as_bytes()).len(), 44);
    }

    #[test]
    fn reserved_takes_first_three_bytes_of_client_id() {
        // base64("ABCDEF") = "QUJDREVG" -> bytes [65, 66, 67, 68, 69, 70]
        let b64 = base64::engine::general_purpose::STANDARD.encode(b"ABCDEF");
        let reserved = reserved_from_client_id(&b64).unwrap();
        assert_eq!(reserved, [b'A', b'B', b'C']);
    }

    #[test]
    fn reserved_rejects_short_client_id() {
        let b64 = base64::engine::general_purpose::STANDARD.encode(b"AB");
        assert!(reserved_from_client_id(&b64).is_err());
    }

    #[test]
    fn host_port_handles_ipv4() {
        let (h, p) = split_host_port("engage.cloudflareclient.com:2408").unwrap();
        assert_eq!(h, "engage.cloudflareclient.com");
        assert_eq!(p, 2408);
    }

    #[test]
    fn host_port_handles_ipv6() {
        let (h, p) = split_host_port("[2606:4700:d0::a29f:c001]:2408").unwrap();
        assert_eq!(h, "2606:4700:d0::a29f:c001");
        assert_eq!(p, 2408);
    }

    #[test]
    fn build_yaml_strips_cidr_mask() {
        let yaml = build_warp_profile_yaml(
            "WARP",
            "PRIV",
            "PUB",
            "engage.cloudflareclient.com",
            2408,
            "172.16.0.2/32",
            "2606:4700:110::abc/128",
            [0xAA, 0xBB, 0xCC],
        );
        assert!(yaml.contains("ip: 172.16.0.2\n"));
        assert!(yaml.contains("ipv6: 2606:4700:110::abc\n"));
        assert!(yaml.contains("reserved: [170, 187, 204]"));
        assert!(!yaml.contains("/32"));
        assert!(!yaml.contains("/128"));
    }
}
