//! User-managed DNS policy.
//!
//! Persisted to `%APPDATA%\Riptide\dns_policy.json`. When a profile is written
//! to the mihomo config, the policy is overlaid on top of the profile's `dns:`
//! block. Policy fields with `None` / empty defer to whatever the profile has;
//! present policy fields win.
//!
//! Rationale: most users edit DNS via the UI (DoH, FakeIP toggle); a few rely
//! on the profile's bundled DNS. Letting the policy win-on-presence captures
//! both cases without forcing a copy of the YAML.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use crate::config::parser::ClashRawDNS;

const DNS_POLICY_FILENAME: &str = "dns_policy.json";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DnsPolicy {
    /// Whether the user has overridden DNS at all. If false, the policy is
    /// ignored entirely and the profile's dns block is used verbatim.
    #[serde(default)]
    pub enable_override: bool,

    /// Whether mihomo's DNS server should run at all (`dns.enable`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enable: Option<bool>,
    /// Listen address, e.g. "0.0.0.0:53".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub listen: Option<String>,
    /// "fake-ip" | "redir-host". `None` leaves profile's value.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enhanced_mode: Option<String>,
    /// CIDR range for FakeIP allocation.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fake_ip_range: Option<String>,
    /// Domains excluded from FakeIP (must resolve to real IP).
    #[serde(default)]
    pub fake_ip_filter: Vec<String>,
    /// Bootstrap resolvers (plain UDP, not DoH/DoT) used to look up DoH/DoT host names.
    #[serde(default)]
    pub default_nameserver: Vec<String>,
    /// Primary DNS servers — accepts DoH/DoT/DoQ URLs.
    #[serde(default)]
    pub nameserver: Vec<String>,
    /// Fallback resolvers consulted on geosite/geoip miss.
    #[serde(default)]
    pub fallback: Vec<String>,
    /// Per-domain resolver overrides.
    #[serde(default)]
    pub nameserver_policy: HashMap<String, String>,
    /// Whether DNS lookups respect the routing rules. mihomo default is false.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub respect_rules: Option<bool>,
}

impl DnsPolicy {
    fn path() -> PathBuf {
        crate::utils::windows_dirs::WindowsDirs::config_dir().join(DNS_POLICY_FILENAME)
    }

    pub fn load() -> Self {
        let path = Self::path();
        let Ok(contents) = fs::read_to_string(&path) else {
            return Self::default();
        };
        serde_json::from_str(&contents).unwrap_or_else(|e| {
            log::warn!("Ignoring corrupt dns_policy.json: {}", e);
            Self::default()
        })
    }

    pub fn save(&self) -> Result<(), String> {
        let path = Self::path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir: {}", e))?;
        }
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, json).map_err(|e| e.to_string())?;
        fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Overlay the policy on top of an existing (possibly None) dns block.
    /// Returns the merged result, or `None` if neither the profile nor the
    /// policy specifies DNS.
    pub fn apply_to(&self, existing: Option<ClashRawDNS>) -> Option<ClashRawDNS> {
        if !self.enable_override {
            return existing;
        }
        let mut dns = existing.unwrap_or_else(empty_dns);

        if let Some(v) = self.enable {
            dns.enable = Some(v);
        }
        if let Some(ref v) = self.listen {
            dns.listen = Some(v.clone());
        }
        if let Some(ref v) = self.enhanced_mode {
            dns.enhanced_mode = Some(v.clone());
            // When fake-ip is the chosen mode, ensure the boolean flag tracks it
            // — older mihomo builds read `fake-ip` rather than `enhanced-mode`.
            dns.fake_ip = Some(v == "fake-ip");
        }
        if let Some(ref v) = self.fake_ip_range {
            dns.fake_ip_range = Some(v.clone());
        }
        if !self.fake_ip_filter.is_empty() {
            dns.fake_ip_filter = Some(self.fake_ip_filter.clone());
        }
        if !self.default_nameserver.is_empty() {
            dns.default_nameserver = Some(self.default_nameserver.clone());
        }
        if !self.nameserver.is_empty() {
            dns.nameserver = Some(self.nameserver.clone());
        }
        if !self.fallback.is_empty() {
            dns.fallback = Some(self.fallback.clone());
        }
        if !self.nameserver_policy.is_empty() {
            dns.nameserver_policy = Some(self.nameserver_policy.clone());
        }
        if let Some(v) = self.respect_rules {
            dns.respect_rules = Some(v);
        }
        Some(dns)
    }
}

fn empty_dns() -> ClashRawDNS {
    ClashRawDNS {
        enable: None,
        listen: None,
        default_nameserver: None,
        nameserver: None,
        fallback: None,
        fallback_filter: None,
        fake_ip: None,
        fake_ip_range: None,
        fake_ip_filter: None,
        respect_rules: None,
        nameserver_policy: None,
        enhanced_mode: None,
        proxy_server_nameserver: None,
        hosts: None,
        cache_algorithm: None,
        timeout: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_policy_is_passthrough() {
        let policy = DnsPolicy::default();
        let existing = Some(empty_dns());
        let result = policy.apply_to(existing.clone());
        // Default has enable_override=false; the existing block (with all-None fields)
        // should be returned unchanged.
        assert!(result.is_some());
    }

    #[test]
    fn enabled_policy_overrides_existing() {
        let mut policy = DnsPolicy::default();
        policy.enable_override = true;
        policy.nameserver = vec!["https://1.1.1.1/dns-query".into()];
        policy.enhanced_mode = Some("fake-ip".into());

        let result = policy.apply_to(None).unwrap();
        assert_eq!(
            result.nameserver.as_deref(),
            Some(&["https://1.1.1.1/dns-query".to_string()][..])
        );
        assert_eq!(result.enhanced_mode.as_deref(), Some("fake-ip"));
        assert_eq!(result.fake_ip, Some(true));
    }

    #[test]
    fn enhanced_mode_redir_host_clears_fake_ip_flag() {
        let mut policy = DnsPolicy::default();
        policy.enable_override = true;
        policy.enhanced_mode = Some("redir-host".into());
        let result = policy.apply_to(None).unwrap();
        assert_eq!(result.fake_ip, Some(false));
    }
}
