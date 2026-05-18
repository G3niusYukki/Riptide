//! Directory and path utilities
//!
//! On Windows we keep everything under `%APPDATA%\Riptide\` so logs / profiles
//! / mihomo binary / generated config all live in one place. On other targets
//! we fall back to Tauri's bundle-identifier-based path (`com.riptide.app`).

use std::path::PathBuf;
use tauri::AppHandle;
#[cfg(not(target_os = "windows"))]
use tauri::Manager;

/// Root data directory for Riptide. On Windows this is `%APPDATA%\Riptide\`
/// regardless of bundle identifier so the user's data location stays stable
/// across renames or rebrands.
pub fn get_app_data_dir(_app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let path = crate::utils::windows_dirs::WindowsDirs::config_dir();
        std::fs::create_dir_all(&path)?;
        Ok(path)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let path = _app_handle.path().app_data_dir()?;
        std::fs::create_dir_all(&path)?;
        Ok(path)
    }
}

/// Path to the mihomo binary. Lives under the `mihomo/` subdir so the parent
/// data dir doesn't get cluttered with executables alongside config + profiles.
pub fn get_mihomo_binary_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let _ = app_handle;
        let dir = crate::utils::windows_dirs::WindowsDirs::mihomo_dir();
        std::fs::create_dir_all(&dir)?;
        Ok(dir.join("mihomo.exe"))
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(get_app_data_dir(app_handle)?.join("mihomo.exe"))
    }
}

/// Path to wintun.dll (legacy; the current TUN path goes through mihomo's
/// gVisor stack and no longer needs wintun. Kept for backward compatibility.)
pub fn get_wintun_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    Ok(get_app_data_dir(app_handle)?.join("wintun.dll"))
}

/// Directory holding the generated mihomo config (alongside the binary).
pub fn get_config_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let _ = app_handle;
        let dir = crate::utils::windows_dirs::WindowsDirs::mihomo_dir();
        std::fs::create_dir_all(&dir)?;
        Ok(dir)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let path = get_app_data_dir(app_handle)?.join("config");
        std::fs::create_dir_all(&path)?;
        Ok(path)
    }
}

/// Path of the generated mihomo config.yaml.
pub fn get_config_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    Ok(get_config_dir(app_handle)?.join("config.yaml"))
}

/// Directory holding user profile YAMLs.
pub fn get_profiles_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let _ = app_handle;
        let dir = crate::utils::windows_dirs::WindowsDirs::profiles_dir();
        std::fs::create_dir_all(&dir)?;
        Ok(dir)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let path = get_app_data_dir(app_handle)?.join("profiles");
        std::fs::create_dir_all(&path)?;
        Ok(path)
    }
}

/// Directory holding rolling log files.
pub fn get_logs_dir(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        let _ = app_handle;
        let dir = crate::utils::windows_dirs::WindowsDirs::logs_dir();
        std::fs::create_dir_all(&dir)?;
        Ok(dir)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let path = get_app_data_dir(app_handle)?.join("logs");
        std::fs::create_dir_all(&path)?;
        Ok(path)
    }
}
