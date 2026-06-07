//! Mode switching commands — the only sanctioned way for the UI to start or
//! stop a tunnel. These commands delegate to `ModeCoordinator`, which holds
//! the cross-component lock that prevents overlapping starts.

use crate::cmds::config::AppState;
use crate::core::mihomo::MihomoManager;
use crate::core::mode_coordinator::{AppMode, ModeCoordinator};
use crate::core::sysproxy::SystemProxyController;
use tauri::State;

#[tauri::command]
pub async fn mode_current(coordinator: State<'_, ModeCoordinator>) -> Result<AppMode, String> {
    Ok(coordinator.current().await)
}

#[tauri::command]
pub async fn mode_switch_to_system_proxy(
    coordinator: State<'_, ModeCoordinator>,
    mihomo: State<'_, MihomoManager>,
    sysproxy: State<'_, SystemProxyController>,
    app_state: State<'_, AppState>,
    http_port: u16,
    socks_port: Option<u16>,
) -> Result<(), String> {
    coordinator
        .switch_to_system_proxy(&mihomo, &sysproxy, &app_state, http_port, socks_port)
        .await
}

#[tauri::command]
pub async fn mode_switch_to_tun(
    coordinator: State<'_, ModeCoordinator>,
    mihomo: State<'_, MihomoManager>,
    sysproxy: State<'_, SystemProxyController>,
    app_state: State<'_, AppState>,
) -> Result<(), String> {
    coordinator
        .switch_to_tun(&mihomo, &sysproxy, &app_state)
        .await
}

#[tauri::command]
pub async fn mode_switch_off(
    coordinator: State<'_, ModeCoordinator>,
    mihomo: State<'_, MihomoManager>,
    sysproxy: State<'_, SystemProxyController>,
) -> Result<(), String> {
    coordinator.switch_off(&mihomo, &sysproxy).await
}
