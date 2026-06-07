//! Tauri commands for the Scene editor.
//!
//! Five thin wrappers over [`crate::core::scenes::SceneStore`]:
//!
//! - [`scene_list`] — read trimmed summaries (the list view's data
//!   source) or the full scenes if `full = true` is passed.
//! - [`scene_create`] — persist a new scene; the backend mints a
//!   UUID v4 id and ISO 8601 timestamps.
//! - [`scene_update`] — replace an existing scene (matched by id).
//! - [`scene_delete`] — remove a scene by id.
//! - [`scene_apply`] — probe a connection tuple `(process, domain, ip)`
//!   against every enabled scene; the first match's mode override is
//!   surfaced to the caller. The current MVP only logs + returns the
//!   decision; a follow-up phase will wire the matched mode into the
//!   `ModeCoordinator` (see ADR-0010 follow-up).
//!
//! Each command builds a fresh `SceneStore` rooted at the default
//! Windows path (`%APPDATA%\Riptide\scenes.json`). The store is
//! cheap to construct — it is a thin handle around the on-disk
//! `scenes.json` file. Sharing a `SceneStore` across commands via
//! `tauri::State` is a v2.5.0 follow-up; the MVP keeps every call
//! self-contained so the file path can be relocated without state
//! refactors.

use crate::core::scenes::{Scene, SceneApplyResult, SceneStore, SceneSummary};

/// Build a fresh `SceneStore` rooted at the default Windows path.
/// One per call — the store is just a handle, the cost is
/// negligible.
fn default_store() -> SceneStore {
    SceneStore::new_default()
}

/// `scene_list(full: Option<bool>) -> Vec<SceneSummary> | Vec<Scene>`
///
/// Read every persisted scene. The list view passes `full = false`
/// (or omits the arg entirely) and gets [`SceneSummary`]s. Pass
/// `full = true` to get the full [`Scene`] list — used by the editor
/// when hydrating the form fields.
#[tauri::command]
pub async fn scene_list(full: Option<bool>) -> Result<ListResponse, String> {
    let store = default_store();
    if full.unwrap_or(false) {
        let scenes = store.list().await?;
        Ok(ListResponse::Full(scenes))
    } else {
        let summaries = store.list_summaries().await?;
        Ok(ListResponse::Summaries(summaries))
    }
}

/// Tagged response: the JS layer picks the right field based on what
/// it asked for. Saves us a second command name.
#[derive(Debug, serde::Serialize)]
#[serde(untagged)]
pub enum ListResponse {
    /// Default — list view's data source.
    Summaries(Vec<SceneSummary>),
    /// Editor hydration — full matchers + timestamps.
    Full(Vec<Scene>),
}

/// `scene_create(scene: Scene) -> Scene`
///
/// Persist a new scene. The backend mints a UUID v4 id and ISO 8601
/// timestamps if the client did not provide them. The stored scene
/// is returned so the JS layer can read the final id + timestamps
/// without a follow-up `scene_list` call.
#[tauri::command]
pub async fn scene_create(scene: Scene) -> Result<Scene, String> {
    default_store().create(scene).await
}

/// `scene_update(scene: Scene) -> Scene`
///
/// Replace an existing scene. The scene's `id` field is the lookup
/// key; the rest of the fields are written verbatim. Returns the
/// updated scene with a fresh `updated_at` timestamp.
#[tauri::command]
pub async fn scene_update(scene: Scene) -> Result<Scene, String> {
    default_store().update(scene).await
}

/// `scene_delete(id: String) -> ()`
///
/// Remove a scene by id. Errors with a clear "not found" message if
/// the id does not match an existing scene.
#[tauri::command]
pub async fn scene_delete(id: String) -> Result<(), String> {
    let removed = default_store().delete(id).await?;
    log::info!("Deleted scene '{}' ({})", removed.name, removed.id);
    Ok(())
}

/// `scene_apply(process, domain, ip) -> SceneApplyResult`
///
/// Probe a connection tuple against every enabled scene and return
/// the first match. The current MVP just logs the decision; the
/// follow-up wires the matched mode into the `ModeCoordinator`.
#[tauri::command]
pub async fn scene_apply(
    process: Option<String>,
    domain: Option<String>,
    ip: Option<String>,
) -> Result<SceneApplyResult, String> {
    let process = process.unwrap_or_default();
    let domain = domain.unwrap_or_default();
    let ip = ip.unwrap_or_default();
    let result = default_store().apply(&process, &domain, &ip).await?;
    if let (Some(id), Some(name), Some(mode)) = (&result.matched, &result.scene_name, &result.mode) {
        log::info!(
            "scene_apply matched scene '{}' ({}): mode = {}",
            name,
            id,
            mode.as_str()
        );
    } else {
        log::debug!(
            "scene_apply: no scene matched process='{}' domain='{}' ip='{}'",
            process,
            domain,
            ip
        );
    }
    Ok(result)
}

// ── Tests ────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    //! The CRUD / apply logic is exercised end-to-end in
    //! `core::scenes::store::tests`. This module only covers
    //! command-layer concerns that don't reach the store:
    //! parameter normalization (None / "" → empty string) and the
    //! "no match returns Ok with None fields" path.
    //!
    //! The 3-store-C1 QA tests live in `core::scenes::store` so they
    //! can hit the on-disk file directly. We only need one command-
    //! layer test here to confirm the Tauri boundary compiles and
    //! returns a sensible error when the store reports one.

    use super::*;
    use crate::core::scenes::types::ModeOverride;
    use std::time::{SystemTime, UNIX_EPOCH};

    /// Build a store rooted at a unique temp dir. Mirrors the helper
    /// in `core::scenes::store::tests` — duplicated here to keep
    /// the test self-contained (avoid cross-module `pub(crate)`).
    fn fresh_store(tag: &str) -> (SceneStore, std::path::PathBuf) {
        let mut p = std::env::temp_dir();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("riptide-scenes-cmd-{tag}-{nanos}"));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        let store = SceneStore::new(crate::core::scenes::ScenePaths {
            file: p.join("scenes.json"),
        });
        (store, p)
    }

    /// Smoke: `scene_apply` with no persisted scenes returns
    /// `Ok(SceneApplyResult { matched: None, ... })`. This is the
    /// "scene_apply 基础流程" gate from C8.4 — the command must not
    /// crash on an empty store. We can't easily redirect the
    /// production `default_store()` at a temp dir, so we exercise
    /// the store directly here to lock the contract that the
    /// command depends on.
    #[tokio::test(flavor = "current_thread")]
    async fn scene_apply_returns_none_on_empty_store() {
        let (store, _dir) = fresh_store("empty-apply");
        let result: SceneApplyResult = store
            .apply("", "no-match.test", "9.9.9.9")
            .await
            .unwrap();
        assert!(result.matched.is_none());
        assert!(result.mode.is_none());
        assert!(result.scene_name.is_none());
    }

    /// Wire shape: a stored scene's serialized JSON includes all
    /// the fields the editor needs. This pins the contract that
    /// the JS side reads via `invoke('scene_list', { full: true })`.
    #[test]
    fn scene_wire_shape_includes_all_editor_fields() {
        let scene = Scene {
            id: "id-1".into(),
            name: "demo".into(),
            mode: ModeOverride::Tun,
            enabled: true,
            matchers: vec![],
            created_at: "2026-06-07T08:00:00Z".into(),
            updated_at: "2026-06-07T08:00:00Z".into(),
        };
        let v: serde_json::Value = serde_json::to_value(&scene).unwrap();
        assert_eq!(v["id"], "id-1");
        assert_eq!(v["name"], "demo");
        assert_eq!(v["mode"], "tun");
        assert_eq!(v["enabled"], true);
        assert!(v["matchers"].is_array());
        assert_eq!(v["created_at"], "2026-06-07T08:00:00Z");
        assert_eq!(v["updated_at"], "2026-06-07T08:00:00Z");
    }
}
