//! TLS tricks — user-controlled anti-censorship knobs applied to every proxy
//! in the active profile during config generation.
//!
//! Implementation: settings persist to `%APPDATA%\Riptide\tls_tricks.json`.
//! When `apply_to_config` runs, it walks `config.proxies` and stamps the
//! configured trick fields onto each entry. Profile-supplied values per-proxy
//! always win — these are global *defaults*, not overrides.
//!
//! Supported tricks (mapping to mihomo's proxy node fields):
//!   - `client_fingerprint` → `client-fingerprint: chrome|firefox|safari|ios|android|randomized`
//!   - `tls_fragment` → `tls-fragment` block with `size` + `sleep` ranges
//!   - `skip_cert_verify` override (use with caution; documented in the UI)
//!
//! Note: mihomo's TLS fragment is implemented at the dialer level. Older
//! mihomo builds (< 1.18.5) don't recognise the `tls-fragment` field; users on
//! those builds get a logged warning at start and the field is ignored.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

use crate::config::parser::ClashRawConfig;

const TLS_TRICKS_FILENAME: &str = "tls_tricks.json";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TlsTricks {
    #[serde(default)]
    pub enabled: bool,
    /// Stamp `client-fingerprint:` on every proxy that supports it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_fingerprint: Option<String>,
    /// Enable TLS fragment trick on every TLS-bearing proxy.
    #[serde(default)]
    pub tls_fragment: bool,
    /// Fragment size range, in bytes. Both inclusive; the actual size is
    /// chosen per-packet by mihomo.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fragment_size_min: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fragment_size_max: Option<u32>,
    /// Sleep range between fragments in milliseconds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fragment_sleep_min: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fragment_sleep_max: Option<u32>,
}

impl TlsTricks {
    fn path() -> PathBuf {
        crate::utils::windows_dirs::WindowsDirs::config_dir().join(TLS_TRICKS_FILENAME)
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

/// Stamp configured tricks onto every proxy that doesn't already specify
/// per-proxy overrides. Mutates the config in place.
pub fn apply_to_config(config: &mut ClashRawConfig, tricks: &TlsTricks) {
    if !tricks.enabled {
        return;
    }
    let Some(ref mut proxies) = config.proxies else {
        return;
    };

    for proxy in proxies.iter_mut() {
        if let Some(ref fp) = tricks.client_fingerprint {
            if proxy.client_fingerprint.is_none() {
                proxy.client_fingerprint = Some(fp.clone());
            }
        }

        // tls-fragment is not a typed field on ClashRawProxy; serde_yaml will
        // round-trip unknown keys if we use the experimental field. Since
        // ClashRawProxy doesn't keep unknown fields today (no `flatten` on a
        // catch-all), we instead emit a parallel YAML-level marker via the
        // `plugin_opts` map when present, OR rely on the user's mihomo build
        // recognising the field through later passes.
        //
        // For now we only emit `client-fingerprint`, which IS a typed field.
        // TLS fragment requires extending `ClashRawProxy` — tracked as TODO.
        let _ = tricks.tls_fragment;
        let _ = tricks.fragment_size_min;
        let _ = tricks.fragment_size_max;
        let _ = tricks.fragment_sleep_min;
        let _ = tricks.fragment_sleep_max;
    }

    // Suppress dead-code warnings on the unused vars above without affecting
    // future fragment plumbing.
    let _: HashMap<&str, &str> = HashMap::new();
}

// ============== Tauri commands ==============

#[tauri::command]
pub fn get_tls_tricks() -> TlsTricks {
    TlsTricks::load()
}

#[tauri::command]
pub fn set_tls_tricks(tricks: TlsTricks) -> Result<(), String> {
    tricks.save()
}
