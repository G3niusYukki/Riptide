//! System proxy control commands

#[cfg(target_os = "windows")]
use crate::core::service::{self, ServiceStatusKind};
use crate::core::sysproxy::SystemProxyController;
use tauri::{AppHandle, State};

/// Enable system proxy
#[tauri::command]
pub async fn enable_system_proxy(
    state: State<'_, SystemProxyController>,
    http_port: u16,
    socks_port: Option<u16>,
) -> Result<(), String> {
    state
        .enable(http_port, socks_port)
        .await
        .map_err(|e| e.to_string())
}

/// Disable system proxy
#[tauri::command]
pub async fn disable_system_proxy(state: State<'_, SystemProxyController>) -> Result<(), String> {
    state.disable().await.map_err(|e| e.to_string())
}

/// Get system proxy status
#[tauri::command]
pub async fn get_system_proxy_status(
    state: State<'_, SystemProxyController>,
) -> Result<bool, String> {
    Ok(state.is_enabled().await)
}

// ── Windows-only system commands ────────────────────────────────

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn install_tun_service() -> Result<(), String> {
    use crate::utils::elevation;
    if elevation::is_elevated() {
        return service::install_service().map_err(|e| e.to_string());
    }
    let code = tokio::task::spawn_blocking(|| elevation::relaunch_elevated(&["--install-service"]))
        .await
        .map_err(|e| format!("Task join failed: {}", e))?
        .map_err(|e| e.to_string())?;
    if code == 0 {
        Ok(())
    } else if code == 1223 {
        Err("Installation cancelled (UAC prompt was declined)".into())
    } else {
        Err(format!("Elevated installer exited with code {}", code))
    }
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn uninstall_tun_service() -> Result<(), String> {
    use crate::utils::elevation;
    if elevation::is_elevated() {
        return service::uninstall_service().map_err(|e| e.to_string());
    }
    let code =
        tokio::task::spawn_blocking(|| elevation::relaunch_elevated(&["--uninstall-service"]))
            .await
            .map_err(|e| format!("Task join failed: {}", e))?
            .map_err(|e| e.to_string())?;
    if code == 0 {
        Ok(())
    } else if code == 1223 {
        Err("Uninstall cancelled (UAC prompt was declined)".into())
    } else {
        Err(format!("Elevated uninstaller exited with code {}", code))
    }
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub fn is_elevated() -> bool {
    crate::utils::elevation::is_elevated()
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn start_tun_service(app_handle: AppHandle) -> Result<(), String> {
    let cfg = service::service_launch_config_from_app(&app_handle).map_err(|e| e.to_string())?;
    service::write_service_config(&cfg).map_err(|e| e.to_string())?;
    service::start_service().map_err(|e| e.to_string())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn stop_tun_service() -> Result<(), String> {
    service::stop_service().map_err(|e| e.to_string())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub fn get_tun_service_status() -> ServiceStatusKind {
    service::query_status()
}

// ── Update check (cross-platform) ───────────────────────────────

#[derive(serde::Serialize)]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub update_available: bool,
    pub release_url: String,
}

#[tauri::command]
pub async fn check_update(app_handle: tauri::AppHandle) -> Result<UpdateInfo, String> {
    let current_version = app_handle
        .config()
        .version
        .clone()
        .unwrap_or_else(|| "0.0.0".to_string());
    let client = reqwest::Client::builder()
        .user_agent("Riptide-Update-Checker")
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))?;
    let url = "https://api.github.com/repos/RiptideTeam/Riptide/releases/latest";
    let response = client
        .get(url)
        .header("Accept", "application/vnd.github.v3+json")
        .send()
        .await
        .map_err(|e| format!("Failed to check for updates: {}", e))?;
    if !response.status().is_success() {
        return Err(format!("GitHub API returned {}", response.status()));
    }
    #[derive(serde::Deserialize)]
    struct ReleaseResponse {
        tag_name: String,
        html_url: String,
    }
    let release: ReleaseResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse release info: {}", e))?;
    let latest = release.tag_name.trim_start_matches('v');
    Ok(UpdateInfo {
        current_version: current_version.clone(),
        latest_version: latest.to_string(),
        update_available: latest != current_version,
        release_url: release.html_url,
    })
}
