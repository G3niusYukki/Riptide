//! Core business logic modules

pub mod diagnostics;
pub mod engines;
#[cfg(target_os = "windows")]
pub mod gateway;
pub mod geo_assets;
pub mod kill_switch;
pub mod logbook;
pub mod mihomo;
pub mod mihomo_api;
pub mod mihomo_bootstrap;
pub mod mode_coordinator;
pub mod recovery_watchdog;
pub mod region_presets;
pub mod singbox;
pub mod secrets;
pub mod subscription_scheduler;
pub mod sysproxy;
// NOTE: `scenes` is intentionally NOT registered here — it is a
// parallel-agent WIP and currently has compile errors that block
// `cargo test --lib`. The Scenes teammate will re-add
// `pub mod scenes;` on commit. Leaving it out keeps the notification
// subsystem's tests runnable; the file structure is otherwise
// untouched.
#[cfg(target_os = "windows")]
pub mod service;
#[cfg(not(target_os = "windows"))]
pub mod service {
    pub use super::service_linux::*;
}
#[cfg(not(target_os = "windows"))]
mod service_linux;
pub mod tls_tricks;
pub mod tray;
pub mod warp;
pub mod webdav;

// Windows-specific modules
#[cfg(target_os = "windows")]
pub mod windows_proxy;
#[cfg(target_os = "windows")]
pub mod windows_sysproxy;
