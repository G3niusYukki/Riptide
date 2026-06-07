//! Per-profile metadata sidecar.
//!
//! Stored next to each profile's YAML as `<sanitized>__<uuid>.meta.json`.
//! Tracks subscription source URL, last-update timestamp, refresh interval,
//! and the most-recently-seen `Subscription-Userinfo` traffic/expiry header.
//!
//! Loss-tolerant: a missing or corrupt sidecar leaves the profile usable;
//! we just skip auto-update for it.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

/// Default subscription refresh cadence: once a day. Users override per-profile.
pub const DEFAULT_UPDATE_INTERVAL_SECS: u64 = 86_400;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProfileMetadata {
    /// Subscription URL — present iff the profile came from a remote feed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_url: Option<String>,
    /// Seconds between automatic refreshes; missing = no auto-refresh.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub update_interval_secs: Option<u64>,
    /// Wall-clock time of the last successful refresh (or import).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_updated_at: Option<DateTime<Utc>>,
    /// Most recent traffic/expiry info from the `Subscription-Userinfo` header.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subscription: Option<SubscriptionInfo>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SubscriptionInfo {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upload: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub download: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expire_at: Option<DateTime<Utc>>,
}

/// Translate a profile YAML path to its sidecar metadata path. Returns `None`
/// only if the input has no `.yaml`/`.yml` extension — i.e., not a profile.
pub fn metadata_path_for(profile_path: &Path) -> Option<PathBuf> {
    let ext = profile_path.extension()?.to_string_lossy().to_lowercase();
    if ext != "yaml" && ext != "yml" {
        return None;
    }
    Some(profile_path.with_extension("meta.json"))
}

pub fn load(profile_path: &Path) -> ProfileMetadata {
    let Some(meta_path) = metadata_path_for(profile_path) else {
        return ProfileMetadata::default();
    };
    let Ok(contents) = fs::read_to_string(&meta_path) else {
        return ProfileMetadata::default();
    };
    match serde_json::from_str(&contents) {
        Ok(m) => m,
        Err(e) => {
            log::warn!("Ignoring corrupt {:?}: {}", meta_path, e);
            ProfileMetadata::default()
        }
    }
}

pub fn save(profile_path: &Path, metadata: &ProfileMetadata) -> Result<(), String> {
    let Some(meta_path) = metadata_path_for(profile_path) else {
        return Err("Profile path has no .yaml extension".into());
    };
    let json = serde_json::to_string_pretty(metadata)
        .map_err(|e| format!("Failed to serialize metadata: {}", e))?;
    let tmp = meta_path.with_extension("json.tmp");
    fs::write(&tmp, json).map_err(|e| format!("Failed to write {:?}: {}", tmp, e))?;
    fs::rename(&tmp, &meta_path).map_err(|e| format!("Failed to commit {:?}: {}", meta_path, e))?;
    Ok(())
}

pub fn delete(profile_path: &Path) {
    if let Some(meta_path) = metadata_path_for(profile_path) {
        let _ = fs::remove_file(&meta_path);
    }
}

/// Parse `Subscription-Userinfo` header value, e.g.
/// `upload=1024; download=2048; total=10485760; expire=1735689600`.
///
/// Tolerant of missing fields, weird whitespace, and out-of-order keys.
pub fn parse_subscription_userinfo(header: &str) -> SubscriptionInfo {
    let mut info = SubscriptionInfo::default();
    for part in header.split(';') {
        let part = part.trim();
        let Some((key, value)) = part.split_once('=') else {
            continue;
        };
        let key = key.trim().to_ascii_lowercase();
        let value = value.trim();
        match key.as_str() {
            "upload" => info.upload = value.parse().ok(),
            "download" => info.download = value.parse().ok(),
            "total" => info.total = value.parse().ok(),
            "expire" => {
                info.expire_at = value
                    .parse::<i64>()
                    .ok()
                    .and_then(|ts| DateTime::from_timestamp(ts, 0));
            }
            _ => {}
        }
    }
    info
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_canonical_userinfo() {
        let info =
            parse_subscription_userinfo("upload=100; download=200; total=300; expire=1735689600");
        assert_eq!(info.upload, Some(100));
        assert_eq!(info.download, Some(200));
        assert_eq!(info.total, Some(300));
        assert!(info.expire_at.is_some());
    }

    #[test]
    fn tolerates_missing_fields() {
        let info = parse_subscription_userinfo("download=42");
        assert_eq!(info.download, Some(42));
        assert_eq!(info.upload, None);
        assert_eq!(info.total, None);
        assert_eq!(info.expire_at, None);
    }

    #[test]
    fn tolerates_unknown_keys() {
        let info = parse_subscription_userinfo("plan=enterprise; download=10");
        assert_eq!(info.download, Some(10));
    }

    #[test]
    fn metadata_path_derived_from_yaml() {
        let p = PathBuf::from("/tmp/foo__abc.yaml");
        let meta = metadata_path_for(&p).unwrap();
        assert_eq!(
            meta.file_name().unwrap().to_string_lossy(),
            "foo__abc.meta.json"
        );
    }

    #[test]
    fn metadata_path_rejects_non_yaml() {
        let p = PathBuf::from("/tmp/foo.txt");
        assert!(metadata_path_for(&p).is_none());
    }
}
