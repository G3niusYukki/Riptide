//! Linux system tray icon (stub — WIP).
//! Real implementation will use `tray-icon` crate with `libxdo` feature.

use anyhow::Result;

pub struct LinuxTray { visible: bool }

impl LinuxTray {
    pub fn new() -> Result<Self> { Ok(Self { visible: false }) }
    pub fn show(&mut self) { self.visible = true; }
    pub fn hide(&mut self) { self.visible = false; }
    pub fn set_tooltip(&self, _text: &str) {}
    pub fn is_visible(&self) -> bool { self.visible }
}
