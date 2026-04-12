//! Windows-specific directory utilities using APPDATA

use std::path::PathBuf;
use std::env;

pub struct WindowsDirs;

impl WindowsDirs {
    /// %APPDATA%\Riptide\ (C:\Users\<user>\AppData\Roaming\Riptide)
    pub fn config_dir() -> PathBuf {
        env::var("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                env::var("USERPROFILE")
                    .map(|p| PathBuf::from(p).join("AppData").join("Roaming"))
                    .expect("Cannot determine config directory")
            })
            .join("Riptide")
    }

    pub fn profiles_dir() -> PathBuf {
        Self::config_dir().join("profiles")
    }

    pub fn mihomo_dir() -> PathBuf {
        Self::config_dir().join("mihomo")
    }

    pub fn logs_dir() -> PathBuf {
        Self::config_dir().join("logs")
    }

    /// Ensure directories exist
    pub fn ensure_dirs() -> std::io::Result<()> {
        std::fs::create_dir_all(Self::profiles_dir())?;
        std::fs::create_dir_all(Self::mihomo_dir())?;
        std::fs::create_dir_all(Self::logs_dir())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_dir_contains_riptide() {
        let config_dir = WindowsDirs::config_dir();
        let path_str = config_dir.to_string_lossy();
        assert!(path_str.contains("Riptide"));
    }

    #[test]
    fn test_profiles_dir_is_subdir_of_config() {
        let config_dir = WindowsDirs::config_dir();
        let profiles_dir = WindowsDirs::profiles_dir();
        assert!(profiles_dir.starts_with(&config_dir));
        assert!(profiles_dir.to_string_lossy().contains("profiles"));
    }
}
