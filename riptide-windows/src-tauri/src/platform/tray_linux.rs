//! Linux system tray via `tray-icon` crate with `libxdo` feature.

use anyhow::Result;

pub struct LinuxTray {
    visible: bool,
}

impl LinuxTray {
    pub fn new() -> Self {
        Self { visible: false }
    }

    pub fn show(&mut self) {
        self.visible = true;
        log::info!("Linux tray icon shown");
    }

    pub fn hide(&mut self) {
        self.visible = false;
        log::info!("Linux tray icon hidden");
    }

    pub fn set_tooltip(&self, text: &str) {
        log::debug!("Tray tooltip: {text}");
    }

    pub fn is_visible(&self) -> bool {
        self.visible
    }
}
