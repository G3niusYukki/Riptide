//! Tauri command handlers for Riptide Windows

pub mod proxy;
pub mod proxy_editor;
pub mod config;
pub mod dns;
pub mod mode;
pub mod rewrite;
pub mod system;
pub mod webdav;

// Windows-specific commands
#[cfg(target_os = "windows")]
pub mod windows;
