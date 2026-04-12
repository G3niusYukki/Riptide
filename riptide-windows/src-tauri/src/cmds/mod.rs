//! Tauri command handlers for Riptide Windows

pub mod proxy;
pub mod config;
pub mod system;

// Windows-specific commands
#[cfg(target_os = "windows")]
pub mod windows;
