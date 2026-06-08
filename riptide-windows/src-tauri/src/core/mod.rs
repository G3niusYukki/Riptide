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
pub mod scenes;
pub mod secrets;
#[cfg(target_os = "windows")]
pub mod service;
pub mod singbox;
pub mod subscription_scheduler;
pub mod sysproxy;
#[cfg(not(target_os = "windows"))]
pub mod service {
    pub use super::service_linux::*;
}
#[cfg(not(target_os = "windows"))]
mod service_linux;
pub mod scripting;
pub mod tls_tricks;
pub mod tray;
pub mod warp;
pub mod webdav;

// Windows-specific modules
#[cfg(target_os = "windows")]
pub mod windows_proxy;
#[cfg(target_os = "windows")]
pub mod windows_sysproxy;
