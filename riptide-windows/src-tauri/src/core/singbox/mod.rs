//! SingBox sidecar integration — v2.4.x skeleton.
//!
//! The full SingBox runtime (binary download, config generation, process
//! supervision, TUN-mode routing, watcher tasks) is a v2.5.0 deliverable
//! — see `docs/WINDOWS-CATCHUP-PLAN.md` Phase C / D. For v2.4.x this
//! module ships only the **shape** of the integration so the rest of the
//! app can be designed against stable types:
//!
//! - [`paths::SingBoxPaths`] — on-disk locations under
//!   `%APPDATA%\Riptide\singbox\`. Mirrors `logbook::LogbookPaths`.
//! - [`downloader::SingBoxDownloader`] — stub downloader. v2.4.x
//!   returns `NotImplementedYet` for missing binaries so the UI can show
//!   a clear "SingBox is not enabled in this build" message; v2.5.0 will
//!   do a real download.
//! - [`runtime_manager::SingBoxRuntimeManager`] — skeleton process
//!   manager, also a no-op stub. v2.5.0 will mirror `MihomoManager`'s
//!   `start` / `stop` / `is_running` / config-generation surface.
//! - [`error::SingBoxError`] — the `thiserror`-based error enum used by
//!   the rest of the module.
//! - [`runtime_manager::SingBoxStatus`] — the small `Serialize` snapshot
//!   the UI displays ("not installed / not running" in v2.4.x).
//!
//! No real `Child` process, no SHA-256 pin, no `SINGBOX_VERSION` — those
//! land with the v2.5.0 work.

pub mod downloader;
pub mod error;
pub mod paths;
pub mod runtime_manager;

pub use downloader::SingBoxDownloader;
pub use error::SingBoxError;
pub use paths::SingBoxPaths;
pub use runtime_manager::{SingBoxRuntimeManager, SingBoxStatus};
