//! SingBox runtime manager — v2.4.x skeleton only.
//!
//! The v2.5.0 deliverable will flesh this out into a `Child` process
//! supervisor that mirrors `MihomoManager` (start / stop / restart /
//! `is_running` / config generation / TUN-mode handling). v2.4.x only
//! needs the *shape* so:
//!
//! 1. The frontend / Tauri command surface can reference
//!    `SingBoxRuntimeManager::status()` and see "installed: false" on a
//!    fresh install.
//! 2. Future v2.5.0 callers can `?`-bubble from `start` / `stop` and get
//!    a typed [`SingBoxError`] (currently always `NotImplementedYet`).
//!
//! Deliberately empty: no `Child`, no `Arc<Mutex<...>>`, no Tauri
//! `AppHandle`. Adding state now would just be churn when the v2.5.0 plan
//! lands — keep the door open, don't lock it in.

use serde::Serialize;

use crate::core::singbox::error::SingBoxError;

/// Snapshot of the SingBox sidecar state, suitable for sending to the
/// frontend as part of a Tauri command response.
///
/// Kept intentionally tiny for v2.4.x. v2.5.0 may add fields like
/// `pid: Option<u32>`, `last_error: Option<String>`, `started_at:
/// Option<chrono::DateTime<Utc>>`, etc.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct SingBoxStatus {
    /// True iff a `sing-box.exe` was found at the expected on-disk path
    /// at status-probe time. Independent of whether the process is
    /// actually running — a binary can be installed but not started.
    pub installed: bool,
    /// True iff the SingBox process is currently running. v2.4.x always
    /// reports `false` because no `start` path can succeed.
    pub running: bool,
    /// Reported SingBox version string (`sing-box version`), if the
    /// binary is installed and the v2.5.0 implementation can shell out
    /// to query it. v2.4.x always reports `None`.
    pub version: Option<String>,
}

/// Skeleton runtime manager for the SingBox sidecar.
///
/// v2.4.x: every method is a no-op stub. `status()` is the one method
/// callers can rely on — it always returns
/// [`SingBoxStatus { installed: false, running: false, version: None }`]
/// so UI surfaces can show a stable "not installed / not running" badge.
///
/// v2.5.0 will replace the internals with a real `Child` supervisor
/// modelled on `MihomoManager` (see `crate::core::mihomo`).
#[derive(Debug, Default, Clone)]
pub struct SingBoxRuntimeManager {
    // Intentionally empty for v2.4.x. v2.5.0 will add:
    //   - app_handle: AppHandle
    //   - process: Arc<Mutex<Option<Child>>>
    //   - mode: StdMutex<TunnelMode>
    //   - expected_exit: Arc<StdMutex<bool>>
    //   - tun_options: StdMutex<TunOptions>
    _priv: (),
}

impl SingBoxRuntimeManager {
    /// Build a new, empty manager. Cheap to construct, no I/O.
    pub fn new() -> Self {
        Self::default()
    }

    /// Start the SingBox sidecar process.
    ///
    /// v2.4.x stub: always returns [`SingBoxError::NotImplementedYet`].
    /// The v2.5.0 implementation will:
    /// 1. Call `SingBoxDownloader::ensure_present()` to fetch the binary.
    /// 2. Generate a SingBox config from the active profile.
    /// 3. Spawn the process with stdout/stderr redirected to
    ///    `WindowsDirs::logs_dir()/singbox.log`.
    /// 4. Spawn a watcher task to distinguish expected vs crash exits.
    pub async fn start(&self) -> Result<(), SingBoxError> {
        Err(SingBoxError::NotImplementedYet)
    }

    /// Stop the SingBox sidecar process.
    ///
    /// v2.4.x stub: always returns [`SingBoxError::NotImplementedYet`].
    /// The v2.5.0 implementation will set an "expected exit" flag so the
    /// watcher doesn't fire a crash event, then `kill()` the child.
    pub async fn stop(&self) -> Result<(), SingBoxError> {
        Err(SingBoxError::NotImplementedYet)
    }

    /// Snapshot of the current state. v2.4.x always reports
    /// `installed: false, running: false, version: None`.
    ///
    /// Marked `&self` (sync, not async) so it can be polled cheaply from
    /// both the UI and the recovery watchdog without contending on a
    /// mutex; v2.5.0 may switch to a real probe if needed.
    pub fn status(&self) -> SingBoxStatus {
        SingBoxStatus::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Task spec test 3: status defaults reflect "not installed / not running".
    #[test]
    fn runtime_manager_status_is_uninstalled_by_default() {
        let mgr = SingBoxRuntimeManager::new();
        let status = mgr.status();
        assert!(
            !status.installed,
            "default status should report not installed"
        );
        assert!(!status.running, "default status should report not running");
        assert!(
            status.version.is_none(),
            "default status should report no version"
        );
    }

    #[test]
    fn default_status_matches_status_call() {
        // Status::default() and SingBoxRuntimeManager::new().status() must
        // agree — guards against drift if a future change tweaks either.
        let mgr = SingBoxRuntimeManager::new();
        assert_eq!(mgr.status(), SingBoxStatus::default());
    }

    #[tokio::test]
    async fn start_returns_not_implemented() {
        let mgr = SingBoxRuntimeManager::new();
        let result = mgr.start().await;
        assert!(matches!(result, Err(SingBoxError::NotImplementedYet)));
    }

    #[tokio::test]
    async fn stop_returns_not_implemented() {
        let mgr = SingBoxRuntimeManager::new();
        let result = mgr.stop().await;
        assert!(matches!(result, Err(SingBoxError::NotImplementedYet)));
    }
}
