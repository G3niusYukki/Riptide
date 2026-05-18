//! System proxy control commands

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

/// Install the RiptideTUN Windows service. If the current process is not
/// elevated, transparently re-launches the UI binary with `--install-service`
/// under UAC, waits for it to complete, and reports back. Single UAC prompt.
#[tauri::command]
pub async fn install_tun_service() -> Result<(), String> {
    use crate::utils::elevation;

    if elevation::is_elevated() {
        return service::install_service().map_err(|e| e.to_string());
    }

    // Off the main async runtime — ShellExecuteExW + WaitForSingleObject are blocking.
    let code = tokio::task::spawn_blocking(|| elevation::relaunch_elevated(&["--install-service"]))
        .await
        .map_err(|e| format!("Task join failed: {}", e))?
        .map_err(|e| e.to_string())?;

    if code == 0 {
        Ok(())
    } else if code == 1223 {
        // ERROR_CANCELLED — user dismissed UAC.
        Err("Installation cancelled (UAC prompt was declined)".into())
    } else {
        Err(format!("Elevated installer exited with code {}", code))
    }
}

#[tauri::command]
pub async fn uninstall_tun_service() -> Result<(), String> {
    use crate::utils::elevation;

    if elevation::is_elevated() {
        return service::uninstall_service().map_err(|e| e.to_string());
    }

    let code = tokio::task::spawn_blocking(|| elevation::relaunch_elevated(&["--uninstall-service"]))
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

#[tauri::command]
pub fn is_elevated() -> bool {
    crate::utils::elevation::is_elevated()
}

/// Start the RiptideTUN service. Writes the service launch config first so
/// the service knows where to find mihomo and the merged config.
#[tauri::command]
pub async fn start_tun_service(app_handle: AppHandle) -> Result<(), String> {
    let cfg = service::service_launch_config_from_app(&app_handle).map_err(|e| e.to_string())?;
    service::write_service_config(&cfg).map_err(|e| e.to_string())?;
    service::start_service().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn stop_tun_service() -> Result<(), String> {
    service::stop_service().map_err(|e| e.to_string())
}

/// Query the SCM status of the RiptideTUN service.
#[tauri::command]
pub fn get_tun_service_status() -> ServiceStatusKind {
    service::query_status()
}

/// Update check result
#[derive(serde::Serialize)]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub update_available: bool,
    pub release_url: String,
}

/// Check for updates via GitHub Releases API
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
    let update_available = latest != current_version;

    Ok(UpdateInfo {
        current_version,
        latest_version: latest.to_string(),
        update_available,
        release_url: release.html_url,
    })
}
