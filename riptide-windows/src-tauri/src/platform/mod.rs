//! Linux platform adapter — TUN, system proxy, tray, and auto-start.
//!
//! This module provides the Linux equivalents of the Windows platform
//! services in `core/`:
//! - `tun_linux`  → `/dev/net/tun` via `tokio-tun`
//! - `sysproxy_linux` → D-Bus `org.gnome.system.proxy` via `zbus`
//! - `tray_linux` → system tray via `tray-icon`
//!
//! Compiles only on `cfg(target_os = "linux")`.

#[cfg(target_os = "linux")]
pub mod tun_linux;

#[cfg(target_os = "linux")]
pub mod sysproxy_linux;

#[cfg(target_os = "linux")]
pub mod tray_linux;

#[cfg(target_os = "linux")]
pub mod autostart_linux;
