//! Diagnostic Logbook — append-only event log persisted to daily JSONL files.
//!
//! This is the Windows-port counterpart of the macOS `Sources/Riptide/Logbook/`
//! module. The shape is intentionally close to the Swift source so the B3
//! front-end (and any future cross-platform tooling) sees a consistent view.
//!
//! Surface:
//! - [`entry`] — `LogLevel` / `LogCategory` / `LogEntry` (the on-disk shape).
//! - [`paths`] — `LogbookPaths` (resolves the daily file under a base dir).
//! - [`writer`] — `LogbookWriter` (fire-and-forget, internal mpsc + batch flush).
//! - [`store`] — `LogbookStore` (read-side: query / clear / export).
//!
//! The writer is `Clone` and `Send + Sync` so it can be `Arc`'d into the five
//! injection points (mode coordinator, subscription scheduler, TUN service
//! control, system proxy guard, recovery watchdog) without holding the
//! caller's task open — the contract is "log a line, never block the caller".

pub mod entry;
pub mod paths;
pub mod store;
pub mod writer;

pub use entry::{LogCategory, LogEntry, LogLevel};
pub use paths::LogbookPaths;
pub use store::{LogbookQuery, LogbookStore};
pub use writer::LogbookWriter;
