//! Errors surfaced by the SingBox sidecar integration.
//!
//! This enum follows the project's `thiserror`-based error pattern (see
//! [`crate::core::mihomo_api::MihomoError`] and
//! [`crate::core::windows_sysproxy::SysproxyError`]) so callers can
//! `?`-bubble a `SingBoxError` from a Tauri command with the same
//! `.map_err(|e| e.to_string())` boundary translation used everywhere else.
//!
//! v2.4.x scope: the full SingBox integration is a v2.5.0 deliverable. This
//! module ships the *skeleton* only — every method on
//! [`crate::core::singbox::runtime_manager::SingBoxRuntimeManager`] returns
//! [`SingBoxError::NotImplementedYet`] until the downloader is wired and the
//! v2.5.0 plan lands.

use std::path::PathBuf;

/// Error type for the SingBox sidecar module.
///
/// Variants grow alongside the v2.5.0 feature work. The current skeleton
/// only ever returns [`SingBoxError::NotImplementedYet`] from runtime calls;
/// path/downloader stubs use [`SingBoxError::PathNotFound`] and
/// [`SingBoxError::DownloadFailed`] once real implementation lands.
#[derive(Debug, thiserror::Error)]
pub enum SingBoxError {
    /// The method is intentionally a stub. v2.4.x does not ship a working
    /// SingBox runtime; this variant lets UI / Tauri commands fail with a
    /// clear message ("SingBox is not enabled in this build") rather than
    /// silently pretending to succeed.
    #[error("SingBox integration is not implemented yet (planned for v2.5.0)")]
    NotImplementedYet,

    /// The expected on-disk path for the SingBox binary did not resolve.
    /// `0` is the path we tried to use (formatted for display).
    #[error("SingBox path not found: {0}")]
    PathNotFound(String),

    /// A real download was attempted but failed. Carries the underlying
    /// cause as a `String` so the caller can surface it in the UI without
    /// a second `From` impl. The skeleton downloader never reaches this
    /// branch — it returns [`SingBoxError::NotImplementedYet`] instead.
    #[error("SingBox download failed: {0}")]
    DownloadFailed(String),
}

impl SingBoxError {
    /// Convenience for callers that want a string-friendly `PathBuf` arg.
    pub fn path_not_found(path: PathBuf) -> Self {
        SingBoxError::PathNotFound(path.to_string_lossy().into_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_implemented_message_is_stable() {
        // The v2.5.0 frontend may grep for this exact phrase; keep it stable.
        let msg = SingBoxError::NotImplementedYet.to_string();
        assert!(msg.contains("not implemented"));
        assert!(msg.contains("v2.5.0"));
    }

    #[test]
    fn path_not_found_includes_path() {
        let err = SingBoxError::path_not_found(PathBuf::from("C:/missing/sing-box.exe"));
        let msg = err.to_string();
        assert!(msg.contains("C:/missing/sing-box.exe"));
    }
}
