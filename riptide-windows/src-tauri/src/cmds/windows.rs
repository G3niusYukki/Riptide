//! Windows-specific Tauri command handlers
//!
//! These commands provide access to Windows-optimized proxy and system proxy
//! management features.

use crate::cmds::config::{resolve_active_profile_content, AppState};
use crate::core::mihomo::{MihomoManager, TunOptions, TunnelMode};
use crate::core::windows_proxy::WindowsProxyManager;
use crate::core::windows_sysproxy::{WindowsSysProxyController, WindowsProxyConfig};
use tauri::{AppHandle, State};
use std::sync::Mutex;

/// State wrapper for WindowsProxyManager
pub struct WindowsProxyState(pub Mutex<WindowsProxyManager>);

/// DTO returned by `get_tun_status`. The legacy wintun-based manager that
/// used to live in `core/windows_tun.rs` is gone — TUN is now driven by
/// mihomo's own TUN stack via the active profile's config. This struct stays
/// here because the UI still expects this shape.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct TUNStatusDto {
    pub status: String,
    pub running: bool,
    pub adapter_name: Option<String>,
    pub interface_ip: Option<String>,
    pub gateway: Option<String>,
}

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

// ==================== TUN Mode Commands ====================

/// Start TUN mode. Switches `MihomoManager` to TUN, rewrites config with a
/// `tun:` block injected, then starts (or restarts) mihomo. Requires that
/// the app is running with administrator privileges *or* the RiptideTUN
/// Windows service is installed (Task 1.2 / 1.3) — without either, mihomo
/// will refuse to create the TUN device.
#[tauri::command]
pub async fn start_tun_mode(
    mihomo: State<'_, MihomoManager>,
    app_state: State<'_, AppState>,
) -> Result<(), String> {
    let content = resolve_active_profile_content(&app_state)?;
    mihomo.set_mode(TunnelMode::Tun);
    mihomo.write_config(&content).map_err(|e| e.to_string())?;

    // If mihomo is already running (e.g., in System Proxy mode), a restart
    // is required to pick up the new config. Otherwise just start fresh.
    if mihomo.is_running().await {
        mihomo.restart().await.map_err(|e| e.to_string())
    } else {
        mihomo.start().await.map_err(|e| e.to_string())
    }
}

/// Stop TUN mode. Reverts the mode pointer to System Proxy so a subsequent
/// `start_proxy` doesn't unexpectedly come up in TUN.
#[tauri::command]
pub async fn stop_tun_mode(mihomo: State<'_, MihomoManager>) -> Result<(), String> {
    mihomo.stop().await.map_err(|e| e.to_string())?;
    mihomo.set_mode(TunnelMode::SystemProxy);
    Ok(())
}

/// Get TUN mode status.
#[tauri::command]
pub async fn get_tun_status(mihomo: State<'_, MihomoManager>) -> Result<TUNStatusDto, String> {
    let mode = mihomo.current_mode();
    let opts = mihomo.current_tun_options();
    let running = mode == TunnelMode::Tun && mihomo.is_running().await;
    let status_str = if running { "running" } else { "stopped" };
    Ok(TUNStatusDto {
        status: status_str.to_string(),
        running,
        adapter_name: Some(opts.device.clone()),
        interface_ip: None,
        gateway: None,
    })
}

/// Update the runtime TUN options (device name, stack, MTU, …). Takes effect
/// next time TUN mode is started or the proxy is restarted.
#[tauri::command]
pub fn set_tun_options(mihomo: State<'_, MihomoManager>, options: TunOptions) -> Result<(), String> {
    mihomo.set_tun_options(options);
    Ok(())
}

#[tauri::command]
pub fn get_tun_options(mihomo: State<'_, MihomoManager>) -> TunOptions {
    mihomo.current_tun_options()
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
