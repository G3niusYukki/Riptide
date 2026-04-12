//! Windows-specific Tauri command handlers
//!
//! These commands provide access to Windows-optimized proxy and system proxy
//! management features.

use crate::core::windows_proxy::{WindowsProxyManager, ProxyError};
use crate::core::windows_sysproxy::{WindowsSysProxyController, WindowsProxyConfig};
use tauri::{AppHandle, State};
use std::sync::Mutex;

/// State wrapper for WindowsProxyManager
pub struct WindowsProxyState(pub Mutex<WindowsProxyManager>);

/// Start the mihomo proxy using Windows-optimized process management
#[tauri::command]
pub fn start_windows_proxy(state: State<'_, WindowsProxyState>) -> Result<(), String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    manager.start().map_err(|e| e.to_string())
}

/// Stop the mihomo proxy process
#[tauri::command]
pub fn stop_windows_proxy(state: State<'_, WindowsProxyState>) -> Result<(), String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    manager.stop().map_err(|e| e.to_string())
}

/// Restart the mihomo proxy process
#[tauri::command]
pub fn restart_windows_proxy(state: State<'_, WindowsProxyState>) -> Result<(), String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    manager.restart().map_err(|e| e.to_string())
}

/// Get the current proxy process status
#[tauri::command]
pub fn get_windows_proxy_status(state: State<'_, WindowsProxyState>) -> Result<bool, String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    Ok(manager.is_running())
}

/// Get the proxy process ID if running
#[tauri::command]
pub fn get_windows_proxy_pid(state: State<'_, WindowsProxyState>) -> Result<Option<u32>, String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    Ok(manager.get_pid())
}

/// Enable system proxy with HTTP configuration
#[tauri::command]
pub fn enable_windows_system_proxy(
    host: String,
    port: u16,
) -> Result<(), String> {
    let controller = WindowsSysProxyController::new();
    controller
        .enable_http_proxy(&host, port)
        .map_err(|e| e.to_string())
}

/// Enable system proxy with SOCKS configuration
#[tauri::command]
pub fn enable_windows_socks_proxy(
    host: String,
    port: u16,
) -> Result<(), String> {
    let controller = WindowsSysProxyController::new();
    controller
        .enable_socks_proxy(&host, port)
        .map_err(|e| e.to_string())
}

/// Enable both HTTP and SOCKS proxies
#[tauri::command]
pub fn enable_windows_both_proxies(
    host: String,
    http_port: u16,
    socks_port: u16,
) -> Result<(), String> {
    let controller = WindowsSysProxyController::new();
    controller
        .enable_both_proxies(&host, http_port, socks_port)
        .map_err(|e| e.to_string())
}

/// Disable Windows system proxy
#[tauri::command]
pub fn disable_windows_system_proxy() -> Result<(), String> {
    let controller = WindowsSysProxyController::new();
    controller.disable().map_err(|e| e.to_string())
}

/// Get current Windows system proxy configuration
#[tauri::command]
pub fn get_windows_system_proxy_config() -> Result<WindowsProxyConfigDto, String> {
    let controller = WindowsSysProxyController::new();
    let config = controller.get_current().map_err(|e| e.to_string())?;
    Ok(WindowsProxyConfigDto::from(config))
}

/// DTO for WindowsProxyConfig serialization
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct WindowsProxyConfigDto {
    pub enable: bool,
    pub proxy_server: String,
    pub bypass_list: String,
    pub auto_config_url: Option<String>,
}

impl From<WindowsProxyConfig> for WindowsProxyConfigDto {
    fn from(config: WindowsProxyConfig) -> Self {
        Self {
            enable: config.enable,
            proxy_server: config.proxy_server,
            bypass_list: config.bypass_list,
            auto_config_url: config.auto_config_url,
        }
    }
}

/// Initialize Windows proxy state for the application
pub fn init_windows_proxy_state(app_handle: &AppHandle) -> anyhow::Result<WindowsProxyState> {
    let manager = WindowsProxyManager::from_app_handle(app_handle)?;
    Ok(WindowsProxyState(Mutex::new(manager)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_config_dto_conversion() {
        let config = WindowsProxyConfig::http_proxy("127.0.0.1", 7890);
        let dto = WindowsProxyConfigDto::from(config);
        
        assert!(dto.enable);
        assert!(dto.proxy_server.contains("7890"));
        assert!(!dto.bypass_list.is_empty());
    }

    #[test]
    fn test_disabled_config_dto() {
        let config = WindowsProxyConfig::disabled();
        let dto = WindowsProxyConfigDto::from(config);
        
        assert!(!dto.enable);
        assert!(dto.proxy_server.is_empty());
    }
}
