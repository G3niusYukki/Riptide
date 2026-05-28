//! Subscription auto-refresh scheduler.
//!
//! On startup we wait 30 seconds (let the rest of the app settle) then begin
//! a 60-second poll loop. Each tick scans every profile and refreshes any
//! whose subscription URL is set, `update_interval_secs` is set, and whose
//! `last_updated_at + interval < now`. Failures are logged and don't stall
//! the loop — a next-tick retry costs nothing.

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;
use tauri::{AppHandle, Emitter, Manager};

#[cfg(target_os = "windows")]
use crate::cmds::config::refresh_profile_impl;
use crate::cmds::config::AppState;

const STARTUP_DELAY: Duration = Duration::from_secs(30);
const POLL_INTERVAL: Duration = Duration::from_secs(60);

#[derive(Clone, serde::Serialize)]
struct RefreshedEvent {
    profile_id: String,
    profile_name: String,
}

#[derive(Clone, serde::Serialize)]
struct RefreshErrorEvent {
    profile_id: String,
    error: String,
}

pub fn spawn(app_handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(STARTUP_DELAY).await;
        loop {
            tick(&app_handle).await;
            tokio::time::sleep(POLL_INTERVAL).await;
        }
    });
}

async fn tick(app_handle: &AppHandle) {
    let state = match app_handle.try_state::<AppState>() {
        Some(s) => s,
        None => return,
    };

    let due: Vec<(String, String)> = {
        let profiles = state.profiles.lock().unwrap();
        let now = Utc::now();
        profiles.iter().filter_map(|p| {
            let url = p.metadata.source_url.as_ref()?;
            let interval = p.metadata.update_interval_secs?;
            let last = p.metadata.last_updated_at.unwrap_or(chrono::DateTime::<Utc>::MIN_UTC);
            let elapsed = now.signed_duration_since(last).to_std().ok()?;
            if elapsed.as_secs() >= interval && !url.is_empty() {
                Some((p.id.clone(), p.name.clone()))
            } else {
                None
            }
        }).collect()
    };

    for (id, name) in due {
        #[cfg(target_os = "windows")]
        {
            match refresh_profile_impl(&id, &state).await {
                Ok(_) => {
                    let _ = app_handle.emit("profile_refreshed", RefreshedEvent {
                        profile_id: id,
                        profile_name: name,
                    });
                }
                Err(e) => {
                    log::warn!("Auto-refresh failed for '{}': {}", name, e);
                    let _ = app_handle.emit("profile_refresh_error", RefreshErrorEvent {
                        profile_id: id,
                        error: e,
                    });
                }
            }
        }
        #[cfg(not(target_os = "windows"))]
        {
            log::info!("Subscription refresh skipped on non-Windows: {} ({})", name, id);
        }
    }
}

#[allow(dead_code)]
fn _phantom(_a: Arc<AppHandle>) {}
