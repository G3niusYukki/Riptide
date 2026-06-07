//! File-backed [`Scene`] store.
//!
//! Mirrors the macOS `LogbookStore` actor pattern: a single
//! `tokio::sync::Mutex<Vec<Scene>>` guards the in-memory list; every
//! public method takes the lock, hands off to `tokio::task::spawn_blocking`
//! for the file IO, and returns the result. The lock is held for
//! microseconds in practice — the body of each method does the actual
//! work inside `spawn_blocking`, so concurrent Tauri commands
//! serialize only on the lock acquisition, not on disk.
//!
//! Storage layout: a single `scenes.json` under `directory` (no
//! per-day splitting — scenes are CRUD, not append-only):
//!
//! ```json
//! { "scenes": [ { "id": "...", "name": "...", ... }, ... ] }
//! ```
//!
//! The dataset is small (tens of entries) so the full rewrite on
//! every mutation is cheaper than maintaining a partial-update index.

use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use tokio::sync::Mutex;

use super::matcher::scene_applies;
use super::types::{ModeOverride, Scene, SceneId, SceneSummary};

/// Result of `scene_apply` — the first matching scene wins, with its
/// mode override surfaced to the caller. `matched: None` means no
/// scene matched the probe.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SceneApplyResult {
    /// ID of the matched scene, or `None` if nothing applied.
    pub matched: Option<SceneId>,
    /// The mode the matched scene overrides to. `None` if no match.
    pub mode: Option<ModeOverride>,
    /// The matched scene's name, for logging / UI display.
    pub scene_name: Option<String>,
}

/// On-disk envelope wrapping the scene list. The wrapper is forward-
/// compatible: future versions can add top-level fields (e.g. a
/// default policy) without breaking older clients.
#[derive(Debug, Default, Serialize, Deserialize)]
struct SceneFile {
    #[serde(default)]
    scenes: Vec<Scene>,
}

impl SceneFile {
    fn empty() -> Self {
        Self { scenes: Vec::new() }
    }
}

/// Path resolver for the scenes file. Mirrors the `LogbookPaths` /
/// `WindowsDirs` pattern used by other persisted stores in this crate.
#[derive(Debug, Clone)]
pub struct ScenePaths {
    /// File path of `scenes.json`. Parent dir is created on demand.
    pub file: PathBuf,
}

impl ScenePaths {
    /// Mount on `<base>/scenes.json`. Used by tests + the service
    /// binary (`riptide-tun-service.exe`) that has no Tauri handle.
    pub fn resolve(base: &Path) -> Self {
        Self {
            file: base.join("scenes.json"),
        }
    }

    /// Canonical Windows location: `%APPDATA%\Riptide\scenes.json`.
    /// Linux hosts fall back to `$XDG_CONFIG_HOME/riptide/scenes.json`
    /// via `WindowsDirs::config_dir()`.
    pub fn default_windows() -> Self {
        let base = crate::utils::windows_dirs::WindowsDirs::config_dir();
        Self::resolve(&base)
    }
}

/// Scene store. Clone via `Arc<SceneStore>` — the internal `Mutex`
/// is the source of truth.
pub struct SceneStore {
    paths: ScenePaths,
    lock: Mutex<()>,
}

impl SceneStore {
    pub fn new(paths: ScenePaths) -> Self {
        Self {
            paths,
            lock: Mutex::new(()),
        }
    }

    /// Convenience constructor using the default Windows location.
    pub fn new_default() -> Self {
        Self::new(ScenePaths::default_windows())
    }

    /// Path resolver. Useful for tools that want to open the same
    /// file via `serde_json` directly.
    pub fn paths(&self) -> &ScenePaths {
        &self.paths
    }

    /// Read every scene. Returns the scenes in their on-disk order
    /// (insertion order — we never sort here).
    pub async fn list(&self) -> Result<Vec<Scene>, String> {
        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        let file = tokio::task::spawn_blocking(move || read_blocking(&paths))
            .await
            .map_err(|e| format!("Scene list task join failed: {e}"))??;
        Ok(file.scenes)
    }

    /// Read trimmed summaries for the list view. Cheaper than
    /// `list` if the caller only needs the per-row badges.
    pub async fn list_summaries(&self) -> Result<Vec<SceneSummary>, String> {
        let scenes = self.list().await?;
        Ok(scenes.iter().map(SceneSummary::from_scene).collect())
    }

    /// Create a scene. If `scene.id` is empty, the backend mints a
    /// UUID v4. Returns the stored scene (with timestamps filled in).
    pub async fn create(&self, mut scene: Scene) -> Result<Scene, String> {
        if scene.name.trim().is_empty() {
            return Err("Scene name cannot be empty".into());
        }
        if scene.id.is_empty() {
            scene.id = uuid_v4();
        }
        let now = Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
        scene.created_at = now.clone();
        scene.updated_at = now;

        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        let to_add = scene.clone();
        tokio::task::spawn_blocking(move || -> Result<Scene, String> {
            let mut file = read_blocking(&paths)?;
            if file.scenes.iter().any(|s| s.id == to_add.id) {
                return Err(format!("Scene with id '{}' already exists", to_add.id));
            }
            file.scenes.push(to_add.clone());
            write_blocking(&paths, &file)?;
            Ok(to_add)
        })
        .await
        .map_err(|e| format!("Scene create task join failed: {e}"))?
    }

    /// Update an existing scene (matched by `scene.id`). Returns the
    /// updated scene. Errors if the id is not found.
    pub async fn update(&self, scene: Scene) -> Result<Scene, String> {
        if scene.id.is_empty() {
            return Err("Cannot update a scene without an id".into());
        }
        if scene.name.trim().is_empty() {
            return Err("Scene name cannot be empty".into());
        }
        let now = Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
        let updated = Scene {
            updated_at: now,
            ..scene
        };
        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        let to_write = updated.clone();
        tokio::task::spawn_blocking(move || -> Result<Scene, String> {
            let mut file = read_blocking(&paths)?;
            let idx = file
                .scenes
                .iter()
                .position(|s| s.id == to_write.id)
                .ok_or_else(|| format!("Scene '{}' not found", to_write.id))?;
            file.scenes[idx] = to_write.clone();
            write_blocking(&paths, &file)?;
            Ok(to_write)
        })
        .await
        .map_err(|e| format!("Scene update task join failed: {e}"))?
    }

    /// Delete a scene by id. Returns the deleted scene (handy for
    /// `undo` on the UI side), or an error if the id is not found.
    pub async fn delete(&self, id: SceneId) -> Result<Scene, String> {
        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        tokio::task::spawn_blocking(move || -> Result<Scene, String> {
            let mut file = read_blocking(&paths)?;
            let idx = file
                .scenes
                .iter()
                .position(|s| s.id == id)
                .ok_or_else(|| format!("Scene '{}' not found", id))?;
            let removed = file.scenes.remove(idx);
            write_blocking(&paths, &file)?;
            Ok(removed)
        })
        .await
        .map_err(|e| format!("Scene delete task join failed: {e}"))?
    }

    /// Probe a connection tuple `(process, domain, ip)` against every
    /// enabled scene and return the first match. The result is a
    /// [`SceneApplyResult`] — the caller (typically the Tauri
    /// `scene_apply` command) decides what to do with the matched
    /// mode (today: log + return; later: drive the mode coordinator).
    pub async fn apply(
        &self,
        process: &str,
        domain: &str,
        ip: &str,
    ) -> Result<SceneApplyResult, String> {
        let scenes = self.list().await?;
        for scene in &scenes {
            if scene_applies(scene, process, domain, ip) {
                return Ok(SceneApplyResult {
                    matched: Some(scene.id.clone()),
                    mode: Some(scene.mode),
                    scene_name: Some(scene.name.clone()),
                });
            }
        }
        Ok(SceneApplyResult {
            matched: None,
            mode: None,
            scene_name: None,
        })
    }
}

// ── blocking IO helpers ─────────────────────────────────────────

fn read_blocking(paths: &ScenePaths) -> Result<SceneFile, String> {
    if !paths.file.exists() {
        return Ok(SceneFile::empty());
    }
    let raw = std::fs::read_to_string(&paths.file)
        .map_err(|e| format!("Failed to read {:?}: {}", paths.file, e))?;
    // Forward-compat: an empty / missing `scenes` key counts as empty.
    if raw.trim().is_empty() {
        return Ok(SceneFile::empty());
    }
    let file: SceneFile =
        serde_json::from_str(&raw).map_err(|e| format!("Failed to parse {:?}: {e}", paths.file))?;
    Ok(file)
}

fn write_blocking(paths: &ScenePaths, file: &SceneFile) -> Result<(), String> {
    if let Some(parent) = paths.file.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create {:?}: {}", parent, e))?;
        }
    }
    let json = serde_json::to_string_pretty(file)
        .map_err(|e| format!("Failed to serialize scenes: {e}"))?;
    // Atomic write: write to a temp sibling then rename. Avoids half-
    // written files on crash mid-flush.
    let tmp = paths.file.with_extension("json.tmp");
    std::fs::write(&tmp, json).map_err(|e| format!("Failed to write {:?}: {}", tmp, e))?;
    std::fs::rename(&tmp, &paths.file)
        .map_err(|e| format!("Failed to rename {:?} -> {:?}: {}", tmp, paths.file, e))?;
    Ok(())
}

/// Tiny UUID v4 generator. We avoid pulling the `uuid` crate in for
/// one call site — the format is `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
/// with `y` in {8,9,a,b}, all hex, per RFC 4122 §4.4. Quality is
/// "good enough for an in-app scene id"; do not use for security-
/// sensitive purposes.
fn uuid_v4() -> String {
    use std::time::SystemTime;
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    // Salt with a constant; wrapping_add keeps the input 128-bit wide
    // so two back-to-back `u128` values give us a 128-bit source.
    let r: u128 = nanos.wrapping_add(0x9E37_79B9_7F4A_7C15_3B14_5F7C_9A2E_4D81);
    let mut b = r.to_le_bytes();
    // Stamp version 4 (byte 6) and variant 10xx (byte 8).
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        b[0], b[1], b[2], b[3],
        b[4], b[5],
        b[6], b[7],
        b[8], b[9],
        b[10], b[11], b[12], b[13], b[14], b[15],
    )
}

// JSON helpers re-exported so the `tests` module can build a
// `SceneFile` envelope directly when hand-writing fixtures.
#[allow(dead_code)]
fn _envelope_marker(_: JsonValue) {}

#[cfg(test)]
mod tests {
    //! 3 tests cover the spec: (1) parse + list round-trip, (2)
    //! SceneStore CRUD end-to-end on a temp file, (3) `scene_apply`
    //! matches against the right scene and ignores disabled ones.

    use super::*;
    use crate::core::scenes::types::{Matcher, ModeOverride, Scene};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn fresh_dir(tag: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        p.push(format!("riptide-scenes-{tag}-{nanos}"));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    fn scene(name: &str, mode: ModeOverride, matchers: Vec<Matcher>) -> Scene {
        Scene {
            id: String::new(),
            name: name.into(),
            mode,
            enabled: true,
            matchers,
            created_at: String::new(),
            updated_at: String::new(),
        }
    }

    /// Test 1 — Scene 解析: hand-write a `scenes.json`, read it back
    /// via the store, and assert the wire shape survives the round
    /// trip. This pins the on-disk JSON contract that the frontend
    /// reads via `invoke('scene_list')`.
    #[tokio::test(flavor = "current_thread")]
    async fn parse_round_trip_preserves_wire_shape() {
        let dir = fresh_dir("parse");
        let file = dir.join("scenes.json");
        let raw = serde_json::json!({
            "scenes": [
                {
                    "id": "abc",
                    "name": "alpha",
                    "mode": "tun",
                    "enabled": true,
                    "matchers": [
                        { "kind": "process", "pattern": "chrome.exe" },
                        { "kind": "domain",  "pattern": "example.com" },
                        { "kind": "ipset",   "value": "10.0.0.0/8" }
                    ],
                    "created_at": "2026-06-07T00:00:00Z",
                    "updated_at": "2026-06-07T00:00:00Z"
                }
            ]
        });
        std::fs::write(&file, serde_json::to_string_pretty(&raw).unwrap()).unwrap();

        let store = SceneStore::new(ScenePaths { file: file.clone() });
        let scenes = store.list().await.unwrap();
        assert_eq!(scenes.len(), 1);
        let s = &scenes[0];
        assert_eq!(s.id, "abc");
        assert_eq!(s.name, "alpha");
        assert_eq!(s.mode, ModeOverride::Tun);
        assert!(s.enabled);
        assert_eq!(s.matchers.len(), 3);
        // Three different matcher kinds — this is the "renders 3
        // matcher kinds" C8.3 gate on the frontend side. We just
        // assert the discriminated union deserialized cleanly.
        assert!(matches!(s.matchers[0], Matcher::Process { .. }));
        assert!(matches!(s.matchers[1], Matcher::Domain { .. }));
        assert!(matches!(s.matchers[2], Matcher::IpSet { .. }));
    }

    /// Test 2 — SceneStore CRUD: create / list / update / delete
    /// against a temp file. The store must survive a re-read after
    /// every mutation, which is what `scene_list` does on the JS side.
    #[tokio::test(flavor = "current_thread")]
    async fn scene_store_crud_round_trip() {
        let dir = fresh_dir("crud");
        let store = SceneStore::new(ScenePaths {
            file: dir.join("scenes.json"),
        });

        // Create #1 + #2
        let s1 = store
            .create(scene(
                "alpha",
                ModeOverride::Tun,
                vec![Matcher::Process {
                    pattern: "chrome.exe".into(),
                }],
            ))
            .await
            .unwrap();
        let s2 = store
            .create(scene(
                "beta",
                ModeOverride::SystemProxy,
                vec![Matcher::Domain {
                    pattern: "example.com".into(),
                }],
            ))
            .await
            .unwrap();
        assert!(!s1.id.is_empty(), "create must mint a UUID v4");
        assert_ne!(s1.id, s2.id, "scenes get unique ids");
        assert!(!s1.created_at.is_empty());

        // List returns both
        let all = store.list().await.unwrap();
        assert_eq!(all.len(), 2);

        // Update #1: rename + flip mode
        let mut edited = s1.clone();
        edited.name = "alpha-renamed".into();
        edited.mode = ModeOverride::Direct;
        let after = store.update(edited.clone()).await.unwrap();
        assert_eq!(after.name, "alpha-renamed");
        assert_eq!(after.mode, ModeOverride::Direct);
        assert!(!after.updated_at.is_empty());

        // Re-list and confirm the rename + mode flip landed.
        let all = store.list().await.unwrap();
        assert_eq!(all.len(), 2);
        let alpha = all.iter().find(|s| s.id == s1.id).unwrap();
        assert_eq!(alpha.name, "alpha-renamed");
        assert_eq!(alpha.mode, ModeOverride::Direct);
        // created_at is preserved across update; updated_at moves.
        assert_eq!(alpha.created_at, s1.created_at);

        // Summaries list also works
        let summaries = store.list_summaries().await.unwrap();
        assert_eq!(summaries.len(), 2);
        assert!(summaries.iter().all(|s| s.matcher_count == 1));

        // Delete #2
        let removed = store.delete(s2.id.clone()).await.unwrap();
        assert_eq!(removed.id, s2.id);
        let all = store.list().await.unwrap();
        assert_eq!(all.len(), 1);
        assert_eq!(all[0].id, s1.id);

        // Delete missing id errors
        let err = store.delete("does-not-exist".into()).await.unwrap_err();
        assert!(err.contains("not found"), "got: {err}");
    }

    /// Test 3 — `scene_apply` probes a connection tuple and surfaces
    /// the first matching enabled scene. Disabled scenes are skipped.
    /// This is the "scene_apply 基础流程" gate from the C8.4 spec.
    #[tokio::test(flavor = "current_thread")]
    async fn scene_apply_returns_first_match_skips_disabled() {
        let dir = fresh_dir("apply");
        let store = SceneStore::new(ScenePaths {
            file: dir.join("scenes.json"),
        });

        // Scene A: domain "example.com" → direct
        store
            .create(scene(
                "A-domain",
                ModeOverride::Direct,
                vec![Matcher::Domain {
                    pattern: "example.com".into(),
                }],
            ))
            .await
            .unwrap();
        // Scene B: process "chrome.exe" → tun, but disabled
        let disabled = Scene {
            id: String::new(),
            name: "B-disabled".into(),
            mode: ModeOverride::Tun,
            enabled: false,
            matchers: vec![Matcher::Process {
                pattern: "chrome.exe".into(),
            }],
            created_at: String::new(),
            updated_at: String::new(),
        };
        store.create(disabled).await.unwrap();
        // Scene C: ipset "10.0.0.0/8" → system_proxy
        store
            .create(scene(
                "C-ipset",
                ModeOverride::SystemProxy,
                vec![Matcher::IpSet {
                    value: "10.0.0.0/8".into(),
                }],
            ))
            .await
            .unwrap();

        // 1) Domain match on "api.example.com" → A
        let r = store
            .apply("any.exe", "api.example.com", "9.9.9.9")
            .await
            .unwrap();
        assert_eq!(r.scene_name.as_deref(), Some("A-domain"));
        assert_eq!(r.mode, Some(ModeOverride::Direct));

        // 2) Process match would be on B but B is disabled → fall
        // through to C via the IP match on 10.0.0.5.
        let r = store
            .apply("chrome.exe", "no-match.test", "10.0.0.5")
            .await
            .unwrap();
        assert_eq!(r.scene_name.as_deref(), Some("C-ipset"));
        assert_eq!(r.mode, Some(ModeOverride::SystemProxy));

        // 3) No match anywhere → matched = None
        let r = store
            .apply("firefox.exe", "no-match.test", "9.9.9.9")
            .await
            .unwrap();
        assert!(r.matched.is_none());
        assert!(r.mode.is_none());
        assert!(r.scene_name.is_none());
    }
}
