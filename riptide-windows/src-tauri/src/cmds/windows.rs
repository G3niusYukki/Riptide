//! Windows-specific Tauri command handlers
//!
//! These commands provide access to Windows-optimized proxy and system proxy
//! management features.

use crate::core::windows_proxy::{WindowsProxyManager, ProxyError};
use crate::core::windows_sysproxy::{WindowsSysProxyController, WindowsProxyConfig};
use crate::core::windows_tun::{WindowsTUNManager, TUNError, TUNStatusDto};
use tauri::{AppHandle, State};
use std::sync::Mutex;

/// State wrapper for WindowsProxyManager
pub struct WindowsProxyState(pub Mutex<WindowsProxyManager>);

/// State wrapper for WindowsTUNManager
pub struct WindowsTUNState(pub Mutex<WindowsTUNManager>);

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

/// Initialize Windows TUN state for the application
pub fn init_windows_tun_state(app_handle: &AppHandle) -> anyhow::Result<WindowsTUNState> {
    // Get the app data directory where wintun.dll should be bundled
    let app_dir = crate::utils::dirs::get_app_data_dir(app_handle)?;
    let wintun_path = app_dir.join("wintun.dll");
    
    // Check if wintun.dll exists in the app directory
    // In production, wintun.dll should be bundled via tauri.conf.json resources
    let wintun_dll_path = if wintun_path.exists() {
        wintun_path
    } else {
        // Fallback to current directory (for development)
        std::env::current_dir()?.join("wintun.dll")
    };
    
    log::info!("Wintun DLL path: {:?}", wintun_dll_path);
    
    let manager = WindowsTUNManager::new(wintun_dll_path);
    Ok(WindowsTUNState(Mutex::new(manager)))
}

// ==================== TUN Mode Commands ====================

/// Start TUN mode
#[tauri::command]
pub async fn start_tun_mode(state: State<'_, WindowsTUNState>) -> Result<(), String> {
    let mut manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    if manager.get_status() == crate::core::windows_tun::TUNStatus::Stopped {
        manager.create_adapter().map_err(|e| e.to_string())?;
    }
    manager.start().await.map_err(|e| e.to_string())
}

/// Stop TUN mode
#[tauri::command]
pub async fn stop_tun_mode(state: State<'_, WindowsTUNState>) -> Result<(), String> {
    let mut manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    manager.stop().await.map_err(|e| e.to_string())
}

/// Get TUN mode status
#[tauri::command]
pub fn get_tun_status(state: State<'_, WindowsTUNState>) -> Result<TUNStatusDto, String> {
    let manager = state.0.lock().map_err(|e| format!("Lock error: {}", e))?;
    let config = manager.get_config();
    Ok(TUNStatusDto {
        status: format!("{}", manager.get_status()),
        running: false,
        adapter_name: Some(config.adapter_name.clone()),
        interface_ip: Some(config.interface_ip.clone()),
        gateway: Some(config.gateway.clone()),
    })
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
