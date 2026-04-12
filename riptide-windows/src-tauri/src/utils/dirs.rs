//! Directory and path utilities

use std::path::PathBuf;
use tauri::AppHandle;
use tauri::Manager;

/// Get the application data directory
pub fn get_app_data_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let path = app_handle.path().app_data_dir()?;
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

/// Get the mihomo binary path
pub fn get_mihomo_binary_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let app_dir = get_app_data_dir(app_handle)?;
    Ok(app_dir.join("mihomo.exe"))
}

/// Get the wintun.dll path
pub fn get_wintun_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let app_dir = get_app_data_dir(app_handle)?;
    Ok(app_dir.join("wintun.dll"))
}

/// Get the config directory
pub fn get_config_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let path = get_app_data_dir(app_handle)?.join("config");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

/// Get the main config file path
pub fn get_config_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    Ok(get_config_dir(app_handle)?.join("config.yaml"))
}

/// Get the profiles directory
pub fn get_profiles_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let path = get_app_data_dir(app_handle)?.join("profiles");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}

/// Get the logs directory
pub fn get_logs_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let path = get_app_data_dir(app_handle)?.join("logs");
    std::fs::create_dir_all(&path)?;
    Ok(path)
}
