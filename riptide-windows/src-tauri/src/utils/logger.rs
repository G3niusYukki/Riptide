//! Logging utilities

use log::LevelFilter;
use std::fs;
use std::path::Path;

/// Initialize the logger, writing output to both stderr and a log file.
pub fn init_logger(log_dir: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(log_dir)?;
    let log_file = log_dir.join("riptide.log");

    let file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)?;

    env_logger::Builder::new()
        .filter_level(LevelFilter::Info)
        .parse_default_env()
        .target(env_logger::Target::Pipe(Box::new(file)))
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
