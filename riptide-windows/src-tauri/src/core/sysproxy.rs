//! System proxy control using the `sysproxy` crate.
//!
//! The controller maintains a desired-state cache (`http_proxy`/`socks_proxy`)
//! and, while enabled, runs a background "guard" task that re-applies the
//! desired state whenever an external actor (Group Policy, another app, the
//! user via Settings) changes the OS-level proxy. Guard events surface to the
//! UI via the `system_proxy_drift` Tauri event.

use std::sync::Arc;
use std::time::Duration;

use sysproxy::Sysproxy;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

/// Polling interval for the drift detector. Long enough that we don't burn CPU
/// reading the registry, short enough that a brief misroute heals quickly.
const GUARD_POLL_INTERVAL: Duration = Duration::from_secs(3);

/// Maximum number of consecutive re-apply attempts before backing off. If we
/// can't keep ownership of the proxy setting, something is fighting us and we
/// should surface that to the user rather than re-applying forever.
const MAX_REAPPLY_BEFORE_BACKOFF: u32 = 5;

#[derive(Clone, serde::Serialize)]
struct DriftEvent {
    /// What the OS reported when we polled (best-effort representation).
    observed: ObservedProxy,
    /// What we expected (and re-applied).
    expected: ObservedProxy,
    /// Reapply attempts so far in this drift episode. Reset on success+match.
    reapply_count: u32,
    /// True once we've hit `MAX_REAPPLY_BEFORE_BACKOFF` and stopped fighting.
    gave_up: bool,
}

#[derive(Clone, Debug, serde::Serialize)]
struct ObservedProxy {
    enable: bool,
    host: String,
    port: u16,
}

impl From<&Sysproxy> for ObservedProxy {
    fn from(s: &Sysproxy) -> Self {
        Self {
            enable: s.enable,
            host: s.host.clone(),
            port: s.port,
        }
    }
}

pub struct SystemProxyController {
    http_proxy: Arc<Mutex<Option<Sysproxy>>>,
    socks_proxy: Arc<Mutex<Option<Sysproxy>>>,
    guard_handle: Mutex<Option<JoinHandle<()>>>,
    app_handle: Mutex<Option<AppHandle>>,
}

impl SystemProxyController {
    pub fn new() -> Self {
        Self {
            http_proxy: Arc::new(Mutex::new(None)),
            socks_proxy: Arc::new(Mutex::new(None)),
            guard_handle: Mutex::new(None),
            app_handle: Mutex::new(None),
        }
    }

    /// Bind a Tauri app handle so the guard can emit drift events. Called once
    /// from `lib.rs::run::setup`.
    pub async fn bind_app_handle(&self, handle: AppHandle) {
        *self.app_handle.lock().await = Some(handle);
    }

    pub async fn enable(&self, http_port: u16, socks_port: Option<u16>) -> anyhow::Result<()> {
        // Apply HTTP proxy.
        let http = Sysproxy {
            enable: true,
            host: "127.0.0.1".to_string(),
            port: http_port,
            bypass: "".to_string(),
        };
        http.set_system_proxy()?;
        *self.http_proxy.lock().await = Some(http);

        if let Some(port) = socks_port {
            let socks = Sysproxy {
                enable: true,
                host: "127.0.0.1".to_string(),
                port,
                bypass: "".to_string(),
            };
            socks.set_system_proxy()?;
            *self.socks_proxy.lock().await = Some(socks);
        }

        self.start_guard().await;

        log::info!(
            "System proxy enabled: HTTP={}, SOCKS={:?} (guard armed)",
            http_port,
            socks_port
        );
        Ok(())
    }

    pub async fn disable(&self) -> anyhow::Result<()> {
        // Tear down the guard first so it doesn't fight our `disable` call.
        self.stop_guard().await;

        if let Some(ref proxy) = *self.http_proxy.lock().await {
            let disabled = Sysproxy {
                enable: false,
                host: proxy.host.clone(),
                port: proxy.port,
                bypass: proxy.bypass.clone(),
            };
            disabled.set_system_proxy()?;
        }
        *self.http_proxy.lock().await = None;

        if let Some(ref proxy) = *self.socks_proxy.lock().await {
            let disabled = Sysproxy {
                enable: false,
                host: proxy.host.clone(),
                port: proxy.port,
                bypass: proxy.bypass.clone(),
            };
            disabled.set_system_proxy()?;
        }
        *self.socks_proxy.lock().await = None;

        log::info!("System proxy disabled");
        Ok(())
    }

    pub async fn is_enabled(&self) -> bool {
        self.http_proxy.lock().await.is_some()
    }

    pub fn get_current_proxy() -> anyhow::Result<Sysproxy> {
        Sysproxy::get_system_proxy()
            .map_err(|e| anyhow::anyhow!("Failed to get system proxy: {:?}", e))
    }

    async fn start_guard(&self) {
        // Replace any prior guard. If one is already running for a previous
        // enable cycle we'd race ourselves.
        self.stop_guard().await;

        let http = self.http_proxy.clone();
        let app = self.app_handle.lock().await.clone();
        let handle = tokio::spawn(async move {
            guard_loop(http, app).await;
        });
        *self.guard_handle.lock().await = Some(handle);
    }

    async fn stop_guard(&self) {
        if let Some(h) = self.guard_handle.lock().await.take() {
            h.abort();
        }
    }
}

/// Background loop: every `GUARD_POLL_INTERVAL`, ensure the OS proxy still
/// matches our HTTP expectation. Re-apply on mismatch. Back off after too many
/// consecutive failures.
async fn guard_loop(
    http_state: Arc<Mutex<Option<Sysproxy>>>,
    app_handle: Option<AppHandle>,
) {
    let mut reapply_count: u32 = 0;
    let mut backed_off = false;

    loop {
        tokio::time::sleep(GUARD_POLL_INTERVAL).await;

        let expected = match http_state.lock().await.clone() {
            Some(p) => p,
            None => return, // disabled while we were sleeping; bail.
        };

        // Spawn the (blocking) registry read on the blocking pool — sysproxy's
        // `get_system_proxy` hits the registry and we don't want to stall the
        // async runtime.
        let observed = match tokio::task::spawn_blocking(Sysproxy::get_system_proxy)
            .await
        {
            Ok(Ok(s)) => s,
            Ok(Err(e)) => {
                log::warn!("System proxy guard: read failed: {:?}", e);
                continue;
            }
            Err(e) => {
                log::warn!("System proxy guard: join failed: {}", e);
                continue;
            }
        };

        let matches = observed.enable
            && observed.host == expected.host
            && observed.port == expected.port;

        if matches {
            // Healthy: reset the back-off counter so the next drift episode
            // starts fresh.
            reapply_count = 0;
            backed_off = false;
            continue;
        }

        if backed_off {
            // Already gave up; keep polling so we resume the moment something
            // else (e.g., the user) restores our settings.
            continue;
        }

        reapply_count += 1;
        let gave_up = reapply_count >= MAX_REAPPLY_BEFORE_BACKOFF;
        if gave_up {
            backed_off = true;
            log::error!(
                "System proxy drift could not be corrected after {} attempts; backing off",
                reapply_count
            );
        } else {
            // Re-apply on a blocking thread for the same reason as the read.
            let to_apply = expected.clone();
            let res = tokio::task::spawn_blocking(move || to_apply.set_system_proxy()).await;
            match res {
                Ok(Ok(())) => {
                    log::warn!(
                        "System proxy drifted (observed {:?}), restored to expected ({:?})",
                        ObservedProxy::from(&observed),
                        ObservedProxy::from(&expected)
                    );
                }
                Ok(Err(e)) => {
                    log::warn!("System proxy guard: re-apply failed: {:?}", e);
                }
                Err(e) => {
                    log::warn!("System proxy guard: re-apply task join failed: {}", e);
                }
            }
        }

        if let Some(ref app) = app_handle {
            let event = DriftEvent {
                observed: ObservedProxy::from(&observed),
                expected: ObservedProxy::from(&expected),
                reapply_count,
                gave_up,
            };
            if let Err(e) = app.emit("system_proxy_drift", event) {
                log::warn!("Failed to emit system_proxy_drift event: {}", e);
            }
        }
    }
}
