//! Tauri command handlers for Riptide Windows

pub mod bench;
pub mod config;
pub mod dns;
pub mod engines;
#[cfg(target_os = "windows")]
pub mod gateway;
pub mod logbook;
pub mod mode;
pub mod proxy;
pub mod proxy_editor;
pub mod scripting;
pub mod scenes;
pub mod system;
pub mod uri_serializer;
pub mod webdav;

// Windows-specific commands
#[cfg(target_os = "windows")]
pub mod windows;
