//! Scene editor — process / domain / IP-set rules with mode overrides.
//!
//! This is the Windows-port counterpart of the macOS `SceneEditorView`.
//! Each [`Scene`] binds a set of matchers (process names, domain
//! suffixes, IP-CIDR sets) to a [`ModeOverride`] (which proxy mode the
//! connection should use when any matcher fires).
//!
//! Files live at `%APPDATA%\Riptide\scenes.json` as a single JSON
//! document holding `{ "scenes": [ ... ] }` — flat, no directory tree.
//!
//! Public surface:
//! - [`types`] — `Scene`, `Matcher`, `ModeOverride`, `SceneId` (the
//!   on-disk wire shape).
//! - [`matcher`] — `Matcher::matches` / `Scene::applies_to` (the pure
//!   matching logic; no IO).
//! - [`store`] — `SceneStore` (file-backed CRUD, tokio actor mirroring
//!   `LogbookStore`).
//!
//! Scenes are read on demand by [`SceneStore::list`]; the file is
//! re-written in full on every mutation. The dataset is small (tens
//! of entries, not thousands) so the full rewrite is cheaper than
//! maintaining an index.

pub mod matcher;
pub mod store;
pub mod types;

pub use matcher::{match_ipset, match_process_pattern};
pub use store::{SceneApplyResult, ScenePaths, SceneStore};
pub use types::{ModeOverride, Matcher, Scene, SceneId, SceneSummary};
