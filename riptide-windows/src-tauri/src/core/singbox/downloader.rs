//! SingBox binary downloader — v2.4.x skeleton only.
//!
//! The full downloader (URL + SHA-256 pin, chunked download, signature
//! verification, atomic install) is a v2.5.0 deliverable alongside the
//! SingBox runtime. For v2.4.x this module exposes the *shape* callers will
//! need so the surrounding wiring can be exercised without a real network
//! round-trip:
//!
//! - [`SingBoxDownloader::ensure_present`] — probe the expected on-disk
//!   location, return [`SingBoxError::NotImplementedYet`] if missing
//!   (so the user sees a clear "SingBox is not enabled in this build"
//!   message instead of a confusing 404 / panic), or hand back the
//!   existing `PathBuf` if it's there.
//! - [`SingBoxDownloader::expected_path`] — a cheap accessor that does
//!   not touch the filesystem, useful for UI status surfaces.
//!
//! Real network calls, SHA-256 pins, and a `SINGBOX_VERSION` constant will
//! land in v2.5.0 alongside the rest of the integration.

use std::path::{Path, PathBuf};

use crate::core::singbox::error::SingBoxError;
use crate::core::singbox::paths::SingBoxPaths;

/// Stub downloader for the SingBox sidecar binary.
///
/// The struct is intentionally cheap to construct — the v2.5.0
/// implementation will likely add an `AppHandle` and a download-progress
/// emitter, but neither is needed for the skeleton.
#[derive(Debug, Default, Clone)]
pub struct SingBoxDownloader {
    /// Resolved on-disk locations. Populated eagerly on `new` so callers
    /// can ask for `expected_path()` without doing any I/O.
    paths: SingBoxPaths,
}

impl SingBoxDownloader {
    /// Build a downloader rooted at the canonical Windows path
    /// (`%APPDATA%\Riptide\singbox\sing-box.exe`).
    pub fn new() -> Self {
        Self {
            paths: SingBoxPaths::default_windows(),
        }
    }

    /// Build a downloader rooted at an explicit base directory. The
    /// `sing-box.exe` file is expected at `<base>/singbox/sing-box.exe`.
    /// Used by tests and by the `riptide-tun-service.exe` binary which
    /// doesn't carry a Tauri app handle.
    pub fn with_base(base: &Path) -> Self {
        Self {
            paths: SingBoxPaths::resolve(base),
        }
    }

    /// The path this downloader will look for (and, in v2.5.0, install to).
    pub fn expected_path(&self) -> &Path {
        &self.paths.binary
    }

    /// Make sure the SingBox binary is present on disk, returning the path
    /// to it on success.
    ///
    /// v2.4.x behaviour:
    ///
    /// 1. If the binary is present at the expected location, return
    ///    `Ok(path)` — the rest of the v2.5.0 work assumes a future
    ///    `SingBoxRuntimeManager` can call this and get a usable path.
    /// 2. If it is *missing*, return
    ///    [`SingBoxError::NotImplementedYet`]. v2.4.x does not actually
    ///    download the binary yet (deliberate — see C5 deliverable notes),
    ///    so we fail loudly with a message the UI can show verbatim.
    ///
    /// v2.5.0 will swap the missing-branch for a real download call.
    pub async fn ensure_present(&self) -> Result<PathBuf, SingBoxError> {
        if self.paths.binary.exists() {
            Ok(self.paths.binary.clone())
        } else {
            Err(SingBoxError::NotImplementedYet)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    /// Task spec test 1: missing binary -> NotImplementedYet.
    #[tokio::test]
    async fn downloader_returns_not_implemented_when_missing() {
        // Use a fresh per-test tempdir so we don't collide with the
        // user's real %APPDATA%\Riptide\singbox in case it happens to
        // exist (it shouldn't on a dev box, but be defensive).
        let tmp = std::env::temp_dir().join(format!(
            "riptide-singbox-test-{}",
            uuid::Uuid::new_v4()
        ));
        let downloader = SingBoxDownloader::with_base(&tmp);
        let result = downloader.ensure_present().await;
        assert!(
            matches!(result, Err(SingBoxError::NotImplementedYet)),
            "missing binary should return NotImplementedYet, got {result:?}"
        );
        let _ = fs::remove_dir_all(&tmp);
    }

    /// Task spec test 2: pre-staged stub file -> returned path.
    #[tokio::test]
    async fn downloader_returns_path_when_present() {
        let tmp = std::env::temp_dir().join(format!(
            "riptide-singbox-test-{}",
            uuid::Uuid::new_v4()
        ));
        let paths = SingBoxPaths::resolve(&tmp);
        // The downloader doesn't auto-create the directory, so mirror the
        // pre-install layout: create the singbox/ dir, drop a stub exe.
        fs::create_dir_all(&paths.directory).expect("create singbox dir");
        fs::write(&paths.binary, b"fake-sing-box-binary").expect("write stub");

        let downloader = SingBoxDownloader::with_base(&tmp);
        let result = downloader.ensure_present().await;
        assert!(
            result.is_ok(),
            "pre-staged binary should be returned, got {result:?}"
        );
        let got = result.unwrap();
        assert_eq!(got, paths.binary);
        assert!(got.exists());

        let _ = fs::remove_dir_all(&tmp);
    }
}
