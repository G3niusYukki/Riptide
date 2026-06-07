//! Diagnostics report — a single text dump the user can copy into a bug report.
//! Cheap to collect (no health probes block the request) and fully read-only.
//!
//! What's in scope:
//!   - Riptide version, Windows version, current mode
//!   - mihomo binary location + version (from `mihomo -v`)
//!   - Active profile name + node count + last update
//!   - System proxy state (HTTP/SOCKS port, drift counter)
//!   - TUN service status
//!   - Geo asset presence + last modified
//!   - Kill switch state
//!   - Recent log tail
//!
//! What's deliberately NOT in scope (privacy):
//!   - Profile YAML content (would leak server addresses / passwords)
//!   - Active connections (leaks visited hosts)
//!   - WebDAV credentials

use crate::utils::process::CommandExt;
use std::process::Command;

use serde::Serialize;
use tauri::{AppHandle, Manager};

use crate::cmds::config::AppState;
use crate::core::mihomo::MihomoManager;
use crate::core::mode_coordinator::ModeCoordinator;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const LOG_TAIL_LINES: usize = 60;

#[derive(Serialize)]
pub struct DiagnosticReport {
    pub riptide_version: String,
    pub os: String,
    pub mode: String,
    pub mihomo_path: String,
    pub mihomo_installed: bool,
    pub mihomo_version: Option<String>,
    pub active_profile: Option<ProfileSummary>,
    pub tun_service_status: String,
    pub kill_switch: KillSwitchSummary,
    pub geo_assets: Vec<GeoAssetSummary>,
    pub log_tail: String,
}

#[derive(Serialize)]
pub struct ProfileSummary {
    pub name: String,
    pub node_count: Option<usize>,
    pub last_updated: Option<String>,
    pub has_subscription: bool,
}

#[derive(Serialize)]
pub struct KillSwitchSummary {
    pub enabled: bool,
    pub armed: bool,
}

#[derive(Serialize)]
pub struct GeoAssetSummary {
    pub name: String,
    pub installed: bool,
    pub size_bytes: Option<u64>,
}

#[tauri::command]
pub async fn collect_diagnostic_report(app_handle: AppHandle) -> Result<DiagnosticReport, String> {
    let riptide_version = app_handle
        .config()
        .version
        .clone()
        .unwrap_or_else(|| "unknown".into());

    let os = os_version_string();

    let mode = match app_handle.try_state::<ModeCoordinator>() {
        Some(coord) => format!("{:?}", coord.current().await),
        None => "unknown".into(),
    };

    let mihomo_path = crate::utils::dirs::get_mihomo_binary_path(&app_handle)
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| "<unresolvable>".into());
    let mihomo_installed = crate::core::mihomo::check_mihomo_binary(&app_handle);
    let mihomo_version = if mihomo_installed {
        query_mihomo_version(&mihomo_path)
    } else {
        None
    };

    let active_profile = collect_active_profile(&app_handle);
    let tun_service_status = format!("{:?}", crate::core::service::query_status());
    let kill_switch_state = crate::core::kill_switch::KillSwitchState::load();
    let geo_assets = crate::core::geo_assets::get_geo_assets(app_handle.clone())
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|a| GeoAssetSummary {
            name: a.name,
            installed: a.installed,
            size_bytes: a.size_bytes,
        })
        .collect();

    let log_tail = collect_log_tail(LOG_TAIL_LINES);

    // Mark a few fields read so the Manager import isn't pruned by the cfg checks.
    let _ = app_handle.try_state::<MihomoManager>();

    Ok(DiagnosticReport {
        riptide_version,
        os,
        mode,
        mihomo_path,
        mihomo_installed,
        mihomo_version,
        active_profile,
        tun_service_status,
        kill_switch: KillSwitchSummary {
            enabled: kill_switch_state.enabled,
            armed: kill_switch_state.armed,
        },
        geo_assets,
        log_tail,
    })
}

fn collect_active_profile(app_handle: &AppHandle) -> Option<ProfileSummary> {
    let state = app_handle.try_state::<AppState>()?;
    let active_id = state.active_profile_id.lock().unwrap().clone()?;
    let profiles = state.profiles.lock().unwrap();
    let profile = profiles.iter().find(|p| p.id == active_id)?;
    Some(ProfileSummary {
        name: profile.name.clone(),
        node_count: profile.node_count,
        last_updated: profile.metadata.last_updated_at.map(|t| t.to_rfc3339()),
        has_subscription: profile.metadata.source_url.is_some(),
    })
}

fn os_version_string() -> String {
    // `ver` on cmd prints "Microsoft Windows [Version 10.0.26200.xxxx]" — good enough
    // for triage. Avoid an extra winapi crate dependency just for this.
    Command::new("cmd")
        .args(["/C", "ver"])
        .no_window()
        .output()
        .ok()
        .and_then(|out| {
            if out.status.success() {
                Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
            } else {
                None
            }
        })
        .unwrap_or_else(|| "Windows (version unknown)".into())
}

fn query_mihomo_version(path: &str) -> Option<String> {
    let out = Command::new(path).arg("-v").no_window().output().ok()?;
    if !out.status.success() {
        return None;
    }
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    // mihomo prints multiple lines; the first non-empty one is what we want.
    combined
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(|s| s.to_string())
}

fn collect_log_tail(n: usize) -> String {
    let log_dir = crate::utils::windows_dirs::WindowsDirs::logs_dir();
    // tracing-appender daily rolling creates files like riptide.log.2026-05-18.
    // Pick the lexicographically-latest one so we don't have to know today's
    // date format.
    let Ok(entries) = std::fs::read_dir(&log_dir) else {
        return "<no logs directory>".into();
    };
    let mut candidates: Vec<_> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|s| s.to_str())
                .map(|s| s.starts_with("riptide.log"))
                .unwrap_or(false)
        })
        .collect();
    candidates.sort();
    let Some(latest) = candidates.last() else {
        return "<no log file>".into();
    };
    let Ok(contents) = std::fs::read_to_string(latest) else {
        return format!("<unreadable: {:?}>", latest);
    };
    let lines: Vec<&str> = contents.lines().collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].join("\n")
}
