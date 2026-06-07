//! Region presets — opinionated rule/DNS bundles for users in heavily-censored
//! regions. When a preset is active, we overlay its rules onto the profile's
//! rule list (prepending so they win over profile-supplied rules) and force
//! its DNS configuration.
//!
//! Presets are baked in as constants — keeping them out of profiles means
//! users don't have to switch subscriptions to change region behaviour.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::config::parser::{ClashRawConfig, ClashRawDNS};

const REGION_PRESET_FILENAME: &str = "region_preset.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Region {
    None,
    China,
    Iran,
    Russia,
}

impl Default for Region {
    fn default() -> Self {
        Region::None
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RegionState {
    #[serde(default)]
    pub active: Region,
}

impl RegionState {
    fn path() -> PathBuf {
        crate::utils::windows_dirs::WindowsDirs::config_dir().join(REGION_PRESET_FILENAME)
    }

    pub fn load() -> Self {
        let path = Self::path();
        let Ok(contents) = std::fs::read_to_string(&path) else {
            return Self::default();
        };
        serde_json::from_str(&contents).unwrap_or_default()
    }

    pub fn save(&self) -> Result<(), String> {
        let path = Self::path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, json).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// Overlay the active region preset onto a `ClashRawConfig`. Mutates rules
/// (prepends preset rules) and replaces the DNS block when a preset is active.
pub fn apply_to_config(config: &mut ClashRawConfig, region: Region) {
    if region == Region::None {
        return;
    }
    let preset = preset_for(region);

    // Prepend region rules. They reference policies named in the profile —
    // we deliberately don't invent new policy names so existing proxies keep
    // working.
    let mut new_rules = preset.rules.clone();
    if let Some(existing) = &config.rules {
        new_rules.extend(existing.iter().cloned());
    }
    config.rules = Some(new_rules);

    // Replace DNS wholesale — region DNS is the whole point.
    config.dns = Some(preset.dns.clone());
}

struct Preset {
    rules: Vec<String>,
    dns: ClashRawDNS,
}

fn preset_for(region: Region) -> Preset {
    match region {
        Region::None => Preset {
            rules: vec![],
            dns: empty_dns(),
        },
        Region::China => Preset {
            rules: vec![
                // Always-direct: LAN, common Chinese-mainland targets.
                "DOMAIN-SUFFIX,cn,DIRECT".to_string(),
                "GEOIP,LAN,DIRECT,no-resolve".to_string(),
                "GEOIP,CN,DIRECT".to_string(),
                "GEOSITE,cn,DIRECT".to_string(),
                "GEOSITE,private,DIRECT".to_string(),
                // Block ads + malicious by default.
                "GEOSITE,category-ads-all,REJECT".to_string(),
            ],
            dns: ClashRawDNS {
                enable: Some(true),
                listen: Some("0.0.0.0:53".into()),
                enhanced_mode: Some("fake-ip".into()),
                fake_ip: Some(true),
                fake_ip_range: Some("198.18.0.1/16".into()),
                default_nameserver: Some(vec!["223.5.5.5".into(), "119.29.29.29".into()]),
                nameserver: Some(vec![
                    "https://dns.alidns.com/dns-query".into(),
                    "https://doh.pub/dns-query".into(),
                ]),
                fallback: Some(vec![
                    "https://1.1.1.1/dns-query".into(),
                    "https://dns.google/dns-query".into(),
                ]),
                ..empty_dns()
            },
        },
        Region::Iran => Preset {
            rules: vec![
                "GEOIP,IR,DIRECT".to_string(),
                "GEOSITE,category-ir,DIRECT".to_string(),
                "GEOSITE,private,DIRECT".to_string(),
            ],
            dns: ClashRawDNS {
                enable: Some(true),
                listen: Some("0.0.0.0:53".into()),
                enhanced_mode: Some("fake-ip".into()),
                fake_ip: Some(true),
                fake_ip_range: Some("198.18.0.1/16".into()),
                default_nameserver: Some(vec!["178.22.122.100".into(), "185.51.200.2".into()]),
                nameserver: Some(vec![
                    "https://1.1.1.1/dns-query".into(),
                    "https://dns.google/dns-query".into(),
                ]),
                ..empty_dns()
            },
        },
        Region::Russia => Preset {
            rules: vec![
                "GEOIP,RU,DIRECT".to_string(),
                "GEOSITE,category-ru,DIRECT".to_string(),
                "GEOSITE,private,DIRECT".to_string(),
            ],
            dns: ClashRawDNS {
                enable: Some(true),
                listen: Some("0.0.0.0:53".into()),
                enhanced_mode: Some("fake-ip".into()),
                fake_ip: Some(true),
                fake_ip_range: Some("198.18.0.1/16".into()),
                default_nameserver: Some(vec!["77.88.8.8".into()]),
                nameserver: Some(vec![
                    "https://1.1.1.1/dns-query".into(),
                    "https://dns.google/dns-query".into(),
                ]),
                ..empty_dns()
            },
        },
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

// ============== Tauri commands ==============

#[tauri::command]
pub fn get_region_preset() -> RegionState {
    RegionState::load()
}

#[tauri::command]
pub fn set_region_preset(region: Region) -> Result<(), String> {
    let state = RegionState { active: region };
    state.save()
}
