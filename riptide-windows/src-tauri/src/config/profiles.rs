//! Profile management

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    // Extended fields for Windows profile management
    pub path: Option<PathBuf>,
    pub is_active: bool,
    pub node_count: Option<usize>,
}

impl Profile {
    pub fn new(name: String, content: String) -> Self {
        let id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();

        Self {
            id,
            name,
            content,
            created_at: now,
            updated_at: now,
            path: None,
            is_active: false,
            node_count: None,
        }
    }

    /// Create a new profile with a specific file path
    pub fn new_with_path(name: String, content: String, path: PathBuf) -> Self {
        let mut profile = Self::new(name, content);
        profile.path = Some(path);
        profile
    }

    /// Parse YAML content to verify validity
    pub fn validate(&self) -> Result<(), String> {
        // TODO: Implement YAML validation
        Ok(())
    }

    /// Get proxies from profile
    pub fn get_proxies(&self) -> Vec<Proxy> {
        // TODO: Parse YAML and extract proxies
        Vec::new()
    }

    /// Get proxy groups from profile
    pub fn get_proxy_groups(&self) -> Vec<ProxyGroup> {
        // TODO: Parse YAML and extract proxy groups
        Vec::new()
    }

    /// Update the node count
    pub fn set_node_count(&mut self, count: usize) {
        self.node_count = Some(count);
    }

    /// Set as active profile
    pub fn set_active(&mut self, active: bool) {
        self.is_active = active;
    }

    /// Get the file path as string
    pub fn path_string(&self) -> Option<String> {
        self.path.as_ref().map(|p| p.to_string_lossy().to_string())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proxy {
    pub name: String,
    pub server: String,
    pub port: u16,
    pub proxy_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyGroup {
    pub name: String,
    pub group_type: String, // select, url-test, fallback, load-balance
    pub proxies: Vec<String>,
    pub url: Option<String>,
    pub interval: Option<u32>,
}

/// Result of configuration validation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub valid: bool,
    pub message: Option<String>,
    pub proxy_count: Option<usize>,
    pub group_count: Option<usize>,
}

impl ValidationResult {
    pub fn valid() -> Self {
        Self {
            valid: true,
            message: None,
            proxy_count: None,
            group_count: None,
        }
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self {
            valid: false,
            message: Some(message.into()),
            proxy_count: None,
            group_count: None,
        }
    }

    pub fn with_counts(mut self, proxies: usize, groups: usize) -> Self {
        self.proxy_count = Some(proxies);
        self.group_count = Some(groups);
        self
    }
}

/// Profile storage manager for file-based operations
#[cfg(target_os = "windows")]
pub mod storage {
    use super::*;
    use crate::utils::windows_dirs::WindowsDirs;
    use std::fs;

    /// Get the profiles directory
    pub fn get_profiles_dir() -> PathBuf {
        WindowsDirs::profiles_dir()
    }

    /// Generate a unique filename for a profile
    pub fn generate_profile_filename(name: &str) -> String {
        let sanitized = name
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect::<String>();
        format!("{}_{}.yaml", sanitized, uuid::Uuid::new_v4().to_simple())
    }

    /// Save a profile to disk
    pub fn save_profile(profile: &mut Profile) -> Result<(), String> {
        // Ensure directory exists
        WindowsDirs::ensure_dirs()
            .map_err(|e| format!("Failed to create directories: {}", e))?;

        // Generate path if not set
        if profile.path.is_none() {
            let filename = generate_profile_filename(&profile.name);
            let path = get_profiles_dir().join(&filename);
            profile.path = Some(path);
        }

        let path = profile.path.as_ref().unwrap();

        // Write content to file
        fs::write(path, &profile.content)
            .map_err(|e| format!("Failed to write profile file: {}", e))?;

        profile.updated_at = Utc::now();

        Ok(())
    }

    /// Load a profile from disk
    pub fn load_profile(path: &PathBuf) -> Result<Profile, String> {
        let content = fs::read_to_string(path)
            .map_err(|e| format!("Failed to read profile file: {}", e))?;

        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown")
            .to_string();

        let metadata = fs::metadata(path)
            .map_err(|e| format!("Failed to read file metadata: {}", e))?;

        let created_at = metadata
            .created()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| DateTime::from_timestamp(d.as_secs() as i64, 0))
            .flatten()
            .unwrap_or_else(Utc::now);

        let updated_at = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| DateTime::from_timestamp(d.as_secs() as i64, 0))
            .flatten()
            .unwrap_or_else(Utc::now);

        Ok(Profile {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            content,
            created_at,
            updated_at,
            path: Some(path.clone()),
            is_active: false,
            node_count: None,
        })
    }

    /// Delete a profile from disk
    pub fn delete_profile_file(path: &PathBuf) -> Result<(), String> {
        fs::remove_file(path)
            .map_err(|e| format!("Failed to delete profile file: {}", e))
    }

    /// List all profiles in the profiles directory
    pub fn list_profiles() -> Result<Vec<Profile>, String> {
        WindowsDirs::ensure_dirs()
            .map_err(|e| format!("Failed to create directories: {}", e))?;

        let profiles_dir = get_profiles_dir();

        let mut profiles = Vec::new();

        let entries = fs::read_dir(&profiles_dir)
            .map_err(|e| format!("Failed to read profiles directory: {}", e))?;

        for entry in entries {
            let entry = entry
                .map_err(|e| format!("Failed to read directory entry: {}", e))?;

            let path = entry.path();

            if path.is_file() && path.extension().map(|e| e == "yaml" || e == "yml").unwrap_or(false) {
                match load_profile(&path) {
                    Ok(profile) => profiles.push(profile),
                    Err(e) => log::warn!("Failed to load profile from {:?}: {}", path, e),
                }
            }
        }

        Ok(profiles)
    }

    /// Export a profile to a specific path
    pub fn export_profile(profile: &Profile, dest_path: &PathBuf) -> Result<(), String> {
        let content = profile.content.clone();

        fs::write(dest_path, content)
            .map_err(|e| format!("Failed to export profile: {}", e))
    }
}
