//! Configuration management commands

use crate::config::parser::parse_clash_config;
use crate::config::profiles::{Profile, ValidationResult};
use tauri::State;
use std::sync::Mutex;

/// AppState for profile management
pub struct AppState {
    pub profiles: Mutex<Vec<Profile>>,
    pub active_profile_id: Mutex<Option<String>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            profiles: Mutex::new(Vec::new()),
            active_profile_id: Mutex::new(None),
        }
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

/// Get all profiles (legacy command for compatibility)
#[tauri::command]
pub fn get_profiles(state: State<'_, Mutex<Vec<Profile>>>) -> Vec<Profile> {
    state.lock().unwrap().clone()
}

/// Add a new profile (legacy command for compatibility)
#[tauri::command]
pub fn add_profile(
    state: State<'_, Mutex<Vec<Profile>>>,
    name: String,
    content: String,
) -> Result<Profile, String> {
    let mut profiles = state.lock().unwrap();
    let profile = Profile::new(name, content);
    profiles.push(profile.clone());
    Ok(profile)
}

/// Remove a profile (legacy command for compatibility)
#[tauri::command]
pub fn remove_profile(
    state: State<'_, Mutex<Vec<Profile>>>,
    id: String,
) -> Result<(), String> {
    let mut profiles = state.lock().unwrap();
    profiles.retain(|p| p.id != id);
    Ok(())
}

/// Update a profile (legacy command for compatibility)
#[tauri::command]
pub fn update_profile(
    state: State<'_, Mutex<Vec<Profile>>>,
    id: String,
    content: String,
) -> Result<(), String> {
    let mut profiles = state.lock().unwrap();
    if let Some(profile) = profiles.iter_mut().find(|p| p.id == id) {
        profile.content = content;
        profile.updated_at = chrono::Utc::now();
        Ok(())
    } else {
        Err("Profile not found".to_string())
    }
}

/// Import profile from URL
#[tauri::command]
pub async fn import_profile_from_url(
    state: State<'_, Mutex<Vec<Profile>>>,
    url: String,
    name: Option<String>,
) -> Result<Profile, String> {
    // Download profile content from URL
    log::info!("Downloading profile from: {}", url);

    let response = reqwest::get(&url)
        .await
        .map_err(|e| format!("Failed to download profile: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("HTTP error: {}", response.status()));
    }

    let content = response.text()
        .await
        .map_err(|e| format!("Failed to read response: {}", e))?;

    // Validate YAML by parsing it
    match parse_clash_config(&content) {
        Ok(config) => {
            log::info!("Successfully parsed Clash config");

            // Count proxies and groups for logging
            let proxy_count = config.proxies.as_ref().map(|p| p.len()).unwrap_or(0);
            let group_count = config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0);
            log::info!("Config contains {} proxies and {} groups", proxy_count, group_count);
        }
        Err(e) => {
            return Err(format!("Invalid Clash config: {}", e));
        }
    }

    // Determine profile name
    let profile_name = name.unwrap_or_else(|| {
        // Extract filename from URL or use domain
        url.split('/')
            .last()
            .and_then(|s| s.split('?').next())
            .filter(|s| !s.is_empty())
            .map(|s| {
                if s.ends_with(".yaml") || s.ends_with(".yml") {
                    s.trim_end_matches(".yaml").trim_end_matches(".yml").to_string()
                } else {
                    s.to_string()
                }
            })
            .unwrap_or_else(|| "Imported Profile".to_string())
    });

    // Create and store profile
    let profile = Profile::new(profile_name, content);

    let mut profiles = state.lock().unwrap();
    profiles.push(profile.clone());

    log::info!("Profile '{}' imported successfully", profile.name);
    Ok(profile)
}

/// Import profile from a share URI (ss://, trojan://, vless://, vmess://, hysteria2://)
#[tauri::command]
pub async fn import_share_uri(
    uri: String,
    state: State<'_, Mutex<Vec<Profile>>>,
) -> Result<Profile, String> {
    use crate::config::parser::{serialize_clash_config, ClashRawConfig};
    use crate::config::uri::parse_share_uri;

    // Parse the URI into a single proxy
    let proxy = parse_share_uri(&uri)
        .map_err(|e| format!("Failed to parse share URI: {}", e))?;

    let name = proxy.name.clone();

    // Wrap in a minimal Clash config
    let config = ClashRawConfig {
        proxies: Some(vec![proxy]),
        proxy_groups: Some(vec![
            crate::config::parser::ClashRawProxyGroup {
                name: Some("Proxy".into()),
                group_type: Some("select".into()),
                proxies: Some(vec![name.clone()]),
                ..Default::default()
            },
        ]),
        mode: Some("rule".into()),
        ..Default::default()
    };

    let yaml = serialize_clash_config(&config)
        .map_err(|e| format!("Failed to generate config: {}", e))?;

    // Create and store the profile
    let profile = Profile::new(name, yaml);
    let mut profiles = state.lock().unwrap();
    profiles.push(profile.clone());

    log::info!("Profile '{}' created from share URI", profile.name);
    Ok(profile)
}

/// Get active profile ID
#[tauri::command]
pub fn get_active_profile() -> Option<String> {
    // TODO: Get from config storage
    None
}

/// Set active profile
#[tauri::command]
pub fn set_active_profile(id: String) -> Result<(), String> {
    // TODO: Save to config storage
    let _ = id;
    Ok(())
}

// ============== Windows-specific Profile Management Commands ==============

/// Create a new profile with validation and file storage
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn create_profile(
    name: String,
    content: String,
    state: State<'_, AppState>
) -> Result<Profile, String> {
    use crate::config::profiles::storage;
    use crate::config::parser::parse_clash_config;

    // Validate configuration syntax
    let (proxy_count, group_count) = match parse_clash_config(&content) {
        Ok(config) => {
            let proxy_count = config.proxies.as_ref().map(|p| p.len()).unwrap_or(0);
            let group_count = config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0);
            (proxy_count, group_count)
        }
        Err(e) => {
            return Err(format!("Invalid configuration: {}", e));
        }
    };

    // Create profile and save to disk
    let mut profile = Profile::new(name, content);
    profile.set_node_count(proxy_count);

    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    // Add to state
    let mut profiles = state.profiles.lock().unwrap();
    profiles.push(profile.clone());

    log::info!("Created profile '{}' with {} proxies, {} groups", profile.name, proxy_count, group_count);
    Ok(profile)
}

/// List all profiles from file storage
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn list_profiles(
    state: State<'_, AppState>
) -> Result<Vec<Profile>, String> {
    use crate::config::profiles::storage;

    // Scan profiles directory
    let mut profiles = storage::list_profiles()
        .map_err(|e| format!("Failed to list profiles: {}", e))?;

    // Check active status
    let active_id = state.active_profile_id.lock().unwrap();
    for profile in &mut profiles {
        if let Some(ref id) = *active_id {
            if profile.id == *id {
                profile.set_active(true);
            }
        }
    }

    // Update state
    *state.profiles.lock().unwrap() = profiles.clone();

    Ok(profiles)
}

/// Delete a profile
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn delete_profile(
    id: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    use crate::config::profiles::storage;

    // Find profile in state
    let mut profiles = state.profiles.lock().unwrap();
    let profile_idx = profiles.iter().position(|p| p.id == id);

    if let Some(idx) = profile_idx {
        let profile = profiles.remove(idx);

        // Delete file if path exists
        if let Some(path) = &profile.path {
            storage::delete_profile_file(path)
                .map_err(|e| format!("Failed to delete profile file: {}", e))?;
        }

        log::info!("Deleted profile '{}'", profile.name);
        Ok(())
    } else {
        Err("Profile not found".to_string())
    }
}

/// Import profile from a file
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn import_profile_from_file(
    path: String,
    state: State<'_, AppState>
) -> Result<Profile, String> {
    use crate::config::profiles::storage;
    use std::path::PathBuf;
    use std::fs;

    let source_path = PathBuf::from(&path);

    // Read file content
    let content = fs::read_to_string(&source_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    // Validate configuration
    let (proxy_count, group_count) = match parse_clash_config(&content) {
        Ok(config) => {
            let proxy_count = config.proxies.as_ref().map(|p| p.len()).unwrap_or(0);
            let group_count = config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0);
            (proxy_count, group_count)
        }
        Err(e) => {
            return Err(format!("Invalid configuration: {}", e));
        }
    };

    // Extract name from source filename
    let name = source_path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Imported Profile")
        .to_string();

    // Create and save profile
    let mut profile = Profile::new(name, content);
    profile.set_node_count(proxy_count);

    storage::save_profile(&mut profile)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    // Add to state
    let mut profiles = state.profiles.lock().unwrap();
    profiles.push(profile.clone());

    log::info!("Imported profile '{}' from {:?} with {} proxies, {} groups",
        profile.name, source_path, proxy_count, group_count);
    Ok(profile)
}

/// Export a profile to a specific path
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn export_profile(
    id: String,
    path: String,
    state: State<'_, AppState>
) -> Result<(), String> {
    use crate::config::profiles::storage;
    use std::path::PathBuf;

    // Find profile in state
    let profiles = state.profiles.lock().unwrap();
    let profile = profiles.iter().find(|p| p.id == id)
        .ok_or_else(|| "Profile not found".to_string())?;

    let dest_path = PathBuf::from(&path);

    storage::export_profile(profile, &dest_path)
        .map_err(|e| format!("Failed to export profile: {}", e))?;

    log::info!("Exported profile '{}' to {:?}", profile.name, dest_path);
    Ok(())
}

/// Validate configuration content using mihomo
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn validate_config(
    content: String
) -> Result<ValidationResult, String> {
    use crate::config::parser::parse_clash_config;
    use std::io::Write;
    use std::process::Command;
    use std::fs::File;

    // First, do basic YAML parsing
    let config = match parse_clash_config(&content) {
        Ok(config) => config,
        Err(e) => {
            return Ok(ValidationResult::invalid(format!("YAML parse error: {}", e)));
        }
    };

    let proxy_count = config.proxies.as_ref().map(|p| p.len()).unwrap_or(0);
    let group_count = config.proxy_groups.as_ref().map(|g| g.len()).unwrap_or(0);

    // Create a temporary file for mihomo validation
    let temp_dir = std::env::temp_dir();
    let temp_file = temp_dir.join(format!("riptide_validate_{}.yaml", uuid::Uuid::new_v4()));

    // Write content to temp file
    {
        let mut file = File::create(&temp_file)
            .map_err(|e| format!("Failed to create temp file: {}", e))?;
        file.write_all(content.as_bytes())
            .map_err(|e| format!("Failed to write temp file: {}", e))?;
    }

    // Try to find mihomo binary
    // First check if it exists in expected locations
    let mihomo_paths = [
        std::path::PathBuf::from("mihomo.exe"),
        std::path::PathBuf::from(".\\mihomo.exe"),
        std::env::current_exe().ok().map(|p| p.parent().map(|p| p.join("mihomo.exe"))).flatten().unwrap_or_default(),
    ];

    let mihomo_path = mihomo_paths.iter()
        .find(|p| p.exists())
        .cloned()
        .or_else(|| which::which("mihomo.exe").ok())
        .or_else(|| which::which("mihomo").ok());

    let validation_result = if let Some(mihomo) = mihomo_path {
        // Run mihomo -t to validate config
        let output = Command::new(&mihomo)
            .arg("-t")
            .arg("-f")
            .arg(&temp_file)
            .output()
            .map_err(|e| format!("Failed to run mihomo validation: {}", e))?;

        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_file);

        if output.status.success() {
            ValidationResult::valid()
                .with_counts(proxy_count, group_count)
        } else {
            let error_msg = if stderr.is_empty() { stdout.to_string() } else { stderr.to_string() };
            ValidationResult::invalid(format!("mihomo validation failed: {}", error_msg.trim()))
        }
    } else {
        // mihomo not available, skip binary validation
        log::warn!("mihomo binary not found, skipping binary validation");

        // Clean up temp file
        let _ = std::fs::remove_file(&temp_file);

        ValidationResult::valid()
            .with_counts(proxy_count, group_count)
    };

    Ok(validation_result)
}

// Add dependency on which crate for finding mihomo binary
// This is a placeholder - the which crate should be added to Cargo.toml

/// Non-Windows stub implementations
#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn create_profile(_name: String, _content: String, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn list_profiles(_state: State<'_, AppState>) -> Result<Vec<Profile>, String> {
    Err("Profile management only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn delete_profile(_id: String, _state: State<'_, AppState>) -> Result<(), String> {
    Err("Profile management only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn import_profile_from_file(_path: String, _state: State<'_, AppState>) -> Result<Profile, String> {
    Err("Profile management only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn export_profile(_id: String, _path: String, _state: State<'_, AppState>) -> Result<(), String> {
    Err("Profile management only available on Windows".to_string())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn validate_config(_content: String) -> Result<ValidationResult, String> {
    Err("Profile management only available on Windows".to_string())
}

// Stub for non-Windows builds where AppState isn't used
#[cfg(not(target_os = "windows"))]
impl AppState {
    pub fn new() -> Self {
        Self {
            profiles: Mutex::new(Vec::new()),
            active_profile_id: Mutex::new(None),
        }
    }
}

#[cfg(not(target_os = "windows"))]
impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
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
}
