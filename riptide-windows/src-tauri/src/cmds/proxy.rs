//! Proxy control commands

use crate::core::mihomo::MihomoManager;
use tauri::State;

/// Start the proxy service
#[tauri::command]
pub async fn start_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.start().await.map_err(|e| e.to_string())
}

/// Stop the proxy service
#[tauri::command]
pub async fn stop_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.stop().await.map_err(|e| e.to_string())
}

/// Restart the proxy service
#[tauri::command]
pub async fn restart_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.restart().await.map_err(|e| e.to_string())
}

/// Get proxy status
#[tauri::command]
pub async fn get_proxy_status(state: State<'_, MihomoManager>) -> Result<bool, String> {
    Ok(state.is_running().await)
}

/// Test proxy delay for a specific node
#[tauri::command]
pub async fn test_proxy_delay(name: String, url: Option<String>) -> Result<i32, String> {
    // TODO: Implement delay test via mihomo API
    Ok(0)
}
