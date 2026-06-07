//! Windows-specific directory utilities using APPDATA

use std::env;
use std::path::PathBuf;

pub struct WindowsDirs;

impl WindowsDirs {
    /// Root config directory.
    /// Windows: %APPDATA%\Riptide\
    /// Linux:   $XDG_CONFIG_HOME/riptide/ or ~/.config/riptide/
    pub fn config_dir() -> PathBuf {
        #[cfg(target_os = "windows")]
        {
            env::var("APPDATA")
                .map(PathBuf::from)
                .unwrap_or_else(|_| {
                    env::var("USERPROFILE")
                        .map(|p| PathBuf::from(p).join("AppData").join("Roaming"))
                        .expect("Cannot determine config directory")
                })
                .join("Riptide")
        }
        #[cfg(not(target_os = "windows"))]
        {
            env::var("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|_| {
                    env::var("HOME")
                        .map(|p| PathBuf::from(p).join(".config"))
                        .expect("Cannot determine config directory")
                })
                .join("riptide")
        }
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
