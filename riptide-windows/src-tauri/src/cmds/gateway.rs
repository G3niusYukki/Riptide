//! Tauri commands for gateway / ICS mode management.

use crate::core::gateway;
use tauri::command;

/// Enable ICS / gateway mode.
#[command]
pub fn enable_gateway(outbound_interface: String, subnet: String) -> Result<(), String> {
    gateway::enable_ics(&outbound_interface, &subnet)
}

/// Disable ICS / gateway mode.
#[command]
pub fn disable_gateway() -> Result<(), String> {
    gateway::disable_ics()
}

/// Check if gateway mode is active.
#[command]
pub fn is_gateway_enabled() -> bool {
    gateway::is_ics_enabled()
}

/// Get connected LAN devices.
#[command]
pub fn get_gateway_devices() -> Vec<gateway::ConnectedDevice> {
    gateway::connected_devices()
}
