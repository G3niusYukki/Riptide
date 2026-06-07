//! System proxy control.
//!
//! Windows: uses the `sysproxy` crate (WinINet registry API).
//! Linux: no-op stub (system proxy managed via gsettings/D-Bus externally).
//! macOS: no-op stub (system proxy managed by the Swift layer).

use std::sync::{Arc, Mutex as StdMutex, OnceLock};
use std::time::Duration;

use crate::core::logbook::{LogCategory, LogEntry, LogLevel, LogbookWriter};
#[cfg(target_os = "windows")]
use sysproxy::Sysproxy;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

/// Polling interval for the drift detector.
const GUARD_POLL_INTERVAL: Duration = Duration::from_secs(3);

/// Maximum re-apply attempts before backing off.
const MAX_REAPPLY_BEFORE_BACKOFF: u32 = 5;

/// Module-level writer slot — `SystemProxyController` is held on
/// `tauri::State` and wired before the writer is installed, so the
/// writer is keyed off a `OnceLock` in module scope.
static SYSPROXY_LOGBOOK: OnceLock<StdMutex<Option<Arc<LogbookWriter>>>> = OnceLock::new();

fn sysproxy_cell() -> &'static StdMutex<Option<Arc<LogbookWriter>>> {
    SYSPROXY_LOGBOOK.get_or_init(|| StdMutex::new(None))
}

/// Install the diagnostic Logbook writer for the system proxy guard.
/// Called once at app startup, right after
/// `AppState::install_logbook_writer`.
pub fn set_logbook_writer(writer: Option<Arc<LogbookWriter>>) {
    if let Ok(mut g) = sysproxy_cell().lock() {
        *g = writer;
    }
}

#[allow(dead_code)]
fn log_event(level: LogLevel, message: impl Into<String>) {
    let Some(writer) = sysproxy_cell().lock().ok().and_then(|g| g.clone()) else {
        return;
    };
    writer.send(LogEntry::new(level, LogCategory::Sysproxy, message));
}

// ── Windows implementation ───────────────────────────────────────

#[cfg(target_os = "windows")]
mod windows_impl {
    use super::*;

    #[derive(Clone, serde::Serialize)]
    pub(super) struct DriftEvent {
        pub(super) observed: ObservedProxy,
        pub(super) expected: ObservedProxy,
        pub(super) reapply_count: u32,
        pub(super) gave_up: bool,
    }

    #[derive(Clone, Debug, serde::Serialize)]
    pub(super) struct ObservedProxy {
        pub(super) enable: bool,
        pub(super) host: String,
        pub(super) port: u16,
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

        pub async fn bind_app_handle(&self, handle: AppHandle) {
            *self.app_handle.lock().await = Some(handle);
        }

        pub async fn enable(&self, http_port: u16, socks_port: Option<u16>) -> anyhow::Result<()> {
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

    async fn guard_loop(http_state: Arc<Mutex<Option<Sysproxy>>>, app_handle: Option<AppHandle>) {
        let mut reapply_count: u32 = 0;
        let mut backed_off = false;

        loop {
            tokio::time::sleep(GUARD_POLL_INTERVAL).await;

            let expected = match http_state.lock().await.clone() {
                Some(p) => p,
                None => return,
            };

            let observed = match tokio::task::spawn_blocking(Sysproxy::get_system_proxy).await {
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

            let matches =
                observed.enable && observed.host == expected.host && observed.port == expected.port;
            if matches {
                reapply_count = 0;
                backed_off = false;
                continue;
            }

            if backed_off {
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
                let to_apply = expected.clone();
                let res = tokio::task::spawn_blocking(move || to_apply.set_system_proxy()).await;
                match res {
                    Ok(Ok(())) => {
                        log::warn!("System proxy drifted, restored to expected");
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

    #[cfg(test)]
    mod tests {
        //! `ObservedProxy` projection round-trip.
        //!
        //! The drift detector compares `expected` (the value we wrote
        //! via `enable()`) to `observed` (what `Sysproxy::get_system_proxy`
        //! reads back from the WinINet registry). The projection MUST
        //! carry every field — losing `host` or `port` would silently
        //! turn a real drift into a no-op. We lock that down here so
        //! the field set can't shrink without a failing test.

        use super::*;

        #[test]
        fn observed_proxy_projects_all_fields() {
            let raw = Sysproxy {
                enable: true,
                host: "127.0.0.1".to_string(),
                port: 7890,
                bypass: "<local>".to_string(),
            };
            let observed = ObservedProxy::from(&raw);
            assert!(observed.enable);
            assert_eq!(observed.host, "127.0.0.1");
            assert_eq!(observed.port, 7890);
        }
    }
}

#[cfg(target_os = "windows")]
pub use windows_impl::SystemProxyController;

// ── Linux / macOS stub ──────────────────────────────────────────

#[cfg(not(target_os = "windows"))]
pub struct SystemProxyController;

#[cfg(not(target_os = "windows"))]
impl SystemProxyController {
    pub fn new() -> Self {
        Self
    }

    pub async fn bind_app_handle(&self, _handle: AppHandle) {}

    pub async fn enable(&self, http_port: u16, _socks_port: Option<u16>) -> anyhow::Result<()> {
        log::info!("System proxy enable (stub): port={}", http_port);
        Ok(())
    }

    pub async fn disable(&self) -> anyhow::Result<()> {
        log::info!("System proxy disable (stub)");
        Ok(())
    }

    pub async fn is_enabled(&self) -> bool {
        false
    }

    pub fn get_current_proxy() -> anyhow::Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    //! Cross-platform shape tests for the `SystemProxyController`
    //! surface. The actual Windows registry writes (`enable` / `disable`)
    //! hit the live WinINet config and are intentionally not unit-tested
    //! here — those paths are covered by the manual QA matrix in
    //! `docs/WINDOWS-CATCHUP-PLAN.md` § B1.3. The tests below lock down
    //! the bits that have caused regressions in the past: the
    //! non-Windows stub's "always-disabled" invariant and the
    //! Windows-only `ObservedProxy` projection from a `Sysproxy` value
    //! (the drift detector compares this shape against what the
    //! registry actually says).

    #[cfg(not(target_os = "windows"))]
    use super::SystemProxyController;

    #[tokio::test]
    #[cfg(not(target_os = "windows"))]
    async fn non_windows_stub_starts_disabled() {
        // The Linux/macOS stub is used when compiling on CI hosts and
        // for cross-platform dev. A fresh controller must report
        // "not enabled" so the UI's first paint doesn't falsely claim
        // the system proxy is active.
        let controller = SystemProxyController::new();
        assert!(!controller.is_enabled().await);
    }

    #[tokio::test]
    #[cfg(not(target_os = "windows"))]
    async fn non_windows_stub_enable_and_disable_are_idempotent() {
        // On non-Windows, `enable` / `disable` are no-ops that return
        // `Ok(())`. The state bit must not flip — the controller is a
        // pure log-only stub. This guards against an accidental
        // platform-specific regression where someone "fixed" the
        // stub to track state and broke cross-platform builds.
        let controller = SystemProxyController::new();
        controller.enable(7890, Some(7891)).await.unwrap();
        assert!(
            !controller.is_enabled().await,
            "stub must not track enable state"
        );
        controller.disable().await.unwrap();
        assert!(
            !controller.is_enabled().await,
            "stub must not track disable state"
        );
    }
}
