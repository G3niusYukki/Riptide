//! System proxy control commands

use crate::core::sysproxy::SystemProxyController;
use tauri::State;

/// Enable system proxy
#[tauri::command]
pub async fn enable_system_proxy(
    state: State<'_, SystemProxyController>,
    http_port: u16,
    socks_port: Option<u16>,
) -> Result<(), String> {
    state.enable(http_port, socks_port).await.map_err(|e| e.to_string())
}

/// Disable system proxy
#[tauri::command]
pub async fn disable_system_proxy(
    state: State<'_, SystemProxyController>,
) -> Result<(), String> {
    state.disable().await.map_err(|e| e.to_string())
}

/// Get system proxy status
#[tauri::command]
pub async fn get_system_proxy_status(
    state: State<'_, SystemProxyController>,
) -> Result<bool, String> {
    Ok(state.is_enabled().await)
}

/// Install Windows Service for TUN mode
#[tauri::command]
pub async fn install_tun_service() -> Result<(), String> {
    crate::core::service::install_service()
        .map_err(|e| format!("Failed to install service: {}", e))
}

/// Uninstall Windows Service for TUN mode
#[tauri::command]
pub async fn uninstall_tun_service() -> Result<(), String> {
    crate::core::service::uninstall_service()
        .map_err(|e| format!("Failed to uninstall service: {}", e))
}

/// Start TUN mode service
#[tauri::command]
pub async fn start_tun_service() -> Result<(), String> {
    crate::core::service::start_service()
        .map_err(|e| format!("Failed to start service: {}", e))
}

/// Stop TUN mode service
#[tauri::command]
pub async fn stop_tun_service() -> Result<(), String> {
    crate::core::service::stop_service()
        .map_err(|e| format!("Failed to stop service: {}", e))
}
