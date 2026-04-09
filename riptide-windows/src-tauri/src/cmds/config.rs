//! Configuration management commands

use crate::config::parser::parse_clash_config;
use crate::config::profiles::Profile;
use tauri::State;
use std::sync::Mutex;

/// Get all profiles
#[tauri::command]
pub fn get_profiles(state: State<'_, Mutex<Vec<Profile>>>) -> Vec<Profile> {
    state.lock().unwrap().clone()
}

/// Add a new profile
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

/// Remove a profile
#[tauri::command]
pub fn remove_profile(
    state: State<'_, Mutex<Vec<Profile>>>,
    id: String,
) -> Result<(), String> {
    let mut profiles = state.lock().unwrap();
    profiles.retain(|p| p.id != id);
    Ok(())
}

/// Update a profile
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
