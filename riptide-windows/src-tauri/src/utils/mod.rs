//! Utility functions

pub mod dirs;
pub mod elevation;
pub mod logger;
pub mod process;

pub mod windows_dirs;

#[cfg(target_os = "windows")]
pub mod hotkeys;
