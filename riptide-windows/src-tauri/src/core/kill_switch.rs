//! Kill switch — when mihomo crashes in TUN mode, install a blackhole default
//! route so traffic doesn't silently leak out the OS's normal interfaces. The
//! user must explicitly release (or restart the tunnel) to regain connectivity.
//!
//! Implementation: we shell out to `route.exe` for portability — Windows API
//! routing manipulation is fiddly and `route.exe` is on every Windows install.
//!
//! The blackhole route is `0.0.0.0/0` → `127.0.0.1` with metric 1, which beats
//! the default gateway and drops outbound traffic at the loopback.
//!
//! Config + state are persisted to `%APPDATA%\Riptide\kill_switch.json` so a
//! crash that triggered the switch is visible across app restarts.

use crate::utils::process::CommandExt;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;

use crate::utils::windows_dirs::WindowsDirs;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const CONFIG_FILENAME: &str = "kill_switch.json";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct KillSwitchState {
    /// User opted in to the kill switch.
    #[serde(default)]
    pub enabled: bool,
    /// True iff the blackhole route is currently installed.
    #[serde(default)]
    pub armed: bool,
}

impl KillSwitchState {
    fn path() -> PathBuf {
        WindowsDirs::config_dir().join(CONFIG_FILENAME)
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

/// Install the blackhole route. Idempotent — running twice is harmless because
/// `route add` returns non-zero on duplicate, which we ignore.
pub fn arm() -> Result<(), String> {
    log::warn!("Arming kill switch — installing blackhole default route");
    let output = Command::new("route")
        .args([
            "add",
            "0.0.0.0",
            "mask",
            "0.0.0.0",
            "127.0.0.1",
            "metric",
            "1",
        ])
        .no_window()
        .output()
        .map_err(|e| format!("Failed to run route.exe: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        // "The route addition failed: The object already exists." is fine —
        // we're already armed.
        let combined = format!("{} {}", stderr, stdout).to_lowercase();
        if !combined.contains("already exists") {
            return Err(format!(
                "route add failed: stderr={}, stdout={}",
                stderr.trim(),
                stdout.trim()
            ));
        }
    }

    let mut state = KillSwitchState::load();
    state.armed = true;
    state.save()?;
    Ok(())
}

pub fn release() -> Result<(), String> {
    log::info!("Releasing kill switch — removing blackhole default route");
    let output = Command::new("route")
        .args(["delete", "0.0.0.0", "mask", "0.0.0.0", "127.0.0.1"])
        .no_window()
        .output()
        .map_err(|e| format!("Failed to run route.exe: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        // Already absent is fine.
        let combined = format!("{} {}", stderr, stdout).to_lowercase();
        if !combined.contains("not found") && !combined.contains("element not found") {
            return Err(format!(
                "route delete failed: stderr={}, stdout={}",
                stderr.trim(),
                stdout.trim()
            ));
        }
    }

    let mut state = KillSwitchState::load();
    state.armed = false;
    state.save()?;
    Ok(())
}

// ============== Tauri commands ==============

#[tauri::command]
pub fn get_kill_switch_state() -> KillSwitchState {
    KillSwitchState::load()
}

#[tauri::command]
pub fn set_kill_switch_enabled(enabled: bool) -> Result<(), String> {
    let mut state = KillSwitchState::load();
    state.enabled = enabled;
    // Disabling implicitly releases.
    if !enabled && state.armed {
        release()?;
        // release() rewrites armed=false; reload to keep enabled change.
        let mut state = KillSwitchState::load();
        state.enabled = false;
        state.save()?;
    } else {
        state.save()?;
    }
    Ok(())
}

#[tauri::command]
pub fn kill_switch_release() -> Result<(), String> {
    release()
}
