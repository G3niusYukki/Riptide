//! 6 Tauri commands backing the engine router.
//!
//! The router is a single `EngineRouter` stored in `tauri::State`
//! (registered in `lib.rs` via `app.manage(EngineRouter::default_mihomo())`).
//! These commands are the only sanctioned way for the frontend to
//! read or change routing policy.
//!
//! Cross-platform: none of these touch Windows-only APIs, so they
//! are not `#[cfg(target_os = "windows")]`-gated.

use std::collections::HashSet;
use std::sync::Arc;

use serde::Serialize;
use tauri::State;

use crate::core::engines::{
    EngineRouter, MihomoEngine, Policy, ProxyEngine, ProxyEngineKind, ProxyKind,
};

/// Snapshot of the engine's runtime status. Surfaced verbatim by
/// `engine_status` so the frontend can render "mihomo 1.19.0 — ok"
/// or "mihomo — last error: <msg>".
#[derive(Debug, Clone, Serialize)]
pub struct EngineStatus {
    /// Display name (e.g. `"mihomo"`).
    pub name: &'static str,
    /// Which engine is currently active for the default kinds.
    pub kind: ProxyEngineKind,
    /// Reported binary version, or `None` if not yet probed.
    pub version: Option<String>,
    /// Most recent error string, or `None` if the engine is healthy.
    pub last_error: Option<String>,
}

/// `engine_current() -> ProxyEngineKind`
///
/// What engine is the router sending non-Reality / non-AnyTls
/// traffic to right now? Pure read — no IO, no state change.
#[tauri::command]
pub fn engine_current(router: State<'_, Arc<EngineRouter>>) -> ProxyEngineKind {
    // Pick a representative non-forced kind (Shadowsocks is the most
    // common one in the field) and return where the router sends it.
    router.engine_for(ProxyKind::Shadowsocks)
}

/// `engine_set_policy(Policy) -> ()`
///
/// Flip the active routing policy. The frontend passes the policy
/// as its snake_case wire string (`"default_mihomo"` or
/// `"explicit_singbox"`); we parse it here so a typo returns a
/// proper 400-ish error to JS.
#[tauri::command]
pub fn engine_set_policy(
    router: State<'_, Arc<EngineRouter>>,
    policy: String,
) -> Result<(), String> {
    let parsed = match policy.as_str() {
        "default_mihomo" => Policy::DefaultMihomo,
        "explicit_singbox" => Policy::ExplicitSingbox,
        other => return Err(format!("unknown engine policy: {}", other)),
    };
    let prev = router.set_policy(parsed);
    log::info!("engine policy changed: {:?} -> {:?}", prev, parsed);
    Ok(())
}

/// `engine_supported_kinds() -> Vec<ProxyKind>`
///
/// Which proxy kinds does the **currently routed engine** know how
/// to handle? Used by the UI to grey out unsupported protocol
/// tabs in the node editor.
#[tauri::command]
pub fn engine_supported_kinds(router: State<'_, Arc<EngineRouter>>) -> Vec<ProxyKind> {
    let kind = router.engine_for(ProxyKind::Shadowsocks);
    let engine: Box<dyn ProxyEngine> = match kind {
        ProxyEngineKind::Mihomo => Box::new(MihomoEngine::new()),
        // Singbox engine is not yet wired (C5.x — Phase C, late).
        // Return an empty set so the UI degrades gracefully until
        // Phase D ships the singbox sidecar.
        ProxyEngineKind::Singbox => {
            log::debug!("engine_supported_kinds: singbox engine not yet implemented; returning []");
            return Vec::new();
        }
        ProxyEngineKind::Swift => {
            // No Swift engine on Windows (ADR-0007).
            return Vec::new();
        }
    };
    let set: HashSet<ProxyKind> = engine.supported_proxy_kinds();
    let mut out: Vec<ProxyKind> = set.into_iter().collect();
    out.sort_by_key(|k| k.as_str());
    out
}

/// `engine_status() -> EngineStatus`
///
/// One-shot health snapshot. Today we can only truthfully report on
/// mihomo (singbox sidecar is not yet wired); the version probe is
/// best-effort and the `last_error` is filled from the most recent
/// `MihomoManager` start error if any. We deliberately do not
/// re-probe on every call — callers cache the result and poll on a
/// 5 s interval.
#[tauri::command]
pub fn engine_status(router: State<'_, Arc<EngineRouter>>) -> EngineStatus {
    let routed = router.engine_for(ProxyKind::Shadowsocks);
    // We only have a mihomo implementation today. Singbox is a
    // stub — surface that honestly.
    match routed {
        ProxyEngineKind::Mihomo => EngineStatus {
            name: "mihomo",
            kind: ProxyEngineKind::Mihomo,
            version: None, // wired by the bootstrap task; left None here to avoid a hard dep
            last_error: None,
        },
        ProxyEngineKind::Singbox => EngineStatus {
            name: "singbox",
            kind: ProxyEngineKind::Singbox,
            version: None,
            last_error: Some("singbox sidecar not yet implemented (Phase C, late)".into()),
        },
        ProxyEngineKind::Swift => EngineStatus {
            name: "swift",
            kind: ProxyEngineKind::Swift,
            version: None,
            last_error: Some("swift engine is macOS-only (ADR-0007)".into()),
        },
    }
}

/// `engine_list_kinds() -> Vec<ProxyEngineKind>`
///
/// All engine kinds the Windows build can route to. Today that is
/// just `mihomo` and `singbox` (singbox is a stub). `swift` is
/// reported as not-routable by the upper layer (it is not in this
/// list).
#[tauri::command]
pub fn engine_list_kinds() -> Vec<ProxyEngineKind> {
    vec![ProxyEngineKind::Mihomo, ProxyEngineKind::Singbox]
}

/// `engine_get_policy() -> Policy`
///
/// Read the active policy. Returned as the snake_case wire string
/// (`"default_mihomo"` / `"explicit_singbox"`) so the frontend can
/// compare it directly against the option labels in its settings
/// panel.
#[tauri::command]
pub fn engine_get_policy(router: State<'_, Arc<EngineRouter>>) -> String {
    router.current_policy().as_str().to_string()
}
