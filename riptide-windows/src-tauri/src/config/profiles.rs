//! Profile management

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::config::profile_meta::ProfileMetadata;

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
    /// Sidecar metadata: subscription URL, traffic, expiry. Loaded from disk on `list_profiles`.
    #[serde(default)]
    pub metadata: ProfileMetadata,
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
            metadata: ProfileMetadata::default(),
        }
    }

    /// Create a new profile with a specific file path
    pub fn new_with_path(name: String, content: String, path: PathBuf) -> Self {
        let mut profile = Self::new(name, content);
        profile.path = Some(path);
        profile
    }

    /// Parse YAML content to verify validity.
    /// Returns Ok(()) if the YAML is valid Clash config, Err with details if not.
    pub fn validate(&self) -> Result<(), String> {
        crate::config::parser::parse_clash_config(&self.content)
            .map(|_| ())
            .map_err(|e| format!("Invalid YAML config: {}", e))
    }

    /// Get proxies from profile by parsing YAML and extracting proxy nodes.
    pub fn get_proxies(&self) -> Vec<Proxy> {
        match crate::config::parser::parse_clash_config(&self.content) {
            Ok(config) => {
                config.proxies.unwrap_or_default().into_iter().map(|p| Proxy {
                    name: p.name,
                    server: p.server.unwrap_or_default(),
                    port: p.port.unwrap_or(0),
                    proxy_type: p.proxy_type.unwrap_or_else(|| "unknown".to_string()),
                }).collect()
            }
            Err(_) => Vec::new(),
        }
    }

    /// Get proxy groups from profile by parsing YAML and extracting groups.
    pub fn get_proxy_groups(&self) -> Vec<ProxyGroup> {
        match crate::config::parser::parse_clash_config(&self.content) {
            Ok(config) => {
                config.proxy_groups.unwrap_or_default().into_iter().map(|g| ProxyGroup {
                    name: g.name.unwrap_or_default(),
                    group_type: g.group_type.unwrap_or_else(|| "select".to_string()),
                    proxies: g.proxies.unwrap_or_default(),
                    url: g.url,
                    interval: g.interval,
                }).collect()
            }
            Err(_) => Vec::new(),
        }
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

    /// Generate a stable filename embedding the profile UUID so the ID survives reloads.
    /// Format: `<sanitized_name>__<uuid_simple>.yaml`
    pub fn generate_profile_filename(name: &str, id: &str) -> String {
        let sanitized: String = name
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect();
        let id_simple = id.replace('-', "");
        // Double underscore separator avoids collisions with user-provided underscores in names.
        format!("{}__{}.yaml", sanitized, id_simple)
    }

    /// Parse the embedded profile UUID out of a filename produced by `generate_profile_filename`.
    fn parse_id_from_filename(stem: &str) -> Option<String> {
        let (_, tail) = stem.rsplit_once("__")?;
        if tail.len() != 32 || !tail.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        // Re-hyphenate into canonical UUID form.
        Some(format!(
            "{}-{}-{}-{}-{}",
            &tail[0..8], &tail[8..12], &tail[12..16], &tail[16..20], &tail[20..32]
        ))
    }

    /// Save a profile to disk. The filename embeds `profile.id` so IDs survive reloads.
    pub fn save_profile(profile: &mut Profile) -> Result<(), String> {
        WindowsDirs::ensure_dirs()
            .map_err(|e| format!("Failed to create directories: {}", e))?;

        if profile.path.is_none() {
            let filename = generate_profile_filename(&profile.name, &profile.id);
            let path = get_profiles_dir().join(&filename);
            profile.path = Some(path);
        }

        let path = profile.path.as_ref().unwrap();
        fs::write(path, &profile.content)
            .map_err(|e| format!("Failed to write profile file: {}", e))?;

        profile.updated_at = Utc::now();
        Ok(())
    }

    /// Load a profile from disk. Recovers the stable ID from the filename.
    pub fn load_profile(path: &PathBuf) -> Result<Profile, String> {
        let content = fs::read_to_string(path)
            .map_err(|e| format!("Failed to read profile file: {}", e))?;

        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown");

        let (name, id) = match parse_id_from_filename(stem) {
            Some(id) => {
                let display_name = stem.rsplit_once("__").map(|(n, _)| n).unwrap_or(stem);
                (display_name.to_string(), id)
            }
            // Legacy file (or hand-placed): fabricate an ID. Caller will re-save to migrate.
            None => (stem.to_string(), uuid::Uuid::new_v4().to_string()),
        };

        let metadata = fs::metadata(path)
            .map_err(|e| format!("Failed to read file metadata: {}", e))?;

        let created_at = metadata
            .created()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .and_then(|d| DateTime::from_timestamp(d.as_secs() as i64, 0))
            .unwrap_or_else(Utc::now);

        let updated_at = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .and_then(|d| DateTime::from_timestamp(d.as_secs() as i64, 0))
            .unwrap_or_else(Utc::now);

        Ok(Profile {
            id,
            name,
            content,
            created_at,
            updated_at,
            path: Some(path.clone()),
            is_active: false,
            node_count: None,
            metadata: crate::config::profile_meta::load(path),
        })
    }

    /// Update a profile's content and persist. Updates `node_count` from parsed config.
    pub fn update_profile_content(profile: &mut Profile, new_content: String) -> Result<(), String> {
        let path = profile
            .path
            .clone()
            .ok_or_else(|| "Profile has no on-disk path".to_string())?;

        fs::write(&path, &new_content)
            .map_err(|e| format!("Failed to write profile file: {}", e))?;

        profile.content = new_content;
        profile.updated_at = Utc::now();
        Ok(())
    }

    /// Delete a profile from disk
    pub fn delete_profile_file(path: &PathBuf) -> Result<(), String> {
        // Best-effort: clean up the sidecar so we don't leave orphan metadata.
        crate::config::profile_meta::delete(path);
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

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn filename_round_trips_profile_id() {
            let id = "a1b2c3d4-e5f6-7890-1234-567890abcdef";
            let filename = generate_profile_filename("My Cool Profile", id);
            assert!(filename.ends_with(".yaml"));
            let stem = filename.trim_end_matches(".yaml");
            assert_eq!(parse_id_from_filename(stem), Some(id.to_string()));
        }

        #[test]
        fn legacy_filename_without_uuid_returns_none() {
            assert!(parse_id_from_filename("just_a_name").is_none());
            assert!(parse_id_from_filename("name__notarealuuid").is_none());
        }

        #[test]
        fn sanitizes_special_chars_in_name() {
            let id = "00000000-0000-0000-0000-000000000000";
            let filename = generate_profile_filename("a/b\\c:d?e*f", id);
            assert!(!filename.contains('/'));
            assert!(!filename.contains('\\'));
            assert!(!filename.contains(':'));
        }
    }
}
