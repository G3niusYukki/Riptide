//! Core business logic modules

pub mod diagnostics;
pub mod gateway;
pub mod geo_assets;
pub mod kill_switch;
pub mod mihomo;
pub mod mihomo_api;
pub mod mihomo_bootstrap;
pub mod mode_coordinator;
pub mod recovery_watchdog;
pub mod region_presets;
pub mod secrets;
pub mod subscription_scheduler;
pub mod sysproxy;
pub mod service;
pub mod tls_tricks;
pub mod tray;
pub mod warp;
pub mod webdav;

// Windows-specific modules
#[cfg(target_os = "windows")]
pub mod windows_proxy;
#[cfg(target_os = "windows")]
pub mod windows_sysproxy;
