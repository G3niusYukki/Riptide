//! On-disk locations for the SingBox sidecar.
//!
//! Mirrors the layout of `crate::core::mihomo_bootstrap` and
//! `crate::core::logbook::paths`:
//!
//! ```text
//! <base>/singbox/
//!   sing-box.exe             # the binary itself
//! ```
//!
//! The full SingBox integration is a v2.5.0 deliverable; the v2.4.x skeleton
//! only needs the *path* so the downloader can decide whether to bail with
//! [`crate::core::singbox::error::SingBoxError::NotImplementedYet`] or hand
//! the existing binary back to the caller.

use std::path::{Path, PathBuf};

/// Resolves on-disk locations for the SingBox binary.
#[derive(Debug, Clone, Default)]
pub struct SingBoxPaths {
    /// Directory that holds the `sing-box.exe` executable. Always `<base>/singbox`.
    pub directory: PathBuf,
    /// Convenience: the resolved path to `sing-box.exe`. Always
    /// `<base>/singbox/sing-box.exe`.
    pub binary: PathBuf,
}

impl SingBoxPaths {
    /// Build paths rooted at `<base>/singbox`. Used by tests and by the
    /// service binary (`riptide-tun-service.exe`), which can't depend on
    /// the Tauri app handle.
    pub fn resolve(base: &Path) -> Self {
        let directory = base.join("singbox");
        let binary = directory.join("sing-box.exe");
        Self { directory, binary }
    }

    /// The canonical location: `%APPDATA%\Riptide\singbox\sing-box.exe` on
    /// Windows. On non-Windows hosts (e.g. CI on Linux) the binary path
    /// still resolves under `WindowsDirs::config_dir()` so the local dev
    /// loop works the same as a Windows install — the file won't exist
    /// there, but the path is consistent.
    pub fn default_windows() -> Self {
        let base = crate::utils::windows_dirs::WindowsDirs::config_dir();
        Self::resolve(&base)
    }

    /// Create the `singbox/` directory (and any missing parents) if it does
    /// not exist. Safe to call repeatedly. Returns `std::io::Result` so the
    /// caller can decide whether a missing-data-dir is a fatal startup
    /// error or just a "no binary yet" hint.
    pub fn create_dir_if_needed(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.directory)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::utils::windows_dirs::WindowsDirs;

    #[test]
    fn resolve_appends_singbox_subdir() {
        let base = PathBuf::from("/tmp/riptide-test");
        let paths = SingBoxPaths::resolve(&base);
        assert_eq!(paths.directory, base.join("singbox"));
        assert_eq!(paths.binary, base.join("singbox").join("sing-box.exe"));
    }

    #[test]
    fn default_windows_uses_windows_dirs() {
        let paths = SingBoxPaths::default_windows();
        let config_dir = WindowsDirs::config_dir();
        assert!(
            paths.directory.starts_with(&config_dir),
            "default_windows path {:?} must start with WindowsDirs::config_dir() {:?}",
            paths.directory,
            config_dir
        );
        assert_eq!(
            paths.directory.file_name().and_then(|s| s.to_str()),
            Some("singbox")
        );
    }
}
