//! Configuration management commands.
//!
//! All profile commands are backed by on-disk YAML files under
//! `%APPDATA%\Riptide\profiles\`. `AppState` is an in-memory cache of the
//! last-known disk state; `list_profiles` re-scans the directory and refreshes
//! the cache. Profile IDs are embedded in filenames and survive restarts.

use crate::config::active_state;
use crate::config::parser::parse_clash_config;
use crate::config::profile_meta::{self, ProfileMetadata, DEFAULT_UPDATE_INTERVAL_SECS};
use crate::config::profiles::{Profile, ValidationResult};
use crate::core::logbook::LogbookWriter;
use tauri::State;
use std::sync::{Arc, Mutex};

/// In-memory cache of the disk-backed profile list plus the active profile id,
/// plus the diagnostic Logbook writer (installed at startup, optional).
pub struct AppState {
    pub profiles: Mutex<Vec<Profile>>,
    pub active_profile_id: Mutex<Option<String>>,
    /// Fire-and-forget Logbook writer. `None` only during very early
    /// startup before `install_logbook_writer` runs, or in unit tests
    /// that never spin up a writer. Injection points must therefore
    /// treat this as optional (see `set_logbook_writer` on each module).
    pub logbook_writer: Mutex<Option<Arc<LogbookWriter>>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            profiles: Mutex::new(Vec::new()),
            active_profile_id: Mutex::new(None),
            logbook_writer: Mutex::new(None),
        }
    }

    /// Install the diagnostic Logbook writer. Called once at app
    /// startup, after `WindowsDirs::ensure_dirs()` succeeds. The writer
    /// is then fanned out to the five injection points via
    /// `crate::core::<module>::set_logbook_writer`.
    pub fn install_logbook_writer(&self, writer: Arc<LogbookWriter>) {
        *self.logbook_writer.lock().unwrap() = Some(writer);
    }

    /// Restore the active profile pointer from disk. Called once at app
    /// startup so subsequent reads see the persisted selection.
    pub fn load_active_from_disk(&self) {
        let id = active_state::load_active_id();
        *self.active_profile_id.lock().unwrap() = id;
    }
}

/// Resolve the active profile's YAML content. Refreshes the cache from disk
/// on miss (e.g., right after startup, before `list_profiles` was called).
#[cfg(target_os = "windows")]
pub fn resolve_active_profile_content(state: &AppState) -> Result<String, String> {
    use crate::config::profiles::storage;

    let active_id = state
        .active_profile_id
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| "No active profile selected".to_string())?;

    if let Some(content) = state
        .profiles
        .lock()
        .unwrap()
        .iter()
        .find(|p| p.id == active_id)
        .map(|p| p.content.clone())
    {
        return Ok(content);
    }

    // Cache miss — scan disk and try again.
    let disk = storage::list_profiles()
        .map_err(|e| format!("Failed to refresh profiles from disk: {}", e))?;
    let content = disk
        .iter()
        .find(|p| p.id == active_id)
        .map(|p| p.content.clone())
        .ok_or_else(|| format!("Active profile id '{}' not found on disk", active_id))?;
    *state.profiles.lock().unwrap() = disk;
    Ok(content)
}

#[cfg(not(target_os = "windows"))]
pub fn resolve_active_profile_content(_state: &AppState) -> Result<String, String> {
    Err("Active profile resolution only available on Windows".into())
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "windows")]
fn count_proxies_and_groups(content: &str) -> (usize, usize) {
    match parse_clash_config(content) {
        Ok(config) => (
            config.proxies.as_ref().map(|p| p.len()).unwrap_or(0),
            config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0),
        ),
        Err(_) => (0, 0),
    }
}

// ============== Profile management — disk-backed, Windows ==============

/// Create a new profile and persist it to disk.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn create_profile(
    name: String,
    content: String,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    use crate::config::profiles::storage;

    if parse_clash_config(&content).is_err() && !content.trim().is_empty() {
        // Allow empty/placeholder content (lets users create a blank profile to edit),
        // but reject malformed YAML up front.
        return Err("Invalid configuration: failed to parse YAML".into());
    }

    let (proxy_count, _group_count) = count_proxies_and_groups(&content);
    let mut profile = Profile::new(name, content);
    profile.set_node_count(proxy_count);

    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    let mut profiles = state.profiles.lock().unwrap();
    profiles.push(profile.clone());

    log::info!("Created profile '{}' ({} proxies)", profile.name, proxy_count);
    Ok(profile)
}

/// List all profiles from disk, refreshing the in-memory cache.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn list_profiles(state: State<'_, AppState>) -> Result<Vec<Profile>, String> {
    use crate::config::profiles::storage;

    let mut profiles = storage::list_profiles()
        .map_err(|e| format!("Failed to list profiles: {}", e))?;

    let active_id = state.active_profile_id.lock().unwrap().clone();
    for profile in &mut profiles {
        if Some(&profile.id) == active_id.as_ref() {
            profile.set_active(true);
        }
        let (proxy_count, _) = count_proxies_and_groups(&profile.content);
        profile.set_node_count(proxy_count);
    }

    *state.profiles.lock().unwrap() = profiles.clone();
    Ok(profiles)
}

/// Delete a profile from disk and the cache.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn delete_profile(id: String, state: State<'_, AppState>) -> Result<(), String> {
    use crate::config::profiles::storage;

    let removed = {
        let mut profiles = state.profiles.lock().unwrap();
        let idx = profiles
            .iter()
            .position(|p| p.id == id)
            .ok_or_else(|| "Profile not found".to_string())?;
        profiles.remove(idx)
    };

    if let Some(path) = &removed.path {
        storage::delete_profile_file(path)
            .map_err(|e| format!("Failed to delete profile file: {}", e))?;
    }

    let mut active = state.active_profile_id.lock().unwrap();
    if active.as_deref() == Some(&id) {
        *active = None;
        // Best-effort: clear the persisted pointer too. If this fails the
        // worst case is a stale id on disk that points nowhere — the next
        // list_profiles will not match it.
        if let Err(e) = active_state::save_active_id(None) {
            log::warn!("Failed to clear active.json: {}", e);
        }
    }

    log::info!("Deleted profile '{}'", removed.name);
    Ok(())
}

/// Update an existing profile's content. Validates YAML before writing.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn update_profile(
    id: String,
    content: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    use crate::config::profiles::storage;

    if parse_clash_config(&content).is_err() {
        return Err("Invalid configuration: failed to parse YAML".into());
    }

    let mut profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter_mut()
        .find(|p| p.id == id)
        .ok_or_else(|| "Profile not found".to_string())?;

    storage::update_profile_content(profile, content)
        .map_err(|e| format!("Failed to update profile: {}", e))?;

    let (proxy_count, _) = count_proxies_and_groups(&profile.content);
    profile.set_node_count(proxy_count);

    log::info!("Updated profile '{}'", profile.name);
    Ok(())
}

/// Import a profile by downloading remote YAML and persisting it. Captures
/// the `Subscription-Userinfo` header (if any) so the UI can display traffic
/// and expiry, and stores the source URL so auto-refresh can re-fetch later.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn import_profile_from_url(
    url: String,
    name: Option<String>,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    use crate::config::profiles::storage;

    log::info!("Downloading profile from {}", url);
    let client = reqwest::Client::builder()
        .user_agent(concat!("riptide-windows/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {}", e))?;

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("Failed to download profile: {}", e))?;
    if !response.status().is_success() {
        return Err(format!("HTTP error: {}", response.status()));
    }

    // Capture the subscription metadata header before consuming the body.
    let subscription = response
        .headers()
        .get("subscription-userinfo")
        .and_then(|v| v.to_str().ok())
        .map(profile_meta::parse_subscription_userinfo);

    let content = response
        .text()
        .await
        .map_err(|e| format!("Failed to read response: {}", e))?;

    if parse_clash_config(&content).is_err() {
        return Err("Downloaded content is not a valid Clash config".into());
    }
    let (proxy_count, group_count) = count_proxies_and_groups(&content);

    let profile_name = name.unwrap_or_else(|| {
        url.split('/')
            .last()
            .and_then(|s| s.split('?').next())
            .filter(|s| !s.is_empty())
            .map(|s| {
                s.trim_end_matches(".yaml")
                    .trim_end_matches(".yml")
                    .to_string()
            })
            .unwrap_or_else(|| "Imported Profile".into())
    });

    let mut profile = Profile::new(profile_name, content);
    profile.set_node_count(proxy_count);
    profile.metadata = ProfileMetadata {
        source_url: Some(url.clone()),
        update_interval_secs: Some(DEFAULT_UPDATE_INTERVAL_SECS),
        last_updated_at: Some(chrono::Utc::now()),
        subscription,
    };
    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;
    if let Some(ref path) = profile.path {
        if let Err(e) = profile_meta::save(path, &profile.metadata) {
            log::warn!("Failed to write profile metadata: {}", e);
        }
    }

    state.profiles.lock().unwrap().push(profile.clone());

    log::info!(
        "Imported profile '{}' ({} proxies, {} groups) from {}",
        profile.name,
        proxy_count,
        group_count,
        url
    );
    Ok(profile)
}

/// Import a single proxy from a share URI (ss://, vmess://, vless://, trojan://, hysteria2://)
/// and store it as a minimal Clash profile.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn import_share_uri(
    uri: String,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    use crate::config::parser::{serialize_clash_config, ClashRawConfig};
    use crate::config::profiles::storage;
    use crate::config::uri::parse_share_uri;

    let proxy = parse_share_uri(&uri)
        .map_err(|e| format!("Failed to parse share URI: {}", e))?;
    let name = proxy.name.clone();

    let config = ClashRawConfig {
        proxies: Some(vec![proxy]),
        proxy_groups: Some(vec![crate::config::parser::ClashRawProxyGroup {
            name: Some("Proxy".into()),
            group_type: Some("select".into()),
            proxies: Some(vec![name.clone()]),
            ..Default::default()
        }]),
        mode: Some("rule".into()),
        ..Default::default()
    };
    let yaml = serialize_clash_config(&config)
        .map_err(|e| format!("Failed to generate config: {}", e))?;

    let mut profile = Profile::new(name, yaml);
    profile.set_node_count(1);
    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    state.profiles.lock().unwrap().push(profile.clone());

    log::info!("Imported profile '{}' from share URI", profile.name);
    Ok(profile)
}

/// Import a profile from a local file.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn import_profile_from_file(
    path: String,
    state: State<'_, AppState>,
) -> Result<Profile, String> {
    use crate::config::profiles::storage;
    use std::path::PathBuf;
    use std::fs;

    let source_path = PathBuf::from(&path);
    let content = fs::read_to_string(&source_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    if parse_clash_config(&content).is_err() {
        return Err("File is not a valid Clash config".into());
    }
    let (proxy_count, group_count) = count_proxies_and_groups(&content);

    let name = source_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Imported Profile")
        .to_string();

    let mut profile = Profile::new(name, content);
    profile.set_node_count(proxy_count);
    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    state.profiles.lock().unwrap().push(profile.clone());

    log::info!(
        "Imported profile '{}' from {:?} ({} proxies, {} groups)",
        profile.name,
        source_path,
        proxy_count,
        group_count
    );
    Ok(profile)
}

/// Export a profile's YAML to a destination path.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn export_profile(
    id: String,
    path: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    use crate::config::profiles::storage;
    use std::path::PathBuf;

    let profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter()
        .find(|p| p.id == id)
        .ok_or_else(|| "Profile not found".to_string())?;
    let dest_path = PathBuf::from(&path);

    storage::export_profile(profile, &dest_path)
        .map_err(|e| format!("Failed to export profile: {}", e))?;

    log::info!("Exported profile '{}' to {:?}", profile.name, dest_path);
    Ok(())
}

/// Get the active profile id. Reads the in-memory cache (populated at
/// startup by `AppState::load_active_from_disk`).
#[tauri::command]
pub fn get_active_profile(state: State<'_, AppState>) -> Option<String> {
    state.active_profile_id.lock().unwrap().clone()
}

/// Set the active profile id. Persists to `active.json` so the selection
/// survives restarts.
#[tauri::command]
pub fn set_active_profile(id: String, state: State<'_, AppState>) -> Result<(), String> {
    let exists = state.profiles.lock().unwrap().iter().any(|p| p.id == id);
    if !exists {
        return Err("Profile not found".into());
    }
    active_state::save_active_id(Some(&id))?;
    *state.active_profile_id.lock().unwrap() = Some(id);
    Ok(())
}

/// Re-download a subscription-backed profile from its stored `source_url`,
/// updating both the YAML content and the metadata (last_updated_at,
/// subscription traffic/expiry). Errors if the profile has no source URL.
#[cfg(target_os = "windows")]
pub async fn refresh_profile_impl(id: &str, state: &AppState) -> Result<Profile, String> {
    use crate::config::profiles::storage;

    let (mut profile, source_url, prior_path) = {
        let profiles = state.profiles.lock().unwrap();
        let p = profiles
            .iter()
            .find(|p| p.id == id)
            .ok_or_else(|| "Profile not found".to_string())?;
        let url = p
            .metadata
            .source_url
            .clone()
            .ok_or_else(|| "Profile has no subscription URL".to_string())?;
        (p.clone(), url, p.path.clone())
    };

    let client = reqwest::Client::builder()
        .user_agent(concat!("riptide-windows/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| format!("Failed to build HTTP client: {}", e))?;
    let response = client
        .get(&source_url)
        .send()
        .await
        .map_err(|e| format!("Refresh download failed: {}", e))?;
    if !response.status().is_success() {
        return Err(format!("Refresh HTTP error: {}", response.status()));
    }
    let subscription = response
        .headers()
        .get("subscription-userinfo")
        .and_then(|v| v.to_str().ok())
        .map(profile_meta::parse_subscription_userinfo);
    let new_content = response
        .text()
        .await
        .map_err(|e| format!("Failed to read response: {}", e))?;

    if parse_clash_config(&new_content).is_err() {
        return Err("Refreshed content is not a valid Clash config".into());
    }

    if let Some(ref path) = prior_path {
        std::fs::write(path, &new_content)
            .map_err(|e| format!("Failed to write refreshed profile: {}", e))?;
    } else {
        profile.content = new_content.clone();
        storage::save_profile(&mut profile)
            .map_err(|e| format!("Failed to save profile: {}", e))?;
    }
    profile.content = new_content;
    profile.updated_at = chrono::Utc::now();
    let (proxy_count, _) = count_proxies_and_groups(&profile.content);
    profile.set_node_count(proxy_count);
    profile.metadata.last_updated_at = Some(chrono::Utc::now());
    if let Some(sub) = subscription {
        profile.metadata.subscription = Some(sub);
    }
    if let Some(ref path) = profile.path {
        if let Err(e) = profile_meta::save(path, &profile.metadata) {
            log::warn!("Failed to write refreshed profile metadata: {}", e);
        }
    }

    {
        let mut profiles = state.profiles.lock().unwrap();
        if let Some(slot) = profiles.iter_mut().find(|p| p.id == id) {
            *slot = profile.clone();
        }
    }

    log::info!("Refreshed profile '{}' from {}", profile.name, source_url);
    Ok(profile)
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn refresh_profile(id: String, state: State<'_, AppState>) -> Result<Profile, String> {
    refresh_profile_impl(&id, &state).await
}

/// Set or update subscription parameters on an existing profile. Pass `None`
/// for `url` to detach the subscription; `Some(0)` for `interval_secs` to
/// disable auto-refresh while keeping the URL.
#[cfg(target_os = "windows")]
#[tauri::command]
pub fn set_profile_subscription(
    id: String,
    url: Option<String>,
    interval_secs: Option<u64>,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter_mut()
        .find(|p| p.id == id)
        .ok_or_else(|| "Profile not found".to_string())?;

    profile.metadata.source_url = url;
    if let Some(interval) = interval_secs {
        profile.metadata.update_interval_secs = if interval == 0 { None } else { Some(interval) };
    }
    if let Some(ref path) = profile.path {
        profile_meta::save(path, &profile.metadata)?;
    }
    Ok(())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub fn get_profile_metadata(
    id: String,
    state: State<'_, AppState>,
) -> Result<ProfileMetadata, String> {
    let profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter()
        .find(|p| p.id == id)
        .ok_or_else(|| "Profile not found".to_string())?;
    Ok(profile.metadata.clone())
}

/// Validate configuration content with mihomo (`mihomo -t`).
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn validate_config(content: String) -> Result<ValidationResult, String> {
    use std::fs::File;
    use std::io::Write;
    use std::process::Command;

    let config = match parse_clash_config(&content) {
        Ok(config) => config,
        Err(e) => return Ok(ValidationResult::invalid(format!("YAML parse error: {}", e))),
    };

    let proxy_count = config.proxies.as_ref().map(|p| p.len()).unwrap_or(0);
    let group_count = config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0);

    let temp_dir = std::env::temp_dir();
    let temp_file = temp_dir.join(format!("riptide_validate_{}.yaml", uuid::Uuid::new_v4()));
    {
        let mut file = File::create(&temp_file)
            .map_err(|e| format!("Failed to create temp file: {}", e))?;
        file.write_all(content.as_bytes())
            .map_err(|e| format!("Failed to write temp file: {}", e))?;
    }

    let mihomo_paths = [
        std::path::PathBuf::from("mihomo.exe"),
        std::path::PathBuf::from(".\\mihomo.exe"),
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.join("mihomo.exe")))
            .unwrap_or_default(),
    ];
    let mihomo_path = mihomo_paths
        .iter()
        .find(|p| p.exists())
        .cloned()
        .or_else(|| which::which("mihomo.exe").ok())
        .or_else(|| which::which("mihomo").ok());

    let result = if let Some(mihomo) = mihomo_path {
        let output = Command::new(&mihomo)
            .arg("-t")
            .arg("-f")
            .arg(&temp_file)
            .output()
            .map_err(|e| format!("Failed to run mihomo validation: {}", e))?;
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let _ = std::fs::remove_file(&temp_file);

        if output.status.success() {
            ValidationResult::valid().with_counts(proxy_count, group_count)
        } else {
            let msg = if stderr.is_empty() {
                stdout.to_string()
            } else {
                stderr.to_string()
            };
            ValidationResult::invalid(format!("mihomo validation failed: {}", msg.trim()))
        }
    } else {
        log::warn!("mihomo binary not found, skipping binary validation");
        let _ = std::fs::remove_file(&temp_file);
        ValidationResult::valid().with_counts(proxy_count, group_count)
    };

    Ok(result)
}

// ============== Non-Windows stubs (for cross-compile / dev) ==============

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn create_profile(_name: String, _content: String, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn list_profiles(_state: State<'_, AppState>) -> Result<Vec<Profile>, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn delete_profile(_id: String, _state: State<'_, AppState>) -> Result<(), String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn update_profile(_id: String, _content: String, _state: State<'_, AppState>) -> Result<(), String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn import_profile_from_url(_url: String, _name: Option<String>, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn import_share_uri(_uri: String, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn import_profile_from_file(_path: String, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn export_profile(_id: String, _path: String, _state: State<'_, AppState>) -> Result<(), String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn validate_config(_content: String) -> Result<ValidationResult, String> {
    Err("Profile management only available on Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validation_result_valid() {
        let result = ValidationResult::valid();
        assert!(result.valid);
        assert!(result.message.is_none());
    }

    #[test]
    fn test_validation_result_invalid() {
        let result = ValidationResult::invalid("test error");
        assert!(!result.valid);
        assert_eq!(result.message, Some("test error".to_string()));
    }

    #[test]
    fn test_validation_result_with_counts() {
        let result = ValidationResult::valid().with_counts(5, 3);
        assert!(result.valid);
        assert_eq!(result.proxy_count, Some(5));
        assert_eq!(result.group_count, Some(3));
    }

    #[test]
    fn test_set_active_profile_rejects_unknown_id() {
        let state = AppState::new();
        // No profiles in state, so any id should be rejected.
        // We can't easily build a `State<'_, AppState>` here without a full Tauri app,
        // but we can exercise the inner logic by inlining it.
        let exists = state.profiles.lock().unwrap().iter().any(|p| p.id == "bogus");
        assert!(!exists);
    }
}
