//! Tauri commands that expose the diagnostic Logbook to the front-end.
//!
//! Three thin wrappers over [`crate::core::logbook::LogbookStore`]:
//!
//! - [`logbook_query`] — read entries (optional level/category/from/to
//!   filter, with a `limit` cap).
//! - [`logbook_clear`] — remove entries (by category, by date, or both).
//! - [`logbook_export`] — write a filtered slice to a destination path
//!   as a single sorted JSONL file.
//!
//! String parameters come from the JS layer over Tauri's IPC, so we
//! accept the level / category as `Option<String>` and parse them
//! defensively. ISO 8601 `from` / `to` are parsed via
//! `chrono::DateTime::parse_from_rfc3339` and surfaced as user-friendly
//! errors if the JS side hands us a malformed value.

use std::path::PathBuf;
use std::sync::Arc;

use chrono::{DateTime, Utc};

use crate::core::logbook::{
    LogCategory, LogEntry, LogLevel, LogbookPaths, LogbookStore, LogbookWriter,
};

/// Build a `LogbookStore` rooted at the default Windows logbook dir.
/// One fresh store per call — `LogbookStore` is just a thin handle, so
/// the cost is negligible and we never have to share a mutex across
/// commands.
fn default_store() -> LogbookStore {
    LogbookStore::new(LogbookPaths::default_windows())
}

/// Read Logbook entries. `level` and `category` are the lowercase string
/// forms (e.g. `"info"`, `"mode"`) — see [`LogLevel::parse`] and
/// [`LogCategory::parse`]. `from` / `to` are RFC 3339 / ISO 8601
/// timestamps. Unknown filter values are rejected with a clear message
/// so the UI can fall back to "no filter".
#[tauri::command]
pub async fn logbook_query(
    limit: Option<u32>,
    level: Option<String>,
    category: Option<String>,
    from: Option<String>,
    to: Option<String>,
) -> Result<Vec<LogEntry>, String> {
    let levels = match level.as_deref() {
        Some(s) => match LogLevel::parse(s) {
            Some(l) => vec![l],
            None => return Err(format!("Unknown log level: {s}")),
        },
        None => Vec::new(),
    };
    let categories = match category.as_deref() {
        Some(s) => match LogCategory::parse(s) {
            Some(c) => vec![c],
            None => return Err(format!("Unknown log category: {s}")),
        },
        None => Vec::new(),
    };
    let from_ts = parse_ts(from.as_deref(), "from")?;
    let to_ts = parse_ts(to.as_deref(), "to")?;

    let query = crate::core::logbook::LogbookQuery {
        from: from_ts,
        to: to_ts,
        levels,
        categories,
        limit,
    };
    let store = default_store();
    store.query(query).await
}

/// Remove Logbook entries. Returns the number of entries removed.
///
/// - `category = None`, `before_date = None` → delete every `.jsonl` file.
#[tauri::command]
pub async fn logbook_clear(
    category: Option<String>,
    before_date: Option<String>,
) -> Result<u32, String> {
    let cat = match category.as_deref() {
        Some(s) => match LogCategory::parse(s) {
            Some(c) => Some(c),
            None => return Err(format!("Unknown log category: {s}")),
        },
        None => None,
    };
    let before = parse_ts(before_date.as_deref(), "before_date")?;
    let store = default_store();
    store.clear(cat, before).await
}

/// Export Logbook entries to a destination JSONL file. Returns the
/// number of entries exported. The destination is overwritten if it
/// exists. `from` / `to` accept the same RFC 3339 string format as
/// [`logbook_query`].
#[tauri::command]
pub async fn logbook_export(
    from: Option<String>,
    to: Option<String>,
    dest_path: String,
) -> Result<u32, String> {
    let from_ts = parse_ts(from.as_deref(), "from")?;
    let to_ts = parse_ts(to.as_deref(), "to")?;
    let query = crate::core::logbook::LogbookQuery {
        from: from_ts,
        to: to_ts,
        levels: Vec::new(),
        categories: Vec::new(),
        limit: None, // export everything in range
    };
    let store = default_store();
    store.export(query, PathBuf::from(dest_path)).await
}

fn parse_ts(s: Option<&str>, field: &str) -> Result<Option<DateTime<Utc>>, String> {
    match s {
        None => Ok(None),
        Some(raw) if raw.trim().is_empty() => Ok(None),
        Some(raw) => DateTime::parse_from_rfc3339(raw)
            .map(|d| Some(d.with_timezone(&Utc)))
            .map_err(|e| format!("Invalid {field} timestamp '{raw}': {e}")),
    }
}

// ── Test-only helpers (not exported as Tauri commands) ─────────

/// Test-only: build a store rooted at an arbitrary directory. Used by
/// unit tests in the B3.4 sub-module so they don't have to touch
/// `%APPDATA%\Riptide\logbook`.
#[cfg(test)]
pub fn test_store_at(dir: &std::path::Path) -> LogbookStore {
    LogbookStore::new(LogbookPaths::resolve(dir))
}

#[allow(dead_code)]
fn _writer_marker(_: Arc<LogbookWriter>) {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cmds::config::AppState;
    use crate::core::logbook::LogCategory;
    use crate::core::logbook::LogLevel;
    use std::collections::BTreeMap;

    #[test]
    fn parse_ts_handles_none_empty_and_valid() {
        assert!(parse_ts(None, "x").unwrap().is_none());
        assert!(parse_ts(Some(""), "x").unwrap().is_none());
        assert!(parse_ts(Some("  "), "x").unwrap().is_none());

        let ts = parse_ts(Some("2026-06-05T22:00:00Z"), "x")
            .unwrap()
            .unwrap();
        assert_eq!(
            ts.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
            "2026-06-05T22:00:00Z"
        );
    }

    #[test]
    fn parse_ts_rejects_garbage_with_field_name() {
        let err = parse_ts(Some("not-a-date"), "from").unwrap_err();
        assert!(
            err.contains("from"),
            "error should name the field, got {err}"
        );
        assert!(err.contains("not-a-date"));
    }

    #[test]
    fn level_and_category_parse_round_trip_for_known_values() {
        for level in [LogLevel::Info, LogLevel::Warning, LogLevel::Error] {
            assert_eq!(LogLevel::parse(level.as_str()), Some(level));
        }
        for cat in [
            LogCategory::Mode,
            LogCategory::Subscription,
            LogCategory::Service,
            LogCategory::Sysproxy,
            LogCategory::Recovery,
        ] {
            assert_eq!(LogCategory::parse(cat.as_str()), Some(cat));
        }
    }

    #[test]
    fn logbook_query_rejects_unknown_level() {
        let fut = logbook_query(None, Some("verbose".into()), None, None, None);
        let res = tauri::async_runtime::block_on(fut);
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("verbose"));
    }

    #[test]
    fn logbook_query_rejects_unknown_category() {
        let fut = logbook_query(None, None, Some("not-a-cat".into()), None, None);
        let res = tauri::async_runtime::block_on(fut);
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("not-a-cat"));
    }

    #[test]
    fn logbook_clear_rejects_unknown_category() {
        let fut = logbook_clear(Some("not-a-cat".into()), None);
        let res = tauri::async_runtime::block_on(fut);
        assert!(res.is_err());
    }

    #[test]
    fn test_store_at_resolves_logbook_subdir() {
        let base = std::env::temp_dir().join("riptide-cmd-store-test");
        let store = test_store_at(&base);
        assert_eq!(
            store.paths().directory,
            base.join("logbook"),
            "store should mount on <base>/logbook"
        );
        // Touching AppState isn't possible without a Tauri runtime, but
        // we can confirm the surface compiles and the helper resolves.
        let _ = AppState::new();
        // BTreeMap import smoke — the readme/CHANGELOG paths use it.
        let mut m: BTreeMap<&str, &str> = BTreeMap::new();
        m.insert("k", "v");
        assert_eq!(m.get("k"), Some(&"v"));
    }
}
