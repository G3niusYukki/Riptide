//! Persistent storage of the "active profile" pointer.
//!
//! Stored as a tiny JSON file at `%APPDATA%\Riptide\active.json` so the
//! selection survives restarts. The schema is intentionally minimal — we may
//! grow it later (last-used timestamp, per-profile preferences) but treat any
//! unknown fields as forward-compatible.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::utils::windows_dirs::WindowsDirs;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct ActiveState {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    active_profile_id: Option<String>,
}

fn active_state_path() -> PathBuf {
    WindowsDirs::config_dir().join("active.json")
}

/// Read the persisted active profile id. Returns `None` if the file is
/// missing, empty, or malformed (errors are logged but not propagated — a
/// corrupt sidecar should not block the app).
pub fn load_active_id() -> Option<String> {
    let path = active_state_path();
    let contents = fs::read_to_string(&path).ok()?;
    match serde_json::from_str::<ActiveState>(&contents) {
        Ok(state) => state.active_profile_id,
        Err(e) => {
            log::warn!("Ignoring corrupt active.json at {:?}: {}", path, e);
            None
        }
    }
}

/// Persist the active profile id. Passing `None` clears the pointer.
pub fn save_active_id(id: Option<&str>) -> Result<(), String> {
    WindowsDirs::ensure_dirs()
        .map_err(|e| format!("Failed to ensure config dir: {}", e))?;

    let state = ActiveState {
        active_profile_id: id.map(|s| s.to_string()),
    };
    let json = serde_json::to_string_pretty(&state)
        .map_err(|e| format!("Failed to serialize active state: {}", e))?;

    let path = active_state_path();
    // Write to a temp file then rename so we never leave a half-written file
    // behind if the process is killed mid-write.
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, json)
        .map_err(|e| format!("Failed to write {:?}: {}", tmp, e))?;
    fs::rename(&tmp, &path)
        .map_err(|e| format!("Failed to commit active.json: {}", e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_none_as_empty_object() {
        let state = ActiveState { active_profile_id: None };
        let json = serde_json::to_string(&state).unwrap();
        assert_eq!(json, "{}");
    }

    #[test]
    fn deserializes_missing_field_as_none() {
        let state: ActiveState = serde_json::from_str("{}").unwrap();
        assert!(state.active_profile_id.is_none());
    }

    #[test]
    fn round_trips_some_id() {
        let state = ActiveState {
            active_profile_id: Some("abc-123".into()),
        };
        let json = serde_json::to_string(&state).unwrap();
        let parsed: ActiveState = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.active_profile_id.as_deref(), Some("abc-123"));
    }
}
