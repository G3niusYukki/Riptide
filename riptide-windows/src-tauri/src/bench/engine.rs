//! Engine resolver.
//!
//! The MVP recognizes two engine kinds:
//!
//! - [`EngineKind::Mihomo`] — the production engine on Windows.
//!   The binary lives at `<WindowsDirs::mihomo_dir()>/mihomo.exe`.
//!   Resolved via [`resolve_mihomo`].
//! - [`EngineKind::Swift`] / [`EngineKind::Singbox`] — not
//!   implemented on Windows. The resolver returns `None` for
//!   the binary path; the harness emits a `Skipped` dimension
//!   with reason "engine not implemented on this platform".
//!
//! The struct is intentionally zero-sized today: the harness
//! does not need any state to resolve the binary path. A future
//! iteration (when we wire throughput / idle-memory dimensions
//! that need to talk to the controller API) will grow fields
//! like `controller_url` and `controller_port`.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[cfg(target_os = "windows")]
use crate::utils::windows_dirs::WindowsDirs;

/// The engines the bench harness knows how to target.
///
/// Wire format is the snake_case variant name (`"mihomo"`,
/// `"singbox"`, `"swift"`) so the JS layer can pass the
/// `EngineKind` it already gets from `engine_current`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EngineKind {
    Mihomo,
    Singbox,
    Swift,
}

impl EngineKind {
    /// Wire string. Matches the `ProxyEngineKind` enum in
    /// `core::engines` so callers can pass the value through
    /// verbatim.
    pub const fn as_str(self) -> &'static str {
        match self {
            EngineKind::Mihomo => "mihomo",
            EngineKind::Singbox => "singbox",
            EngineKind::Swift => "swift",
        }
    }
}

impl std::str::FromStr for EngineKind {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "mihomo" => Ok(EngineKind::Mihomo),
            "singbox" => Ok(EngineKind::Singbox),
            "swift" => Ok(EngineKind::Swift),
            other => Err(format!("unknown engine: {other}")),
        }
    }
}

/// Resolve the binary path for the given engine, if it exists
/// on disk. Returns `None` when:
/// - the engine is not implemented on this platform, OR
/// - the binary file is not present at the expected location.
///
/// Callers (the harness) treat `None` as "the engine cannot be
/// measured right now; emit Skipped dimensions with the path
/// string in the reason". The path itself is the signal to the
/// user ("hey, mihomo isn't downloaded yet").
pub fn resolve_binary(kind: EngineKind) -> Option<PathBuf> {
    match kind {
        EngineKind::Mihomo => resolve_mihomo(),
        // Windows: singbox sidecar is not yet implemented (C5.x
        // follows in Phase C late). Swift is macOS-only (ADR-0007).
        // Both return None so the harness produces a clean
        // Skipped-dimensions report rather than a hard error.
        EngineKind::Singbox | EngineKind::Swift => None,
    }
}

#[cfg(target_os = "windows")]
fn resolve_mihomo() -> Option<PathBuf> {
    let path = WindowsDirs::mihomo_dir().join("mihomo.exe");
    if path.exists() {
        Some(path)
    } else {
        None
    }
}

/// Non-Windows stub: the macOS Swift side has its own
/// `mihomo.exe` resolution path. We never reach this from a
/// Windows build (gated by `#[cfg(target_os = "windows")]` in
/// the only caller, the bench harness), but we keep a
/// compilable no-op so `cargo check` succeeds on the Linux CI
/// host (see the platform-shim pattern in
/// `core::service_linux`).
#[cfg(not(target_os = "windows"))]
fn resolve_mihomo() -> Option<PathBuf> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_kind_wire_string_roundtrip() {
        for k in [EngineKind::Mihomo, EngineKind::Singbox, EngineKind::Swift] {
            let s = k.as_str();
            let parsed: EngineKind = s.parse().unwrap();
            assert_eq!(parsed, k);
            let json = serde_json::to_string(&k).unwrap();
            assert_eq!(json, format!("\"{s}\""));
        }
        assert!("nope".parse::<EngineKind>().is_err());
    }

    /// Swift and singbox always resolve to None — they are
    /// not implemented on Windows. The harness relies on this
    /// to surface "not implemented" cleanly.
    #[test]
    fn unimplemented_engines_resolve_to_none() {
        assert!(resolve_binary(EngineKind::Singbox).is_none());
        assert!(resolve_binary(EngineKind::Swift).is_none());
    }
}
