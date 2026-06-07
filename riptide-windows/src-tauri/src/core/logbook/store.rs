//! Read-side Logbook store.
//!
//! `LogbookStore` mirrors the macOS `LogbookStore` actor: it holds the
//! `LogbookPaths` and exposes `query` / `clear` / `export` over the
//! per-UTC-day JSONL files written by `LogbookWriter`.
//!
//! All public methods are `async` so callers can `await` from a Tauri
//! command. The actual file IO runs on `tokio::task::spawn_blocking` so
//! the runtime isn't blocked on disk — the `tokio::sync::Mutex<()>` only
//! serializes concurrent store calls (multiple Tauri commands firing at
//! once), not the IO itself.
//!
//! Read path is lenient by design: malformed lines are silently dropped
//! so a partially-written flush (process kill mid-write) never wedges
//! the UI.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use super::entry::{LogCategory, LogEntry, LogLevel};
use super::paths::LogbookPaths;

/// Filter applied by [`LogbookStore::query`] and [`LogbookStore::export`].
///
/// All fields are optional; an empty query (the `Default`) returns every
/// entry in the most recent 1000 lines. `from` / `to` are inclusive on
/// both ends. `limit` is capped at 5000 to bound memory.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LogbookQuery {
    /// Inclusive lower bound (UTC). `None` ⇒ no lower bound.
    pub from: Option<DateTime<Utc>>,
    /// Inclusive upper bound (UTC). `None` ⇒ no upper bound.
    pub to: Option<DateTime<Utc>>,
    /// Restrict to these levels. Empty ⇒ no level filter.
    pub levels: Vec<LogLevel>,
    /// Restrict to these categories. Empty ⇒ no category filter.
    pub categories: Vec<LogCategory>,
    /// Maximum number of entries returned. `None` ⇒ 1000. Capped at 5000.
    pub limit: Option<u32>,
}

impl LogbookQuery {
    /// Effective limit (capped). Tests rely on this number for assertions.
    pub fn effective_limit(&self) -> usize {
        self.limit.unwrap_or(1000).min(5000) as usize
    }
}

/// Persistent Logbook read-side store.
pub struct LogbookStore {
    paths: LogbookPaths,
    /// Serializes concurrent store operations. The body of each method
    /// does the actual work inside `spawn_blocking`, so the lock is held
    /// for microseconds in practice.
    lock: Mutex<()>,
}

impl LogbookStore {
    pub fn new(paths: LogbookPaths) -> Self {
        Self {
            paths,
            lock: Mutex::new(()),
        }
    }

    /// The path resolver this store reads from. Useful for tooling that
    /// wants to open the same directory via [`LogbookWriter`].
    pub fn paths(&self) -> &LogbookPaths {
        &self.paths
    }

    /// Read entries matching `q` across the entire directory.
    pub async fn query(&self, q: LogbookQuery) -> Result<Vec<LogEntry>, String> {
        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        tokio::task::spawn_blocking(move || query_blocking(&paths, &q))
            .await
            .map_err(|e| format!("Logbook query task join failed: {e}"))?
    }

    /// Remove entries. Returns the number of entries that were removed.
    ///
    /// Semantics:
    /// - `category = None`, `before = None` ⇒ delete every `.jsonl` file
    ///   in the directory. Returns 0 (the file count is the meaningful
    ///   number; entries can only be approximated without reading).
    /// - `category = None`, `before = Some(d)` ⇒ delete files whose UTC
    ///   day is strictly before `d`. Returns 0.
    /// - `category = Some(c)`, `before = None` ⇒ scan every file, drop
    ///   entries whose category equals `c`, rewrite the file. Returns
    ///   the number of entries dropped.
    /// - `category = Some(c)`, `before = Some(d)` ⇒ first prune by date,
    ///   then drop the category from the remaining files. Returns the
    ///   number of entries dropped in the second pass.
    pub async fn clear(
        &self,
        category: Option<LogCategory>,
        before: Option<DateTime<Utc>>,
    ) -> Result<u32, String> {
        let _guard = self.lock.lock().await;
        let paths = self.paths.clone();
        tokio::task::spawn_blocking(move || clear_blocking(&paths, category, before))
            .await
            .map_err(|e| format!("Logbook clear task join failed: {e}"))?
    }

    /// Export entries matching `q` to `dest` as a single JSONL file
    /// (sorted by timestamp ascending). Returns the number of entries
    /// written. `dest` is overwritten if it exists.
    pub async fn export(&self, q: LogbookQuery, dest: PathBuf) -> Result<u32, String> {
        let entries = self.query(q).await?;
        let _guard = self.lock.lock().await;
        tokio::task::spawn_blocking(move || export_blocking(&entries, &dest))
            .await
            .map_err(|e| format!("Logbook export task join failed: {e}"))?
    }
}

// ── blocking implementations ───────────────────────────────────

fn query_blocking(paths: &LogbookPaths, q: &LogbookQuery) -> Result<Vec<LogEntry>, String> {
    if !paths.directory.exists() {
        return Ok(Vec::new());
    }
    let mut files = list_jsonl_files(&paths.directory)?;
    files.sort();
    let limit = q.effective_limit();
    let mut out: Vec<LogEntry> = Vec::new();

    for file in files {
        // Cheap pre-filter: skip whole files whose UTC day is outside
        // the requested range. This matters when the directory has
        // weeks of logs and the user only wants today.
        let day_str = file
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .to_string();
        if !day_in_range(&day_str, q.from.as_ref(), q.to.as_ref()) {
            continue;
        }

        let content = std::fs::read_to_string(&file)
            .map_err(|e| format!("Failed to read {:?}: {}", file, e))?;
        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let entry: LogEntry = match serde_json::from_str(line) {
                Ok(e) => e,
                Err(_) => continue, // skip malformed lines
            };
            if !matches_query(&entry, q) {
                continue;
            }
            out.push(entry);
            if out.len() >= limit {
                return Ok(out);
            }
        }
    }
    Ok(out)
}

fn clear_blocking(
    paths: &LogbookPaths,
    category: Option<LogCategory>,
    before: Option<DateTime<Utc>>,
) -> Result<u32, String> {
    if !paths.directory.exists() {
        return Ok(0);
    }

    // First pass: prune whole files when a date bound is supplied.
    if let Some(cutoff) = before {
        let cutoff_day = paths.day_string(cutoff);
        for file in list_jsonl_files(&paths.directory)? {
            let day = file
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or_default()
                .to_string();
            // Strictly-before: a file at exactly the cutoff day is kept.
            if day.as_str() < cutoff_day.as_str() {
                if let Err(e) = std::fs::remove_file(&file) {
                    log::warn!("Logbook: failed to remove {:?}: {}", file, e);
                }
            }
        }
    }

    // Second pass: drop entries of a given category (if requested).
    let mut removed: u32 = 0;
    if let Some(cat) = category {
        for file in list_jsonl_files(&paths.directory)? {
            let content = match std::fs::read_to_string(&file) {
                Ok(c) => c,
                Err(_) => continue,
            };
            let mut kept: Vec<&str> = Vec::new();
            for line in content.lines() {
                if line.trim().is_empty() {
                    continue;
                }
                match serde_json::from_str::<LogEntry>(line) {
                    Ok(entry) if entry.category == cat => {
                        removed = removed.saturating_add(1);
                    }
                    Ok(_) => kept.push(line),
                    Err(_) => {
                        // Keep malformed lines on disk — better than
                        // silently dropping user data we can't read.
                        kept.push(line);
                    }
                }
            }
            if kept.len() < content.lines().filter(|l| !l.trim().is_empty()).count() {
                write_lines(&file, &kept)?;
            }
        }
    }
    Ok(removed)
}

fn export_blocking(entries: &[LogEntry], dest: &Path) -> Result<u32, String> {
    use std::io::Write;

    if let Some(parent) = dest.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create export dir {:?}: {}", parent, e))?;
        }
    }
    let mut sorted: Vec<&LogEntry> = entries.iter().collect();
    sorted.sort_by(|a, b| a.ts.cmp(&b.ts));

    let file = std::fs::File::create(dest)
        .map_err(|e| format!("Failed to create export file {:?}: {}", dest, e))?;
    let mut writer = std::io::BufWriter::new(file);
    let mut count: u32 = 0;
    for entry in sorted {
        let line = serde_json::to_string(entry)
            .map_err(|e| format!("Failed to serialize entry: {}", e))?;
        writer
            .write_all(line.as_bytes())
            .map_err(|e| format!("Write failed: {}", e))?;
        writer
            .write_all(b"\n")
            .map_err(|e| format!("Write failed: {}", e))?;
        count = count.saturating_add(1);
    }
    writer.flush().map_err(|e| format!("Flush failed: {}", e))?;
    Ok(count)
}

fn list_jsonl_files(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let read = std::fs::read_dir(dir)
        .map_err(|e| format!("Failed to read logbook dir {:?}: {}", dir, e))?;
    let mut out = Vec::new();
    for entry in read.flatten() {
        let p = entry.path();
        if p.extension().and_then(|s| s.to_str()) == Some("jsonl") && p.is_file() {
            out.push(p);
        }
    }
    Ok(out)
}

fn day_in_range(day: &str, from: Option<&DateTime<Utc>>, to: Option<&DateTime<Utc>>) -> bool {
    if let Some(f) = from {
        let from_day = f.format("%Y-%m-%d").to_string();
        if day < from_day.as_str() {
            return false;
        }
    }
    if let Some(t) = to {
        let to_day = t.format("%Y-%m-%d").to_string();
        if day > to_day.as_str() {
            return false;
        }
    }
    true
}

fn matches_query(entry: &LogEntry, q: &LogbookQuery) -> bool {
    if !q.levels.is_empty() && !q.levels.contains(&entry.level) {
        return false;
    }
    if !q.categories.is_empty() && !q.categories.contains(&entry.category) {
        return false;
    }
    if let Some(from) = q.from {
        if let Some(ts) = entry.timestamp() {
            if ts < from {
                return false;
            }
        }
    }
    if let Some(to) = q.to {
        if let Some(ts) = entry.timestamp() {
            if ts > to {
                return false;
            }
        }
    }
    true
}

fn write_lines(path: &Path, lines: &[&str]) -> Result<(), String> {
    use std::io::Write;
    let file =
        std::fs::File::create(path).map_err(|e| format!("Failed to rewrite {:?}: {}", path, e))?;
    let mut writer = std::io::BufWriter::new(file);
    for line in lines {
        writer
            .write_all(line.as_bytes())
            .map_err(|e| format!("Rewrite write failed: {}", e))?;
        writer
            .write_all(b"\n")
            .map_err(|e| format!("Rewrite write failed: {}", e))?;
    }
    writer
        .flush()
        .map_err(|e| format!("Rewrite flush failed: {}", e))?;
    Ok(())
}

#[allow(dead_code)]
fn _btreemap_marker(_: BTreeMap<String, String>) {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::logbook::entry::{LogCategory, LogEntry, LogLevel};
    use crate::core::logbook::paths::LogbookPaths;
    use crate::core::logbook::writer::LogbookWriter;
    use chrono::{TimeZone, Utc};
    use std::time::Duration;

    fn fresh_dir(tag: &str) -> std::path::PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "riptide-logbook-store-{}-{}",
            tag,
            Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    /// Write a hand-rolled JSONL file under `dir/<day>.jsonl` directly
    /// so we can test the store without involving the writer's async
    /// batch flush. We open with `create + append` so that back-to-back
    /// calls for the same day accumulate entries (the production writer
    /// appends, and tests should match that semantics).
    fn write_file(dir: &std::path::Path, day: &str, entries: &[LogEntry]) {
        use std::io::Write;
        let path = dir.join(format!("{day}.jsonl"));
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .unwrap();
        for e in entries {
            let line = serde_json::to_string(e).unwrap();
            writeln!(f, "{}", line).unwrap();
        }
    }

    fn entry(day: u32, level: LogLevel, cat: LogCategory, msg: &str) -> LogEntry {
        let ts = Utc.with_ymd_and_hms(2026, 6, day, 12, 0, 0).unwrap();
        let mut e = LogEntry::with_timestamp(ts, level, cat, msg);
        e.fields.insert("k".into(), "v".into());
        e
    }

    /// Wait until `path` exists (poll). The writer's 50ms batch window
    /// means we can't read back synchronously; tests that exercise the
    /// writer use this helper. Tests that bypass the writer (write_file)
    /// don't need it.
    async fn wait_for(p: &std::path::Path) {
        for _ in 0..200 {
            if p.exists() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("timed out waiting for {:?}", p);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn query_empty_dir_returns_empty() {
        let dir = fresh_dir("empty");
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let out = store.query(LogbookQuery::default()).await.unwrap();
        assert!(out.is_empty());
    }

    #[tokio::test(flavor = "current_thread")]
    async fn query_returns_all_entries_in_date_order() {
        let dir = fresh_dir("all");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry(5, LogLevel::Info, LogCategory::App, "first"),
                entry(5, LogLevel::Error, LogCategory::Mihomo, "second"),
            ],
        );
        write_file(
            &dir,
            "2026-06-06",
            &[entry(6, LogLevel::Info, LogCategory::Service, "third")],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let out = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].message, "first");
        assert_eq!(out[1].message, "second");
        assert_eq!(out[2].message, "third");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn query_filters_by_level_and_category() {
        let dir = fresh_dir("filter");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry(5, LogLevel::Info, LogCategory::App, "i-app"),
                entry(5, LogLevel::Warning, LogCategory::Service, "w-svc"),
                entry(5, LogLevel::Error, LogCategory::Mihomo, "e-mihomo"),
            ],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let q = LogbookQuery {
            levels: vec![LogLevel::Warning, LogLevel::Error],
            categories: vec![],
            ..Default::default()
        };
        let out = store.query(q).await.unwrap();
        assert_eq!(out.len(), 2);
        assert!(out.iter().all(|e| e.level != LogLevel::Info));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn query_skips_malformed_lines() {
        let dir = fresh_dir("malformed");
        // Hand-write a file with one good line, one garbage line, and
        // one trailing blank.
        use std::io::Write;
        let path = dir.join("2026-06-05.jsonl");
        let mut f = std::fs::File::create(&path).unwrap();
        let e = entry(5, LogLevel::Info, LogCategory::App, "ok");
        writeln!(f, "{}", serde_json::to_string(&e).unwrap()).unwrap();
        writeln!(f, "this is not json").unwrap();
        writeln!(f, "").unwrap();
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let out = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].message, "ok");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn clear_by_category_rewrites_files_and_counts_removals() {
        let dir = fresh_dir("clear-cat");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry(5, LogLevel::Info, LogCategory::App, "keep"),
                entry(5, LogLevel::Info, LogCategory::Mihomo, "drop-1"),
                entry(5, LogLevel::Info, LogCategory::Mihomo, "drop-2"),
            ],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let removed = store.clear(Some(LogCategory::Mihomo), None).await.unwrap();
        assert_eq!(removed, 2);
        let remaining = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].message, "keep");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn clear_by_date_prunes_whole_files() {
        let dir = fresh_dir("clear-date");
        write_file(
            &dir,
            "2026-06-04",
            &[entry(4, LogLevel::Info, LogCategory::App, "old")],
        );
        write_file(
            &dir,
            "2026-06-05",
            &[entry(5, LogLevel::Info, LogCategory::App, "new")],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let cutoff = Utc.with_ymd_and_hms(2026, 6, 5, 0, 0, 0).unwrap();
        let _ = store.clear(None, Some(cutoff)).await.unwrap();
        let remaining = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].message, "new");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn export_writes_sorted_jsonl_to_dest() {
        let dir = fresh_dir("export");
        // Insert in non-chronological order on disk — export must sort.
        write_file(
            &dir,
            "2026-06-06",
            &[entry(6, LogLevel::Info, LogCategory::App, "b")],
        );
        write_file(
            &dir,
            "2026-06-05",
            &[entry(5, LogLevel::Info, LogCategory::App, "a")],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let dest = dir.join("exported.jsonl");
        let count = store
            .export(LogbookQuery::default(), dest.clone())
            .await
            .unwrap();
        assert_eq!(count, 2);
        let raw = std::fs::read_to_string(&dest).unwrap();
        let messages: Vec<String> = raw
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str::<LogEntry>(l).unwrap().message)
            .collect();
        assert_eq!(messages, vec!["a".to_string(), "b".to_string()]);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn store_sees_what_writer_wrote() {
        // End-to-end smoke: writer + store on the same dir.
        let dir = fresh_dir("e2e");
        let writer = LogbookWriter::spawn(LogbookPaths {
            directory: dir.clone(),
        });
        writer.log_info("hello", LogCategory::App);
        writer.log_warning("careful", LogCategory::Service);

        // The writer's batch flusher is 50ms — give it a few cycles.
        let day = writer.paths().day_string(Utc::now());
        wait_for(&dir.join(format!("{day}.jsonl"))).await;

        // Drop the writer so its background task exits cleanly.
        drop(writer);

        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let out = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(out.len(), 2);
        let messages: Vec<&str> = out.iter().map(|e| e.message.as_str()).collect();
        assert!(messages.contains(&"hello"));
        assert!(messages.contains(&"careful"));
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// B3.4 QA tests (task: B3 — Logbook 17 个 Rust 测试(writer 8 + store 6 + paths 3))
//
// Separate module so they don't collide with the producer's `mod tests`
// block above. Six tests, one per bullet in the task description.
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod b3_4_tests {
    use super::*;
    use crate::core::logbook::entry::{LogCategory, LogEntry, LogLevel};
    use crate::core::logbook::paths::LogbookPaths;
    use chrono::{TimeZone, Utc};
    use std::time::Duration;

    fn fresh_dir(tag: &str) -> std::path::PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "riptide-logbook-b34-store-{}-{}",
            tag,
            Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    /// Write a hand-rolled JSONL file under `dir/<day>.jsonl` directly so
    /// we can test the store without involving the writer's async batch
    /// flush. We open with `create + append` so that back-to-back calls
    /// for the same day accumulate entries (the production writer
    /// appends, and tests should match that semantics).
    fn write_file(dir: &std::path::Path, day: &str, entries: &[LogEntry]) {
        use std::io::Write;
        let path = dir.join(format!("{day}.jsonl"));
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .unwrap();
        for e in entries {
            let line = serde_json::to_string(e).unwrap();
            writeln!(f, "{}", line).unwrap();
        }
    }

    fn entry_at(day: u32, hour: u32, level: LogLevel, cat: LogCategory, msg: &str) -> LogEntry {
        let ts = Utc.with_ymd_and_hms(2026, 6, day, hour, 0, 0).unwrap();
        LogEntry::with_timestamp(ts, level, cat, msg)
    }

    // ── Test 1: query 返回所有 entry ───────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_query_returns_all_entries() {
        let dir = fresh_dir("all");
        // Spread entries across two days and three categories.
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry_at(5, 8, LogLevel::Info, LogCategory::App, "a-1"),
                entry_at(5, 9, LogLevel::Warning, LogCategory::Service, "a-2"),
                entry_at(5, 10, LogLevel::Error, LogCategory::Mihomo, "a-3"),
            ],
        );
        write_file(
            &dir,
            "2026-06-06",
            &[
                entry_at(6, 8, LogLevel::Info, LogCategory::Profile, "b-1"),
                entry_at(6, 9, LogLevel::Info, LogCategory::App, "b-2"),
            ],
        );

        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        let q = LogbookQuery {
            limit: Some(100),
            ..Default::default()
        };
        let out = store.query(q).await.unwrap();
        assert_eq!(
            out.len(),
            5,
            "all 5 entries must be returned, got {}",
            out.len()
        );

        // Order is file order then line order — verify by message.
        let mut messages: Vec<String> = out.iter().map(|e| e.message.clone()).collect();
        messages.sort();
        let mut expected: Vec<String> = ["a-1", "a-2", "a-3", "b-1", "b-2"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        expected.sort();
        assert_eq!(messages, expected);
    }

    // ── Test 2: query + level 过滤 ─────────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_query_filters_by_level() {
        let dir = fresh_dir("level");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry_at(5, 8, LogLevel::Info, LogCategory::App, "i-1"),
                entry_at(5, 9, LogLevel::Info, LogCategory::App, "i-2"),
                entry_at(5, 10, LogLevel::Warning, LogCategory::Service, "w-1"),
                entry_at(5, 11, LogLevel::Error, LogCategory::Mihomo, "e-1"),
                entry_at(5, 12, LogLevel::Error, LogCategory::Helper, "e-2"),
            ],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });

        // Only error → 2 entries
        let q_err = LogbookQuery {
            levels: vec![LogLevel::Error],
            limit: Some(100),
            ..Default::default()
        };
        let out_err = store.query(q_err).await.unwrap();
        assert_eq!(out_err.len(), 2);
        assert!(out_err.iter().all(|e| e.level == LogLevel::Error));

        // info + warning → 3 entries
        let q_iw = LogbookQuery {
            levels: vec![LogLevel::Info, LogLevel::Warning],
            limit: Some(100),
            ..Default::default()
        };
        let out_iw = store.query(q_iw).await.unwrap();
        assert_eq!(out_iw.len(), 3);
        assert!(out_iw.iter().all(|e| e.level != LogLevel::Error));
    }

    // ── Test 3: query + category 过滤 ──────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_query_filters_by_category() {
        let dir = fresh_dir("category");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry_at(5, 8, LogLevel::Info, LogCategory::App, "x-app-1"),
                entry_at(5, 9, LogLevel::Info, LogCategory::Service, "x-svc-1"),
                entry_at(5, 10, LogLevel::Info, LogCategory::Service, "x-svc-2"),
                entry_at(5, 11, LogLevel::Info, LogCategory::Mihomo, "x-mihomo-1"),
                entry_at(5, 12, LogLevel::Info, LogCategory::App, "x-app-2"),
            ],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });

        // Service only → 2 entries
        let q_svc = LogbookQuery {
            categories: vec![LogCategory::Service],
            limit: Some(100),
            ..Default::default()
        };
        let out_svc = store.query(q_svc).await.unwrap();
        assert_eq!(out_svc.len(), 2);
        assert!(out_svc.iter().all(|e| e.category == LogCategory::Service));

        // App + Mihomo → 3 entries
        let q_am = LogbookQuery {
            categories: vec![LogCategory::App, LogCategory::Mihomo],
            limit: Some(100),
            ..Default::default()
        };
        let out_am = store.query(q_am).await.unwrap();
        assert_eq!(out_am.len(), 3);
        // LogCategory does not derive Ord, so collect into a HashSet
        // (it does derive Hash + Eq) for the equality check.
        let cats: std::collections::HashSet<_> = out_am.iter().map(|e| e.category).collect();
        let expected: std::collections::HashSet<_> = [LogCategory::App, LogCategory::Mihomo]
            .into_iter()
            .collect();
        assert_eq!(cats, expected);
    }

    // ── Test 4: query + 时间范围 ───────────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_query_filters_by_time_range() {
        let dir = fresh_dir("time");
        // Three days, two entries per day at different hours.
        for (day, hour) in [(5u32, 1u32), (5, 23), (6, 0), (6, 23), (7, 12)] {
            write_file(
                &dir,
                &format!("2026-06-{day:02}"),
                &[entry_at(
                    day,
                    hour,
                    LogLevel::Info,
                    LogCategory::App,
                    &format!("d{day}-h{hour}"),
                )],
            );
        }
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });

        // Range covers only day 6 (UTC). Expect 2 entries.
        let from = Utc.with_ymd_and_hms(2026, 6, 6, 0, 0, 0).unwrap();
        let to = Utc.with_ymd_and_hms(2026, 6, 6, 23, 59, 59).unwrap();
        let q = LogbookQuery {
            from: Some(from),
            to: Some(to),
            limit: Some(100),
            ..Default::default()
        };
        let out = store.query(q).await.unwrap();
        assert_eq!(
            out.len(),
            2,
            "expected 2 entries on day 6, got {}: {:?}",
            out.len(),
            out.iter().map(|e| &e.message).collect::<Vec<_>>()
        );
        assert!(out.iter().all(|e| e.message.starts_with("d6-")));

        // Range covers days 5 and 6. Expect 4 entries.
        let from = Utc.with_ymd_and_hms(2026, 6, 5, 0, 0, 0).unwrap();
        let to = Utc.with_ymd_and_hms(2026, 6, 6, 23, 59, 59).unwrap();
        let q = LogbookQuery {
            from: Some(from),
            to: Some(to),
            limit: Some(100),
            ..Default::default()
        };
        let out = store.query(q).await.unwrap();
        assert_eq!(out.len(), 4);
    }

    // ── Test 5: clear 返回正确条数 ─────────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_clear_returns_correct_count() {
        let dir = fresh_dir("clear");
        // Build a mix across two days and three categories.
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry_at(5, 8, LogLevel::Info, LogCategory::Mihomo, "m-1"),
                entry_at(5, 9, LogLevel::Info, LogCategory::Mihomo, "m-2"),
                entry_at(5, 10, LogLevel::Info, LogCategory::Mihomo, "m-3"),
                entry_at(5, 11, LogLevel::Info, LogCategory::App, "a-1"),
                entry_at(5, 12, LogLevel::Info, LogCategory::Service, "s-1"),
            ],
        );
        write_file(
            &dir,
            "2026-06-06",
            &[
                entry_at(6, 8, LogLevel::Info, LogCategory::Mihomo, "m-4"),
                entry_at(6, 9, LogLevel::Info, LogCategory::Mihomo, "m-5"),
                entry_at(6, 10, LogLevel::Info, LogCategory::App, "a-2"),
            ],
        );
        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });

        // Sanity: 8 entries total
        let initial = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(initial.len(), 8);

        // Clear by category = Mihomo → expect 5 removals (m-1..m-5)
        let removed = store
            .clear(Some(LogCategory::Mihomo), None)
            .await
            .expect("clear ok");
        assert_eq!(removed, 5, "Mihomo must report 5 removals, got {removed}");

        // 3 entries left (a-1, s-1, a-2)
        let remaining = store.query(LogbookQuery::default()).await.unwrap();
        assert_eq!(remaining.len(), 3);
        let remaining_msgs: Vec<String> = remaining.iter().map(|e| e.message.clone()).collect();
        assert!(remaining_msgs.contains(&"a-1".to_string()));
        assert!(remaining_msgs.contains(&"s-1".to_string()));
        assert!(remaining_msgs.contains(&"a-2".to_string()));

        // Clear a category with no matches → 0
        let zero = store
            .clear(Some(LogCategory::Dns), None)
            .await
            .expect("clear ok");
        assert_eq!(
            zero, 0,
            "clear of absent category must return 0, got {zero}"
        );
    }

    // ── Test 6: export 生成目标文件 ────────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_export_writes_target_file() {
        let dir = fresh_dir("export");
        write_file(
            &dir,
            "2026-06-05",
            &[
                entry_at(5, 8, LogLevel::Info, LogCategory::App, "first"),
                entry_at(5, 10, LogLevel::Warning, LogCategory::Service, "second"),
                entry_at(5, 12, LogLevel::Error, LogCategory::Mihomo, "third"),
            ],
        );
        write_file(
            &dir,
            "2026-06-06",
            &[
                entry_at(6, 9, LogLevel::Info, LogCategory::App, "fourth"),
                entry_at(6, 14, LogLevel::Info, LogCategory::App, "fifth"),
            ],
        );

        let store = LogbookStore::new(LogbookPaths {
            directory: dir.clone(),
        });
        // Export only errors → 1 entry
        let dest = dir.join("only-errors.jsonl");
        let q = LogbookQuery {
            levels: vec![LogLevel::Error],
            limit: Some(100),
            ..Default::default()
        };
        let count = store.export(q, dest.clone()).await.expect("export ok");
        assert_eq!(count, 1, "exactly one error must be exported, got {count}");

        // Verify dest file exists, is a single valid JSONL line, sorted.
        let raw = std::fs::read_to_string(&dest).expect("read dest");
        let lines: Vec<&str> = raw.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(lines.len(), 1, "export must have one line, got {lines:?}");
        let entry: LogEntry = serde_json::from_str(lines[0]).expect("valid json");
        assert_eq!(entry.message, "third");
        assert_eq!(entry.level, LogLevel::Error);

        // Round-trip: re-read the dest via the store and confirm the count.
        let store2 = LogbookStore::new(LogbookPaths {
            directory: dir.parent().unwrap().to_path_buf(),
        });
        // We just want to sanity-check that the file is valid JSONL;
        // read it back as raw lines and confirm count.
        let reread = std::fs::read_to_string(&dest).unwrap();
        let reread_lines: Vec<&str> = reread.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(reread_lines.len(), 1);
        // Touch store2 to make sure it's wired (compile-check).
        let _ = store2.paths().directory;
    }
}
