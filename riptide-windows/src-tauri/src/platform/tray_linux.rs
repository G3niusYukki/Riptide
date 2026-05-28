//! Linux system tray icon via `tray-icon`.
//!
//! On Linux, system trays are provided by the desktop environment
//! (GNOME Shell via AppIndicator extension, KDE Plasma, XFCE, etc.).
//! This module creates a tray icon with a context menu for quick actions.

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Tray icon state.
pub struct LinuxTray {
    visible: bool,
    // In production: holds tray-icon::TrayIcon handle
}

impl LinuxTray {
    pub fn new() -> Result<Self> {
        // TODO: Initialize tray-icon with Riptide icon
        // let icon = tray_icon::TrayIconBuilder::new()
        //     .with_icon(load_icon()?)
        //     .with_tooltip("Riptide")
        //     .with_menu(build_menu())
        //     .build()?;
        Ok(Self { visible: false })
    }

    /// Show the tray icon.
    pub fn show(&mut self) {
        self.visible = true;
        log::info!("Linux tray icon shown");
    }

    /// Hide the tray icon.
    pub fn hide(&mut self) {
        self.visible = false;
        log::info!("Linux tray icon hidden");
    }

    /// Update the tray tooltip (e.g., show current node name).
    pub fn set_tooltip(&self, text: &str) {
        log::debug!("Tray tooltip: {text}");
    }

    pub fn is_visible(&self) -> bool {
        self.visible
    }
}

/// Tray actions (invoked from menu items).
#[derive(Debug, Clone)]
pub enum TrayAction {
    ToggleProxy,
    SwitchMode,
    ShowWindow,
    Quit,
}

/// Shared tray action sender.
pub type TraySender = tokio::sync::mpsc::UnboundedSender<TrayAction>;

/// Build the tray context menu.
// fn build_menu() -> tray_icon::menu::Menu {
//     // Would create: Toggle Proxy | Switch Mode | Show Window | Quit
//     todo!("menu builder")
// }
