//! Subscription auto-refresh scheduler.
//!
//! On startup we wait 30 seconds (let the rest of the app settle) then begin
//! a 60-second poll loop. Each tick scans every profile and refreshes any
//! whose subscription URL is set, `update_interval_secs` is set, and whose
//! `last_updated_at + interval < now`. Failures are logged and don't stall
//! the loop — a next-tick retry costs nothing.
//!
//! Cancellation: this runs for the lifetime of the app. We don't bother with
//! a stop signal — Tauri shutdown will tear the runtime down with us.

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;
use tauri::{AppHandle, Emitter, Manager};

use crate::cmds::config::{refresh_profile_impl, AppState};

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
        None => return, // app teardown.
    };

    // Snapshot due profile ids so we don't hold the lock across awaits.
    let due: Vec<(String, String)> = {
        let profiles = state.profiles.lock().unwrap();
        let now = Utc::now();
        profiles
            .iter()
            .filter_map(|p| {
                let url = p.metadata.source_url.as_ref()?;
                let interval = p.metadata.update_interval_secs?;
                let last = p.metadata.last_updated_at.unwrap_or_else(|| {
                    // Treat "never refreshed" as ancient so first-tick after import is fine.
                    chrono::DateTime::<Utc>::MIN_UTC
                });
                let elapsed = now.signed_duration_since(last).to_std().ok()?;
                if elapsed.as_secs() >= interval && !url.is_empty() {
                    Some((p.id.clone(), p.name.clone()))
                } else {
                    None
                }
            })
            .collect()
    };

    for (id, name) in due {
        match refresh_profile_impl(&id, &state).await {
            Ok(_) => {
                let _ = app_handle.emit(
                    "profile_refreshed",
                    RefreshedEvent {
                        profile_id: id,
                        profile_name: name,
                    },
                );
            }
            Err(e) => {
                log::warn!("Auto-refresh failed for '{}': {}", name, e);
                let _ = app_handle.emit(
                    "profile_refresh_error",
                    RefreshErrorEvent {
                        profile_id: id,
                        error: e,
                    },
                );
            }
        }
    }
}

// Manage `Arc<AppHandle>` lint silencer — the import only exists for clarity in callers.
#[allow(dead_code)]
fn _phantom(_a: Arc<AppHandle>) {}
