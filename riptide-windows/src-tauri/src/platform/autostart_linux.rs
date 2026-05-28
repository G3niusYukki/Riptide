//! Linux auto-start via systemd user unit.
//!
//! Riptide can register a systemd user service to start on login.
//! The service file is written to `~/.config/systemd/user/riptide.service`.

use anyhow::{Context, Result};
use std::path::PathBuf;

const SERVICE_NAME: &str = "riptide.service";
const SERVICE_CONTENT: &str = r#"[Unit]
Description=Riptide Proxy Client
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=riptide-desktop --minimized
Restart=on-failure
RestartSec=5
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
"#;

/// Enable auto-start (install systemd user unit).
pub fn enable_autostart() -> Result<()> {
    let unit_dir = systemd_user_dir()?;
    std::fs::create_dir_all(&unit_dir).context("failed to create systemd user dir")?;

    let unit_path = unit_dir.join(SERVICE_NAME);
    std::fs::write(&unit_path, SERVICE_CONTENT).context("failed to write service file")?;

    // Enable the service
    let status = std::process::Command::new("systemctl")
        .args(["--user", "enable", "--now", SERVICE_NAME])
        .status()
        .context("failed to enable systemd service")?;

    if status.success() {
        log::info!("systemd user service enabled: {SERVICE_NAME}");
    }

    Ok(())
}

/// Disable auto-start (remove systemd user unit).
pub fn disable_autostart() -> Result<()> {
    // Stop and disable
    let _ = std::process::Command::new("systemctl")
        .args(["--user", "stop", SERVICE_NAME])
        .status();

    let _ = std::process::Command::new("systemctl")
        .args(["--user", "disable", SERVICE_NAME])
        .status();

    // Remove unit file
    let unit_path = systemd_user_dir()?.join(SERVICE_NAME);
    if unit_path.exists() {
        std::fs::remove_file(&unit_path).ok();
    }

    log::info!("systemd user service disabled: {SERVICE_NAME}");
    Ok(())
}

/// Check if auto-start is enabled.
pub fn is_autostart_enabled() -> bool {
    let unit_path = systemd_user_dir()
        .map(|d| d.join(SERVICE_NAME))
        .unwrap_or_default();
    unit_path.exists()
}

/// Returns the systemd user unit directory.
fn systemd_user_dir() -> Result<PathBuf> {
    let home = dirs_next().ok_or_else(|| anyhow::anyhow!("no home dir"))?;
    Ok(home.join(".config/systemd/user"))
}

fn dirs_next() -> Option<PathBuf> {
    std::env::var("HOME").ok().map(PathBuf::from)
}
