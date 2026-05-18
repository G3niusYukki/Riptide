//! Utility functions

pub mod dirs;
pub mod elevation;
pub mod logger;

#[cfg(target_os = "windows")]
pub mod windows_dirs;

#[cfg(target_os = "windows")]
pub mod hotkeys;
