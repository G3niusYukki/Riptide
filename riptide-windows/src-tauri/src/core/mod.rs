//! Core business logic modules

pub mod mihomo;
pub mod mihomo_api;
pub mod sysproxy;
pub mod service;

// Windows-specific modules
#[cfg(target_os = "windows")]
pub mod windows_proxy;
#[cfg(target_os = "windows")]
pub mod windows_sysproxy;
