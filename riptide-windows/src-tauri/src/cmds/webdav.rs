//! WebDAV sync commands.

use serde::{Deserialize, Serialize};

use crate::core::webdav::{self, WebDAVConfig};

/// DTO returned to the UI: same as `WebDAVConfig` but redacts the password
/// ciphertext (UI never needs the bytes, only "is a password set?").
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebDAVConfigDto {
    pub endpoint: String,
    pub username: String,
    pub has_password: bool,
    pub remote_path: String,
    pub enabled: bool,
}

impl From<&WebDAVConfig> for WebDAVConfigDto {
    fn from(cfg: &WebDAVConfig) -> Self {
        Self {
            endpoint: cfg.endpoint.clone(),
            username: cfg.username.clone(),
            has_password: !cfg.password_cipher_hex.is_empty(),
            remote_path: cfg.remote_path.clone(),
            enabled: cfg.enabled,
        }
    }
}

#[tauri::command]
pub fn webdav_get_config() -> WebDAVConfigDto {
    WebDAVConfigDto::from(&webdav::load_config())
}

/// Save the config. Pass a non-empty `password` to (re)set the credential;
/// empty `password` leaves the stored ciphertext untouched.
#[tauri::command]
pub fn webdav_set_config(
    endpoint: String,
    username: String,
    password: String,
    remote_path: String,
    enabled: bool,
) -> Result<WebDAVConfigDto, String> {
    let mut cfg = webdav::load_config();
    cfg.endpoint = endpoint;
    cfg.username = username;
    cfg.remote_path = if remote_path.is_empty() {
        "riptide-backup.zip".into()
    } else {
        remote_path
    };
    cfg.enabled = enabled;
    webdav::set_password(&mut cfg, &password)?;
    webdav::save_config(&cfg)?;
    Ok(WebDAVConfigDto::from(&cfg))
}

#[tauri::command]
pub async fn webdav_test_connection() -> Result<(), String> {
    let cfg = webdav::load_config();
    webdav::test_connection(&cfg).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn webdav_backup_now() -> Result<(), String> {
    let cfg = webdav::load_config();
    // Build zip on the blocking pool — file I/O.
    let bytes = tokio::task::spawn_blocking(webdav::build_backup_zip)
        .await
        .map_err(|e| format!("join: {}", e))?
        .map_err(|e| e.to_string())?;
    webdav::upload_backup(&cfg, bytes).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn webdav_restore_now() -> Result<(), String> {
    let cfg = webdav::load_config();
    let bytes = webdav::download_backup(&cfg)
        .await
        .map_err(|e| e.to_string())?;
    tokio::task::spawn_blocking(move || webdav::extract_backup_zip(&bytes))
        .await
        .map_err(|e| format!("join: {}", e))?
        .map_err(|e| e.to_string())?;
    Ok(())
}
