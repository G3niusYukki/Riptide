//! Configuration management commands

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
) -> Result<(), String> {
    let mut profiles = state.lock().unwrap();
    let profile = Profile::new(name, content);
    profiles.push(profile);
    Ok(())
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
pub async fn import_profile_from_url(url: String) -> Result<String, String> {
    // TODO: Download and parse profile from URL
    Ok("Profile imported".to_string())
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
    Ok(())
}
