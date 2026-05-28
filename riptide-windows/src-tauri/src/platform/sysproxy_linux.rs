//! Linux system proxy controller via D-Bus (GNOME / KDE).
//!
//! On Linux there is no single system proxy API. This module:
//! - GNOME: Sets `org.gnome.system.proxy` via D-Bus
//! - KDE:  (future) Sets KDE proxy settings via `kreadconfig5`
//! - Environment: Falls back to `HTTP_PROXY`/`HTTPS_PROXY` env vars
//!
//! The system proxy mode on Linux sets the HTTP/HTTPS proxy to
//! `127.0.0.1:{port}` so that applications respecting the system
//! proxy will route through Riptide.

use anyhow::{Context, Result};

/// Proxy mode for Linux system proxy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinuxProxyMode {
    /// No proxy — remove all proxy settings.
    Off,
    /// Set system proxy to the given port.
    On { http_port: u16 },
}

/// Controller for Linux system proxy settings.
pub struct LinuxSysProxy {
    mode: LinuxProxyMode,
}

impl LinuxSysProxy {
    pub fn new() -> Self {
        Self {
            mode: LinuxProxyMode::Off,
        }
    }

    /// Enable system proxy on the given HTTP port.
    pub async fn enable(&mut self, http_port: u16) -> Result<()> {
        let proxy_uri = format!("http://127.0.0.1:{}", http_port);

        // GNOME: set via gsettings (most common on Ubuntu/Fedora)
        if let Err(e) = set_gnome_proxy(&proxy_uri).await {
            log::warn!("Failed to set GNOME proxy: {e} — falling back to env vars");
            // Fallback: set environment variables (affects current process only)
            std::env::set_var("HTTP_PROXY", &proxy_uri);
            std::env::set_var("HTTPS_PROXY", &proxy_uri);
            std::env::set_var("ALL_PROXY", &proxy_uri);
        }

        self.mode = LinuxProxyMode::On { http_port };
        Ok(())
    }

    /// Disable system proxy (restore direct connection).
    pub async fn disable(&mut self) -> Result<()> {
        // GNOME: set mode to 'none'
        if let Err(e) = set_gnome_proxy_mode("none").await {
            log::warn!("Failed to disable GNOME proxy: {e}");
        }

        // Clear env vars
        std::env::remove_var("HTTP_PROXY");
        std::env::remove_var("HTTPS_PROXY");
        std::env::remove_var("ALL_PROXY");

        self.mode = LinuxProxyMode::Off;
        Ok(())
    }

    /// Returns the current proxy mode.
    pub fn mode(&self) -> LinuxProxyMode {
        self.mode
    }
}

/// Set GNOME system proxy via `gsettings` CLI.
async fn set_gnome_proxy(proxy_uri: &str) -> Result<()> {
    let status = tokio::process::Command::new("gsettings")
        .args([
            "set",
            "org.gnome.system.proxy.http",
            "host",
            "127.0.0.1",
        ])
        .status()
        .await
        .context("gsettings not found — GNOME proxy requires gsettings")?;

    if !status.success() {
        anyhow::bail!("gsettings returned non-zero");
    }

    // Extract port from URI
    let port = proxy_uri
        .split(':')
        .last()
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or(6152);

    tokio::process::Command::new("gsettings")
        .args([
            "set",
            "org.gnome.system.proxy.http",
            "port",
            &port.to_string(),
        ])
        .status()
        .await?;

    // Set mode to 'manual'
    set_gnome_proxy_mode("manual").await?;

    Ok(())
}

/// Set GNOME proxy mode.
async fn set_gnome_proxy_mode(mode: &str) -> Result<()> {
    tokio::process::Command::new("gsettings")
        .args(["set", "org.gnome.system.proxy", "mode", mode])
        .status()
        .await
        .context("failed to set GNOME proxy mode")?;
    Ok(())
}
