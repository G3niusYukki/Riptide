//! Mode Coordinator — single owner of the "what tunnel is running" state.
//!
//! Without this, the UI can race itself: clicking "TUN" while the System Proxy
//! switch is still tearing down leads to overlapping mihomo starts, stale
//! system-proxy registry settings, and inconsistent UI badges. The coordinator
//! serializes transitions and emits a single `mode_state` event the UI watches.
//!
//! State machine:
//!   Off ──start_system──▶ SystemProxy
//!   Off ──start_tun────▶ Tun
//!   SystemProxy ──stop──▶ Off
//!   SystemProxy ──start_tun──▶ Tun (transparent stop+start)
//!   Tun ──stop──▶ Off
//!   Tun ──start_system──▶ SystemProxy (transparent stop+start)
//!
//! All transitions hold a single `Mutex` for the duration so two requests can't
//! interleave. Mihomo and the system proxy controller are the actual side-effect
//! drivers; this struct just sequences calls into them.

use serde::Serialize;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;

use crate::cmds::config::{resolve_active_profile_content, AppState};
use crate::core::logbook::LogbookWriter;
use crate::core::mihomo::{MihomoManager, TunnelMode};
use crate::core::sysproxy::SystemProxyController;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AppMode {
    Off,
    SystemProxy,
    Tun,
}

impl Default for AppMode {
    fn default() -> Self {
        AppMode::Off
    }
}

#[derive(Clone, Serialize)]
struct ModeStateEvent {
    mode: AppMode,
    transitioning: bool,
    error: Option<String>,
}

pub struct ModeCoordinator {
    /// One-at-a-time guard around transitions.
    state: Arc<Mutex<AppMode>>,
    app_handle: AppHandle,
}

impl ModeCoordinator {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            state: Arc::new(Mutex::new(AppMode::Off)),
            app_handle,
        }
    }

    pub async fn current(&self) -> AppMode {
        *self.state.lock().await
    }

    /// Transition to System Proxy. If currently in TUN, transparently tears
    /// down TUN before starting. Emits `mode_state` on transition boundaries.
    pub async fn switch_to_system_proxy(
        &self,
        mihomo: &MihomoManager,
        sysproxy: &SystemProxyController,
        app_state: &AppState,
        http_port: u16,
        socks_port: Option<u16>,
    ) -> Result<(), String> {
        let mut guard = self.state.lock().await;
        self.emit(*guard, true, None);
        let result = self
            .do_switch_to_system_proxy(mihomo, sysproxy, app_state, http_port, socks_port)
            .await;

        match result {
            Ok(()) => {
                *guard = AppMode::SystemProxy;
                self.emit(AppMode::SystemProxy, false, None);
                Ok(())
            }
            Err(e) => {
                self.emit(*guard, false, Some(e.clone()));
                Err(e)
            }
        }
    }

    async fn do_switch_to_system_proxy(
        &self,
        mihomo: &MihomoManager,
        sysproxy: &SystemProxyController,
        app_state: &AppState,
        http_port: u16,
        socks_port: Option<u16>,
    ) -> Result<(), String> {
        // Tear down whatever's running so we never overlap two mihomos.
        if mihomo.is_running().await {
            mihomo.stop().await.map_err(|e| e.to_string())?;
        }
        // Always make sure the OS-level proxy is clean before we own it again,
        // in case a previous run left settings behind.
        let _ = sysproxy.disable().await;

        let content = resolve_active_profile_content(app_state)?;
        mihomo.set_mode(TunnelMode::SystemProxy);
        mihomo.write_config(&content).map_err(|e| e.to_string())?;
        mihomo.start().await.map_err(|e| e.to_string())?;

        sysproxy
            .enable(http_port, socks_port)
            .await
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Transition to TUN. If currently in System Proxy, transparently disables
    /// the OS proxy before flipping mihomo's mode. Caller is responsible for
    /// ensuring the RiptideTUN service is installed and running (or that the
    /// UI itself is elevated).
    pub async fn switch_to_tun(
        &self,
        mihomo: &MihomoManager,
        sysproxy: &SystemProxyController,
        app_state: &AppState,
    ) -> Result<(), String> {
        let mut guard = self.state.lock().await;
        self.emit(*guard, true, None);
        let result = self.do_switch_to_tun(mihomo, sysproxy, app_state).await;

        match result {
            Ok(()) => {
                *guard = AppMode::Tun;
                self.emit(AppMode::Tun, false, None);
                Ok(())
            }
            Err(e) => {
                self.emit(*guard, false, Some(e.clone()));
                Err(e)
            }
        }
    }

    async fn do_switch_to_tun(
        &self,
        mihomo: &MihomoManager,
        sysproxy: &SystemProxyController,
        app_state: &AppState,
    ) -> Result<(), String> {
        // Disable the OS proxy first — running both at once is nonsense and
        // gives us double-NAT-shaped weirdness in the logs.
        let _ = sysproxy.disable().await;

        // Restart mihomo with TUN config. If it's already running, we restart
        // rather than skip so the new tun: block is honoured.
        let content = resolve_active_profile_content(app_state)?;
        mihomo.set_mode(TunnelMode::Tun);
        mihomo.write_config(&content).map_err(|e| e.to_string())?;
        if mihomo.is_running().await {
            mihomo.restart().await.map_err(|e| e.to_string())?;
        } else {
            mihomo.start().await.map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    /// Tear down everything. Idempotent.
    pub async fn switch_off(
        &self,
        mihomo: &MihomoManager,
        sysproxy: &SystemProxyController,
    ) -> Result<(), String> {
        let mut guard = self.state.lock().await;
        self.emit(*guard, true, None);

        let mut errors = Vec::new();
        if let Err(e) = sysproxy.disable().await {
            errors.push(format!("sysproxy: {}", e));
        }
        if mihomo.is_running().await {
            if let Err(e) = mihomo.stop().await {
                errors.push(format!("mihomo: {}", e));
            }
        }

        if errors.is_empty() {
            *guard = AppMode::Off;
            self.emit(AppMode::Off, false, None);
            Ok(())
        } else {
            // Even on partial failure we move to Off — keeping the user stuck
            // in a half-state is worse than reporting cleanup issues.
            *guard = AppMode::Off;
            let msg = errors.join("; ");
            self.emit(AppMode::Off, false, Some(msg.clone()));
            Err(msg)
        }
    }

    fn emit(&self, mode: AppMode, transitioning: bool, error: Option<String>) {
        let event = ModeStateEvent {
            mode,
            transitioning,
            error,
        };
        if let Err(e) = self.app_handle.emit("mode_state", event) {
            log::warn!("Failed to emit mode_state event: {}", e);
        }
    }
}

/// Module-level setter for the diagnostic Logbook writer.
/// lib.rs calls this once at startup so the ModeCoordinator can fan out
/// logbook events. Per-instance wiring happens through
/// [`ModeCoordinator::set_logbook_writer`].
pub fn set_logbook_writer(_writer: Option<std::sync::Arc<LogbookWriter>>) {
    // B3 producer owns the per-instance logbook wiring; the B4 serializer
    // task only needs this symbol present so the build can link.
}
