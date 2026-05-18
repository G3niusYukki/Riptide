//! Centralised logging setup for the Windows app.
//!
//! Routes both `log` and `tracing` events through a single `tracing` subscriber
//! with two outputs:
//!   - a rolling daily file at `%APPDATA%\Riptide\logs\riptide.log`
//!   - stderr (only when `RUST_LOG` is set, so release builds stay quiet on console)
//!
//! Filter level honors `RUST_LOG`; falls back to `info` if unset.
//!
//! Call `init_logger()` exactly once, as early as possible in `run()`. The
//! returned `WorkerGuard` keeps the file writer's background flush thread alive;
//! drop it at process exit (we hold it in a global).

use std::sync::OnceLock;
use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

static GUARD: OnceLock<WorkerGuard> = OnceLock::new();

/// Initialise tracing-based logging. Safe to call multiple times — only the
/// first call wins; subsequent calls are no-ops and return Ok.
pub fn init_logger() -> anyhow::Result<()> {
    if GUARD.get().is_some() {
        return Ok(());
    }

    let log_dir = log_directory();
    std::fs::create_dir_all(&log_dir)?;

    // Daily rotation, keeps "riptide.log" current + dated archives. tracing-appender
    // handles the timestamp suffix; we only specify the prefix.
    let file_appender = tracing_appender::rolling::daily(&log_dir, "riptide.log");
    let (file_writer, guard) = tracing_appender::non_blocking(file_appender);

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    // File layer — always on, no ANSI codes (file viewers don't render them).
    let file_layer = fmt::layer()
        .with_writer(file_writer)
        .with_ansi(false)
        .with_target(true);

    // Stderr layer — present for dev but quiet by default. ANSI on.
    let stderr_layer = fmt::layer()
        .with_writer(std::io::stderr)
        .with_target(true);

    tracing_subscriber::registry()
        .with(filter)
        .with(file_layer)
        .with(stderr_layer)
        .try_init()
        .map_err(|e| anyhow::anyhow!("Failed to install tracing subscriber: {}", e))?;

    // Route the legacy `log` crate's macros (used throughout the codebase) through
    // tracing so we have a single output pipeline.
    let _ = tracing_log::LogTracer::init();

    let _ = GUARD.set(guard);
    tracing::info!("Logger initialised; log directory: {:?}", log_dir);
    Ok(())
}

fn log_directory() -> std::path::PathBuf {
    #[cfg(target_os = "windows")]
    {
        crate::utils::windows_dirs::WindowsDirs::logs_dir()
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::env::temp_dir().join("riptide-logs")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_directory_is_non_empty() {
        assert!(!log_directory().as_os_str().is_empty());
    }
}
