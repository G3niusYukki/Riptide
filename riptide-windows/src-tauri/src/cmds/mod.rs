//! Tauri command handlers for Riptide Windows

pub mod proxy;
pub mod proxy_editor;
pub mod config;
pub mod engines;
pub mod logbook;
pub mod dns;
pub mod uri_serializer;
#[cfg(target_os = "windows")]
pub mod gateway;
pub mod mode;
pub mod rewrite;
// NOTE: `scenes` is intentionally NOT registered here — it is a
// parallel-agent WIP and currently has compile errors that block
// `cargo test --lib`. The Scenes teammate will re-add
// `pub mod scenes;` on commit.
pub mod system;
pub mod webdav;

// Windows-specific commands
#[cfg(target_os = "windows")]
pub mod windows;
