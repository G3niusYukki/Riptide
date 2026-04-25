//! Clash YAML configuration parser
//!
//! Parses Clash/mihomo YAML configuration files into typed Rust structs
//! using serde_yaml for deserialization.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Top-level Clash configuration structure
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ClashRawConfig {
    /// HTTP proxy port
    pub port: Option<u16>,
    /// SOCKS5 proxy port
    #[serde(rename = "socks-port")]
    pub socks_port: Option<u16>,
    /// Mixed proxy port (HTTP + SOCKS5)
    #[serde(rename = "mixed-port")]
    pub mixed_port: Option<u16>,
    /// Redir port (Linux/macOS)
    #[serde(rename = "redir-port")]
    pub redir_port: Option<u16>,
    /// TProxy port (Linux)
    #[serde(rename = "tproxy-port")]
    pub tproxy_port: Option<u16>,
    /// Operation mode: rule, global, direct
    pub mode: Option<String>,
    /// Log level: debug, info, warning, error, silent
    #[serde(rename = "log-level")]
    pub log_level: Option<String>,
    /// Allow LAN connections
    #[serde(rename = "allow-lan")]
    pub allow_lan: Option<bool>,
    /// Bind address
    #[serde(rename = "bind-address")]
    pub bind_address: Option<String>,
    /// External controller address (REST API)
    #[serde(rename = "external-controller")]
    pub external_controller: Option<String>,
    /// External controller secret
    pub secret: Option<String>,
    /// IPv6 support
    pub ipv6: Option<bool>,
    /// TCP keep alive
    #[serde(rename = "keep-alive-idle")]
    pub keep_alive_idle: Option<u32>,
    #[serde(rename = "keep-alive-interval")]
    pub keep_alive_interval: Option<u32>,
    /// Interface name
    #[serde(rename = "interface-name")]
    pub interface_name: Option<String>,
    /// Routing mark (Linux)
    #[serde(rename = "routing-mark")]
    pub routing_mark: Option<u32>,

    /// Proxy nodes list
    pub proxies: Option<Vec<ClashRawProxy>>,
    /// Proxy groups
    #[serde(rename = "proxy-groups")]
    pub proxy_groups: Option<Vec<ClashRawProxyGroup>>,
    /// Proxy providers
    #[serde(rename = "proxy-providers")]
    pub proxy_providers: Option<HashMap<String, ClashRawProxyProvider>>,
    /// Routing rules
    pub rules: Option<Vec<String>>,
    /// Rule providers
    #[serde(rename = "rule-providers")]
    pub rule_providers: Option<HashMap<String, ClashRawRuleProvider>>,
    /// DNS configuration
    pub dns: Option<ClashRawDNS>,
    /// TUN configuration
    pub tun: Option<ClashRawTUN>,
    /// Profile configuration
    pub profile: Option<ClashRawProfile>,
    /// Experimental configuration
    pub experimental: Option<HashMap<String, serde_yaml::Value>>,
}

/// Proxy node configuration
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ClashRawProxy {
    /// Proxy name (required)
    pub name: String,
    /// Server address (required for most types)
    pub server: Option<String>,
    /// Server port (required for most types)
    pub port: Option<u16>,
    /// Proxy type: ss, vmess, vless, trojan, hysteria2, tuic, socks5, http, snell, etc.
    #[serde(rename = "type")]
    pub proxy_type: Option<String>,
    /// UDP support
    pub udp: Option<bool>,
    /// Network type: tcp, ws, h2, grpc, quic
    pub network: Option<String>,

    // Shadowsocks
    pub cipher: Option<String>,
    pub password: Option<String>,
    /// Shadowsocks plugin
    pub plugin: Option<String>,
    /// Plugin options
    #[serde(rename = "plugin-opts")]
    pub plugin_opts: Option<HashMap<String, serde_yaml::Value>>,

    // VMess / VLESS
    pub uuid: Option<String>,
    #[serde(rename = "alterId")]
    pub alter_id: Option<u32>,
    pub security: Option<String>,
    /// VLESS flow: xtls-rprx-direct, xtls-rprx-origin, xtls-rprx-splice
    pub flow: Option<String>,

    // Trojan / Hysteria2 / Tuic / Snell
    #[serde(rename = "skip-cert-verify")]
    pub skip_cert_verify: Option<bool>,
    pub sni: Option<String>,
    pub alpn: Option<Vec<String>>,
    /// fingerprint: chrome, firefox, safari, ios, android, randomized
    pub fingerprint: Option<String>,
    /// Client fingerprint for TLS
    #[serde(rename = "client-fingerprint")]
    pub client_fingerprint: Option<String>,

    // Hysteria2 specific
    #[serde(rename = "ports")]
    pub hy2_ports: Option<String>, // port hopping range, e.g. "20000-50000"
    #[serde(rename = "hop-interval")]
    pub hop_interval: Option<u32>,
    #[serde(rename = "ca-str")]
    pub ca_str: Option<String>,
    #[serde(rename = "ca")]
    pub ca_file: Option<String>,
    pub obfs: Option<String>,
    #[serde(rename = "obfs-password")]
    pub obfs_password: Option<String>,

    // TUIC specific
    #[serde(rename = "congestion-controller")]
    pub congestion_controller: Option<String>, // cubic, bbr, new_reno
    #[serde(rename = "udp-relay-mode")]
    pub udp_relay_mode: Option<String>, // native, quic
    #[serde(rename = "heartbeat-interval")]
    pub heartbeat_interval: Option<u32>,
    #[serde(rename = "disable-sni")]
    pub disable_sni: Option<bool>,
    #[serde(rename = "reduce-rtt")]
    pub reduce_rtt: Option<bool>,
    #[serde(rename = "request-version")]
    pub request_version: Option<u32>,
    #[serde(rename = "max-udp-relay-packet-size")]
    pub max_udp_relay_packet_size: Option<u32>,
    #[serde(rename = "fast-open")]
    pub fast_open: Option<bool>,
    #[serde(rename = "max-open-streams")]
    pub max_open_streams: Option<u32>,

    // WebSocket options
    #[serde(rename = "ws-opts")]
    pub ws_opts: Option<ClashRawWSOpts>,
    #[serde(rename = "ws-path")]
    pub ws_path: Option<String>,
    #[serde(rename = "ws-headers")]
    pub ws_headers: Option<HashMap<String, String>>,

    // gRPC options
    #[serde(rename = "grpc-opts")]
    pub grpc_opts: Option<ClashRawGRPCOpts>,
    #[serde(rename = "grpc-service-name")]
    pub grpc_service_name: Option<String>,

    // HTTP/2 options
    #[serde(rename = "h2-opts")]
    pub h2_opts: Option<ClashRawH2Opts>,
    #[serde(rename = "h2-host")]
    pub h2_host: Option<Vec<String>>,

    // REALITY options (VLESS/XTLS)
    #[serde(rename = "reality-opts")]
    pub reality_opts: Option<ClashRawRealityOpts>,
    pub pbk: Option<String>, // Public key
    pub sid: Option<String>, // Short ID
    pub spx: Option<String>, // SpiderX

    // HTTP proxy specific
    pub username: Option<String>,
    /// HTTP headers
    pub headers: Option<HashMap<String, String>>,
    /// TLS settings
    pub tls: Option<bool>,

    // SOCKS5 specific
    #[serde(rename = "udp-over-tcp")]
    pub udp_over_tcp: Option<bool>,

    // Snell specific
    pub version: Option<u8>,
    // Note: Snell obfs is handled by the shared obfs field above

    // Relay/Chain
    pub chain: Option<String>,

    // Common TLS options
    #[serde(rename = "disable-auto-tls")]
    pub disable_auto_tls: Option<bool>,
}

/// WebSocket options
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawWSOpts {
    pub path: Option<String>,
    pub headers: Option<HashMap<String, String>>,
    #[serde(rename = "max-early-data")]
    pub max_early_data: Option<u32>,
    #[serde(rename = "early-data-header-name")]
    pub early_data_header_name: Option<String>,
}

/// gRPC options
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawGRPCOpts {
    #[serde(rename = "grpc-service-name")]
    pub grpc_service_name: Option<String>,
}

/// HTTP/2 options
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawH2Opts {
    pub host: Option<Vec<String>>,
}

/// REALITY options
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawRealityOpts {
    pub public_key: Option<String>,
    #[serde(rename = "short-id")]
    pub short_id: Option<String>,
    #[serde(rename = "spider-x")]
    pub spider_x: Option<String>,
}

/// Proxy group configuration
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ClashRawProxyGroup {
    /// Group name (required)
    pub name: Option<String>,
    /// Group type: select, url-test, fallback, load-balance, relay
    #[serde(rename = "type")]
    pub group_type: Option<String>,
    /// Proxy names in this group
    pub proxies: Option<Vec<String>>,
    /// URL for health check
    pub url: Option<String>,
    /// Health check interval in seconds
    pub interval: Option<u32>,
    /// Tolerance for url-test (in ms)
    pub tolerance: Option<u32>,
    /// Load balance strategy: consistent-hashing, round-robin
    pub strategy: Option<String>,
    /// Disable UDP relay
    #[serde(rename = "disable-udp")]
    pub disable_udp: Option<bool>,
    /// Filter for proxy providers
    pub filter: Option<String>,
    /// Exclude filter
    pub exclude_filter: Option<String>,
    /// Use proxy providers instead of proxies list
    #[serde(rename = "use")]
    pub use_providers: Option<Vec<String>>,
}

/// Proxy provider configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawProxyProvider {
    /// Provider type: http or file
    #[serde(rename = "type")]
    pub provider_type: String,
    /// URL for HTTP provider
    pub url: Option<String>,
    /// File path for file provider  
    pub path: Option<String>,
    /// Refresh interval in seconds
    pub interval: Option<u32>,
    /// Health check configuration
    #[serde(rename = "health-check")]
    pub health_check: Option<ClashRawHealthCheck>,
    /// Filter expression
    pub filter: Option<String>,
    /// Exclude filter
    pub exclude_filter: Option<String>,
    /// Expected proxy count (for validation)
    #[serde(rename = "expected-proxies-count")]
    pub expected_proxies_count: Option<u32>,
    /// Override proxy properties
    pub override_config: Option<HashMap<String, serde_yaml::Value>>,
}

/// Health check configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawHealthCheck {
    pub enable: bool,
    pub url: Option<String>,
    pub interval: Option<u32>,
    #[serde(rename = "lazy")]
    pub lazy_check: Option<bool>,
    #[serde(rename = "expected-code")]
    pub expected_code: Option<u16>,
}

/// Rule provider configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawRuleProvider {
    /// Provider type: http or file
    #[serde(rename = "type")]
    pub provider_type: String,
    /// Behavior: domain, ipcidr, classical
    pub behavior: String,
    /// URL for HTTP provider
    pub url: Option<String>,
    /// File path for file provider
    pub path: Option<String>,
    /// Refresh interval in seconds
    pub interval: Option<u32>,
    /// Format: yaml or text
    pub format: Option<String>,
    /// Proxy to use for downloading
    pub proxy: Option<String>,
}

/// DNS configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawDNS {
    pub enable: Option<bool>,
    /// Listen address for DNS server
    pub listen: Option<String>,
    #[serde(rename = "default-nameserver")]
    pub default_nameserver: Option<Vec<String>>,
    pub nameserver: Option<Vec<String>>,
    pub fallback: Option<Vec<String>>,
    #[serde(rename = "fallback-filter")]
    pub fallback_filter: Option<ClashRawFallbackFilter>,
    #[serde(rename = "fake-ip")]
    pub fake_ip: Option<bool>,
    #[serde(rename = "fake-ip-range")]
    pub fake_ip_range: Option<String>,
    #[serde(rename = "fake-ip-filter")]
    pub fake_ip_filter: Option<Vec<String>>,
    /// Respect routing rules for DNS
    #[serde(rename = "respect-rules")]
    pub respect_rules: Option<bool>,
    /// DNS over HTTPS
    #[serde(rename = "nameserver-policy")]
    pub nameserver_policy: Option<HashMap<String, String>>,
    /// Enhanced mode: fake-ip or redir-host
    #[serde(rename = "enhanced-mode")]
    pub enhanced_mode: Option<String>,
    /// Proxy server nameserver
    #[serde(rename = "proxy-server-nameserver")]
    pub proxy_server_nameserver: Option<Vec<String>>,
    /// Use hosts
    pub hosts: Option<HashMap<String, String>>,
    /// Cache size
    #[serde(rename = "cache-algorithm")]
    pub cache_algorithm: Option<String>,
    /// DNS timeout
    pub timeout: Option<u32>,
}

/// DNS fallback filter
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawFallbackFilter {
    pub geoip: Option<bool>,
    #[serde(rename = "geoip-code")]
    pub geoip_code: Option<String>,
    pub ipcidr: Option<Vec<String>>,
    pub domain: Option<Vec<String>>,
    pub geosite: Option<Vec<String>>,
}

/// TUN configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawTUN {
    pub enable: Option<bool>,
    /// Device name
    pub device: Option<String>,
    /// Driver: gvisor, system
    pub stack: Option<String>,
    /// DNS hijack list
    #[serde(rename = "dns-hijack")]
    pub dns_hijack: Option<Vec<String>>,
    /// Auto route
    #[serde(rename = "auto-route")]
    pub auto_route: Option<bool>,
    /// Auto detect interface
    #[serde(rename = "auto-detect-interface")]
    pub auto_detect_interface: Option<bool>,
    /// MTU
    pub mtu: Option<u32>,
    /// Strict route (Windows)
    #[serde(rename = "strict-route")]
    pub strict_route: Option<bool>,
    /// Endpoint independent NAT
    #[serde(rename = "endpoint-independent-nat")]
    pub endpoint_independent_nat: Option<bool>,
    /// Include interfaces
    #[serde(rename = "include-interface")]
    pub include_interface: Option<Vec<String>>,
    /// Exclude interfaces
    #[serde(rename = "exclude-interface")]
    pub exclude_interface: Option<Vec<String>>,
    /// Include UID (Linux)
    #[serde(rename = "include-uid")]
    pub include_uid: Option<Vec<u32>>,
    /// Exclude UID (Linux)
    #[serde(rename = "exclude-uid")]
    pub exclude_uid: Option<Vec<u32>>,
    /// Include Android user
    #[serde(rename = "include-android-user")]
    pub include_android_user: Option<Vec<u32>>,
    /// Include package name (Android)
    #[serde(rename = "include-package")]
    pub include_package: Option<Vec<String>>,
    /// Exclude package name (Android)
    #[serde(rename = "exclude-package")]
    pub exclude_package: Option<Vec<String>>,
    /// UDP timeout
    #[serde(rename = "udp-timeout")]
    pub udp_timeout: Option<u32>,
    /// File descriptor
    #[serde(rename = "file-descriptor")]
    pub file_descriptor: Option<i32>,
}

/// Profile configuration
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ClashRawProfile {
    /// Store selected proxy for each group
    #[serde(rename = "store-selected")]
    pub store_selected: Option<bool>,
    /// Store fake IP mapping
    #[serde(rename = "store-fake-ip")]
    pub store_fake_ip: Option<bool>,
}

/// Parse Clash YAML configuration from string
pub fn parse_clash_config(yaml: &str) -> Result<ClashRawConfig, serde_yaml::Error> {
    serde_yaml::from_str(yaml)
}

/// Parse Clash YAML configuration from file
pub fn parse_clash_config_file(path: &std::path::Path) -> anyhow::Result<ClashRawConfig> {
    let content = std::fs::read_to_string(path)?;
    Ok(parse_clash_config(&content)?)
}

/// Serialize Clash configuration to YAML string
pub fn serialize_clash_config(config: &ClashRawConfig) -> Result<String, serde_yaml::Error> {
    serde_yaml::to_string(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_config() {
        let yaml = r#"
port: 7890
socks-port: 7891
mode: rule
"#;
        let config = parse_clash_config(yaml).unwrap();
        assert_eq!(config.port, Some(7890));
        assert_eq!(config.socks_port, Some(7891));
        assert_eq!(config.mode, Some("rule".to_string()));
    }

    #[test]
    fn test_parse_with_proxies() {
        let yaml = r#"
proxies:
  - name: "US Server"
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: password123
"#;
        let config = parse_clash_config(yaml).unwrap();
        let proxies = config.proxies.unwrap();
        assert_eq!(proxies.len(), 1);
        assert_eq!(proxies[0].name, "US Server");
        assert_eq!(proxies[0].proxy_type, Some("ss".to_string()));
    }

    #[test]
    fn test_parse_with_proxy_groups() {
        let yaml = r#"
proxy-groups:
  - name: "Auto Select"
    type: url-test
    proxies:
      - "US Server"
      - "HK Server"
    url: http://www.gstatic.com/generate_204
    interval: 300
"#;
        let config = parse_clash_config(yaml).unwrap();
        let groups = config.proxy_groups.unwrap();
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].name, Some("Auto Select".to_string()));
        assert_eq!(groups[0].group_type, Some("url-test".to_string()));
    }

    #[test]
    fn test_parse_rules() {
        let yaml = r#"
rules:
  - DOMAIN,google.com,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - MATCH,Proxy
"#;
        let config = parse_clash_config(yaml).unwrap();
        let rules = config.rules.unwrap();
        assert_eq!(rules.len(), 3);
        assert!(rules[0].contains("DOMAIN"));
    }

    #[test]
    fn test_parse_dns() {
        let yaml = r#"
dns:
  enable: true
  listen: 0.0.0.0:53
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
"#;
        let config = parse_clash_config(yaml).unwrap();
        let dns = config.dns.unwrap();
        assert_eq!(dns.enable, Some(true));
        assert_eq!(dns.listen, Some("0.0.0.0:53".to_string()));
    }
}
