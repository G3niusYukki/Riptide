//! Logging utilities

use log::LevelFilter;
use std::path::Path;

/// Initialize the logger
pub fn init_logger(log_dir: &Path) -> anyhow::Result<()> {
    let log_file = log_dir.join("riptide.log");

    env_logger::Builder::new()
        .filter_level(LevelFilter::Info)
        .parse_default_env()
        .try_init()?;

    log::info!("Logger initialized. Log file: {:?}", log_file);
    Ok(())
}

/// Log a message with context
#[macro_export]
macro_rules! log_info {
    ($ctx:expr, $msg:expr) => {
        log::info!("[{}] {}", $ctx, $msg)
    };
}

#[macro_export]
macro_rules! log_error {
    ($ctx:expr, $msg:expr) => {
        log::error!("[{}] {}", $ctx, $msg)
    };
}

#[macro_export]
macro_rules! log_debug {
    ($ctx:expr, $msg:expr) => {
        log::debug!("[{}] {}", $ctx, $msg)
    };
}
