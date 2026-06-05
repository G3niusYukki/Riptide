//! Recovery watchdog — detects sleep/wake and network changes that mihomo
//! doesn't recover from on its own.
//!
//! We deliberately avoid the heavy native paths (hidden window with
//! `WM_POWERBROADCAST`, `NotifyIpInterfaceChange`, `PowerRegisterSuspendResume`)
//! and use a simple monotonic-clock heuristic:
//!
//!   - Every 5s, compare `Instant::now()` to the previous tick. A jump
//!     significantly larger than the expected 5s indicates the OS slept.
//!   - On the same cadence, snapshot the default gateway / active interface;
//!     a change indicates the user switched WiFi networks or unplugged ethernet.
//!
//! Either signal triggers a mihomo REST health probe. If the probe fails twice
//! in a row, restart mihomo with the current config. This catches the long
//! tail of issues where mihomo's gVisor TUN stack gets confused after the
//! interface list shifts under it.

use std::sync::{Arc, Mutex as StdMutex, OnceLock};
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::Mutex;

use crate::core::logbook::{LogCategory, LogEntry, LogLevel, LogbookWriter};
use crate::core::mihomo::MihomoManager;
use crate::core::mihomo_api::MihomoApiClient;

const TICK_INTERVAL: Duration = Duration::from_secs(5);
/// If the gap between two ticks is larger than this, assume the machine slept.
const SLEEP_DETECTION_THRESHOLD: Duration = Duration::from_secs(30);
const HEALTH_PROBE_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Clone, Serialize)]
struct RecoveryEvent {
    reason: &'static str, // "sleep" | "network_change" | "health_fail"
    restarted: bool,
}

pub fn spawn(app_handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        run(app_handle).await;
    });
}

/// Module-level writer slot — the watchdog task is spawned once at
/// startup and holds no struct state we can attach a writer to.
static RECOVERY_LOGBOOK: OnceLock<StdMutex<Option<Arc<LogbookWriter>>>> = OnceLock::new();

fn cell() -> &'static StdMutex<Option<Arc<LogbookWriter>>> {
    RECOVERY_LOGBOOK.get_or_init(|| StdMutex::new(None))
}

/// Install the diagnostic Logbook writer for the recovery watchdog.
/// Called once at app startup, right after `AppState::install_logbook_writer`.
pub fn set_logbook_writer(writer: Option<Arc<LogbookWriter>>) {
    if let Ok(mut g) = cell().lock() {
        *g = writer;
    }
}

#[allow(dead_code)]
fn log_event(level: LogLevel, message: &str) {
    let Some(writer) = cell().lock().ok().and_then(|g| g.clone()) else {
        return;
    };
    writer.send(LogEntry::new(level, LogCategory::Recovery, message));
}

async fn run(app_handle: AppHandle) {
    let mut last_tick = Instant::now();
    let mut last_gateway: Option<String> = read_default_gateway();
    let consecutive_health_fail = Arc::new(Mutex::new(0u32));

    loop {
        tokio::time::sleep(TICK_INTERVAL).await;
        let now = Instant::now();
        let gap = now.duration_since(last_tick);
        last_tick = now;

        let slept = gap > SLEEP_DETECTION_THRESHOLD;
        let current_gateway = read_default_gateway();
        let network_changed = current_gateway != last_gateway;
        if network_changed {
            last_gateway = current_gateway.clone();
        }

        if !slept && !network_changed {
            continue;
        }

        // Only attempt recovery if mihomo is supposed to be running.
        let mihomo = match app_handle.try_state::<MihomoManager>() {
            Some(m) => m,
            None => continue,
        };
        if !mihomo.is_running().await {
            continue;
        }

        let reason: &'static str = if slept {
            "sleep"
        } else {
            "network_change"
        };
        log::info!(
            "Recovery watchdog: {} detected (gap={}s, gw={:?})",
            reason,
            gap.as_secs(),
            current_gateway
        );

        let port = mihomo.api_port_snapshot().await;
        let secret = mihomo.api_secret_snapshot().await;
        let client = MihomoApiClient::new(format!("http://127.0.0.1:{}", port), secret);
        let healthy = probe(&client).await;

        if healthy {
            *consecutive_health_fail.lock().await = 0;
            let _ = app_handle.emit(
                "recovery_health_ok",
                RecoveryEvent {
                    reason,
                    restarted: false,
                },
            );
            continue;
        }

        let mut fails = consecutive_health_fail.lock().await;
        *fails += 1;
        let should_restart = *fails >= 2;
        drop(fails);

        if !should_restart {
            log::warn!(
                "Recovery watchdog: mihomo health probe failed (1/2). Waiting for confirmation."
            );
            continue;
        }

        log::warn!("Recovery watchdog: restarting mihomo");
        match mihomo.restart().await {
            Ok(()) => {
                *consecutive_health_fail.lock().await = 0;
                let _ = app_handle.emit(
                    "recovery_restarted",
                    RecoveryEvent {
                        reason,
                        restarted: true,
                    },
                );
            }
            Err(e) => {
                log::error!("Recovery restart failed: {}", e);
                let _ = app_handle.emit(
                    "recovery_failed",
                    RecoveryEvent {
                        reason,
                        restarted: false,
                    },
                );
            }
        }
    }
}

async fn probe(client: &MihomoApiClient) -> bool {
    // The cheapest mihomo endpoint that returns a meaningful payload.
    let probe = tokio::time::timeout(HEALTH_PROBE_TIMEOUT, client.get_proxies()).await;
    matches!(probe, Ok(Ok(_)))
}

/// Read the current default gateway IPv4 by shelling out to `route print`.
/// Best-effort — returns `None` on parse failure. We compare consecutive reads
/// for equality, so transient parse blips just look like one missed tick.
fn read_default_gateway() -> Option<String> {
    use crate::utils::process::CommandExt;
    use std::process::Command;

    let output = Command::new("route")
        .arg("print")
        .arg("0.0.0.0")
        .no_window()
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    // Look for a line beginning with "          0.0.0.0          0.0.0.0     <gateway> ..."
    text.lines()
        .find_map(|line| {
            let trimmed = line.trim();
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            if parts.len() >= 3 && parts[0] == "0.0.0.0" && parts[1] == "0.0.0.0" {
                Some(parts[2].to_string())
            } else {
                None
            }
        })
}
