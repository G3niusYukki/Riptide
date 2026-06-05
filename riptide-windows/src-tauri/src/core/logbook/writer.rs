//! Fire-and-forget Logbook writer.
//!
//! Callers (`mode_coordinator`, `subscription_scheduler`, `service`,
//! `sysproxy`, `recovery_watchdog`) each hold an `Arc<LogbookWriter>`. They
//! call `log_info` / `log_warning` / `log_error` synchronously; the call
//! only puts the entry on an unbounded mpsc channel and returns. A
//! background task drains the channel, groups entries by UTC day, and
//! appends them to `<dir>/YYYY-MM-DD.jsonl` files using a `BufWriter` with
//! a 50ms batch flush.
//!
//! This matches the macOS contract: the business path must never block on
//! diagnostic logging, and IO errors are swallowed (`log::warn!`) so a
//! full disk / rotated log / locked file never bubbles up to the caller.
//!
//! The writer is `Clone` and `Send + Sync` — the `tx` is an
//! `UnboundedSender` (cheap to clone, no allocation per call) and `paths`
//! is wrapped in `Arc` so the spawned background task can hold its own
//! reference.

use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::mpsc;
use tokio::time::MissedTickBehavior;

use super::entry::{LogCategory, LogEntry, LogLevel};
use super::paths::LogbookPaths;

/// How often the background flusher wakes up to drain pending entries.
pub const FLUSH_INTERVAL_MS: u64 = 50;
/// Maximum entries batched per flush. Keeps the in-memory queue bounded
/// under bursty producers (e.g. recovery watchdog restarts).
pub const MAX_BATCH: usize = 256;

/// Fire-and-forget Logbook writer. Cheap to clone.
#[derive(Clone)]
pub struct LogbookWriter {
    tx: mpsc::UnboundedSender<LogEntry>,
    paths: Arc<LogbookPaths>,
}

impl LogbookWriter {
    /// Spawn the background flusher and return a writer handle.
    ///
    /// The background task is owned by `tauri::async_runtime` and lives
    /// for the lifetime of the process. Drop the writer to stop producing;
    /// the task will drain the queue and exit.
    pub fn spawn(paths: LogbookPaths) -> Self {
        let (tx, rx) = mpsc::unbounded_channel::<LogEntry>();
        let paths = Arc::new(paths);
        let task_paths = paths.clone();
        tauri::async_runtime::spawn(async move {
            run_loop(rx, task_paths).await;
        });
        Self { tx, paths }
    }

    /// Build a writer rooted at the default Windows app-data dir.
    pub fn spawn_default() -> Self {
        Self::spawn(LogbookPaths::default_windows())
    }

    /// The directory this writer writes to. Useful for tests and for the
    /// `LogbookStore` that needs to read back what we wrote.
    pub fn directory(&self) -> &Path {
        &self.paths.directory
    }

    /// The path resolver this writer was built with. Lets callers (and
    /// tests) build a `LogbookStore` over the same directory without
    /// having to recompute `default_windows()`.
    pub fn paths(&self) -> &super::paths::LogbookPaths {
        &self.paths
    }

    /// True iff the background task is still consuming. Drops to `false`
    /// only after the writer is dropped *and* the queue is drained.
    pub fn is_alive(&self) -> bool {
        !self.tx.is_closed()
    }

    /// Log an info-level event with no extra context.
    pub fn log_info(&self, message: impl Into<String>, category: LogCategory) {
        self.send(LogEntry::new(LogLevel::Info, category, message));
    }

    /// Log a warning-level event with no extra context.
    pub fn log_warning(&self, message: impl Into<String>, category: LogCategory) {
        self.send(LogEntry::new(LogLevel::Warning, category, message));
    }

    /// Log an error-level event with no extra context.
    pub fn log_error(&self, message: impl Into<String>, category: LogCategory) {
        self.send(LogEntry::new(LogLevel::Error, category, message));
    }

    /// Info-level with a fixed `fields` map. Useful at the injection sites
    /// where the context is built up once and then passed in.
    pub fn log_info_with_fields(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: std::collections::BTreeMap<String, String>,
    ) {
        let mut entry = LogEntry::new(LogLevel::Info, category, message);
        entry.fields.extend(fields);
        self.send(entry);
    }

    pub fn log_warning_with_fields(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: std::collections::BTreeMap<String, String>,
    ) {
        let mut entry = LogEntry::new(LogLevel::Warning, category, message);
        entry.fields.extend(fields);
        self.send(entry);
    }

    pub fn log_error_with_fields(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: std::collections::BTreeMap<String, String>,
    ) {
        let mut entry = LogEntry::new(LogLevel::Error, category, message);
        entry.fields.extend(fields);
        self.send(entry);
    }

    /// Variadic context helpers. The `I` type can be a slice of tuples,
    /// a `Vec<(K,V)>`, or anything `IntoIterator`.
    pub fn log_info_with<I, K, V>(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: I,
    ) where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        self.log_with(LogLevel::Info, message, category, fields);
    }

    pub fn log_warning_with<I, K, V>(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: I,
    ) where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        self.log_with(LogLevel::Warning, message, category, fields);
    }

    pub fn log_error_with<I, K, V>(
        &self,
        message: impl Into<String>,
        category: LogCategory,
        fields: I,
    ) where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        self.log_with(LogLevel::Error, message, category, fields);
    }

    /// Low-level send. Use [`log_info`](Self::log_info) / friends unless
    /// you really need to construct a custom `LogEntry` (e.g. with a
    /// pre-baked timestamp from a test).
    pub fn send(&self, entry: LogEntry) {
        // UnboundedSender::send can fail only if the receiver was dropped
        // (i.e. the background task exited). We swallow that — fire and
        // forget, by design.
        let _ = self.tx.send(entry);
    }

    fn log_with<I, K, V>(
        &self,
        level: LogLevel,
        message: impl Into<String>,
        category: LogCategory,
        fields: I,
    ) where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        let mut entry = LogEntry::new(level, category, message);
        for (k, v) in fields {
            entry.fields.insert(k.into(), v.into());
        }
        self.send(entry);
    }
}

async fn run_loop(mut rx: mpsc::UnboundedReceiver<LogEntry>, paths: Arc<LogbookPaths>) {
    let mut batch: Vec<LogEntry> = Vec::with_capacity(MAX_BATCH);
    let mut tick = tokio::time::interval(Duration::from_millis(FLUSH_INTERVAL_MS));
    tick.set_missed_tick_behavior(MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            biased;
            // Always prefer draining queued entries first so we can shut
            // down quickly when the producer is dropped.
            maybe = rx.recv() => {
                match maybe {
                    Some(entry) => {
                        batch.push(entry);
                        if batch.len() >= MAX_BATCH {
                            flush_blocking(&paths, &mut batch).await;
                        }
                    }
                    None => {
                        // Producer gone — final drain then exit.
                        if !batch.is_empty() {
                            flush_blocking(&paths, &mut batch).await;
                        }
                        break;
                    }
                }
            }
            _ = tick.tick() => {
                if !batch.is_empty() {
                    flush_blocking(&paths, &mut batch).await;
                }
            }
        }
    }
}

/// Drain `batch` and append entries to per-day files. One synchronous
/// filesystem call per day; lives behind `spawn_blocking` so the tokio
/// runtime isn't blocked on disk IO.
async fn flush_blocking(paths: &LogbookPaths, batch: &mut Vec<LogEntry>) {
    if batch.is_empty() {
        return;
    }
    let drained: Vec<LogEntry> = std::mem::take(batch);

    // Group by UTC day. Use BTreeMap for stable (and therefore testable)
    // iteration order; the order in which days are written doesn't affect
    // correctness because each day's file is independent.
    let mut by_day: std::collections::BTreeMap<String, Vec<LogEntry>> =
        std::collections::BTreeMap::new();
    for entry in drained {
        let day = entry_day(paths, &entry);
        by_day.entry(day).or_default().push(entry);
    }

    let paths = paths.clone();
    let result = tokio::task::spawn_blocking(move || {
        if let Err(e) = paths.create_dir_if_needed() {
            log::warn!("Logbook: failed to create directory {:?}: {}", paths.directory, e);
            return;
        }
        for (day, entries) in &by_day {
            let file_path = paths.directory.join(format!("{day}.jsonl"));
            if let Err(e) = append_to_file(&file_path, entries) {
                log::warn!(
                    "Logbook: failed to write {} entries to {:?}: {}",
                    entries.len(),
                    file_path,
                    e
                );
            }
        }
    })
    .await;

    if let Err(e) = result {
        log::warn!("Logbook: flush task join failed: {}", e);
    }
}

fn entry_day(paths: &LogbookPaths, entry: &LogEntry) -> String {
    match entry.timestamp() {
        Some(ts) => paths.day_string(ts),
        None => paths.day_string(chrono::Utc::now()),
    }
}

fn append_to_file(path: &Path, entries: &[LogEntry]) -> std::io::Result<()> {
    use std::io::Write;

    let file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    let mut writer = std::io::BufWriter::new(file);
    for entry in entries {
        let line = serde_json::to_string(entry).map_err(io_other)?;
        writer.write_all(line.as_bytes())?;
        writer.write_all(b"\n")?;
    }
    writer.flush()?;
    Ok(())
}

fn io_other<E: std::fmt::Display>(e: E) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::Other, e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::logbook::entry::{LogCategory, LogEntry, LogLevel};
    use crate::core::logbook::paths::LogbookPaths;
    use chrono::Utc;
    use std::collections::BTreeMap;
    use std::time::Duration;

    /// Build a writer rooted at a unique temp dir. Returns the writer and
    /// the temp path so tests can read back what was written.
    fn fresh_writer(tag: &str) -> (LogbookWriter, std::path::PathBuf) {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "riptide-logbook-test-{}-{}",
            tag,
            Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let _ = std::fs::remove_dir_all(&p);
        let paths = LogbookPaths::resolve(&p);
        (LogbookWriter::spawn(paths), p)
    }

    /// Wait until `path/<UTC day>.jsonl` exists, or panic. Polls every
    /// 10ms up to a 2s budget. `cargo test` with the default tokio test
    /// runtime + a 50ms batch interval makes the 2s ceiling comfortable.
    async fn wait_for_file(path: &std::path::Path, day: &str) {
        let target = path.join(format!("{day}.jsonl"));
        for _ in 0..200 {
            if target.exists() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("timed out waiting for {:?}", target);
    }

    fn read_lines(path: &std::path::Path) -> Vec<String> {
        let raw = std::fs::read_to_string(path).expect("read jsonl");
        raw.lines()
            .filter(|l| !l.trim().is_empty())
            .map(|s| s.to_string())
            .collect()
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_writes_jsonl_after_batch_window() {
        let (writer, dir) = fresh_writer("basic");
        writer.log_info("hello", LogCategory::App);
        let day = writer
            .paths
            .day_string(Utc::now());
        wait_for_file(&dir, &day).await;

        let lines = read_lines(&dir.join(format!("{day}.jsonl")));
        assert_eq!(lines.len(), 1, "expected one entry, got {lines:?}");
        let entry: LogEntry = serde_json::from_str(&lines[0]).expect("parse");
        assert_eq!(entry.level, LogLevel::Info);
        assert_eq!(entry.category, LogCategory::App);
        assert_eq!(entry.message, "hello");
        assert!(entry.fields.is_empty());
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_preserves_fields_btreemap() {
        let (writer, dir) = fresh_writer("fields");
        let mut fields: BTreeMap<String, String> = BTreeMap::new();
        fields.insert("attempt".into(), "3".into());
        fields.insert("op".into(), "install".into());
        writer.log_warning_with("svc install retry", LogCategory::Service, fields);

        let day = writer.paths().day_string(Utc::now());
        wait_for_file(&dir, &day).await;
        let lines = read_lines(&dir.join(format!("{day}.jsonl")));
        assert_eq!(lines.len(), 1);
        let entry: LogEntry = serde_json::from_str(&lines[0]).unwrap();
        assert_eq!(entry.level, LogLevel::Warning);
        assert_eq!(entry.fields.get("attempt").unwrap(), "3");
        assert_eq!(entry.fields.get("op").unwrap(), "install");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_send_is_low_level_passthrough() {
        let (writer, dir) = fresh_writer("send");
        let entry = LogEntry::new(LogLevel::Error, LogCategory::Diagnostic, "boot ok")
            .with_field("phase", "init");
        writer.send(entry);

        let day = writer.paths().day_string(Utc::now());
        wait_for_file(&dir, &day).await;
        let lines = read_lines(&dir.join(format!("{day}.jsonl")));
        let entry: LogEntry = serde_json::from_str(&lines[0]).unwrap();
        assert_eq!(entry.message, "boot ok");
        assert_eq!(entry.fields.get("phase").unwrap(), "init");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_clamps_max_batch_without_dropping_entries() {
        // Push more than MAX_BATCH entries as fast as possible and confirm
        // the on-disk file ends up with all of them — we must never drop
        // on the floor, only delay.
        let (writer, dir) = fresh_writer("burst");
        let n = MAX_BATCH * 3;
        for i in 0..n {
            writer.log_info(format!("msg-{i}"), LogCategory::App);
        }
        let day = writer.paths().day_string(Utc::now());
        wait_for_file(&dir, &day).await;

        // Wait a little for the tail of the burst to land.
        for _ in 0..200 {
            let lines = read_lines(&dir.join(format!("{day}.jsonl")));
            if lines.len() >= n {
                let messages: Vec<String> = lines
                    .iter()
                    .map(|l| serde_json::from_str::<LogEntry>(l).unwrap().message)
                    .collect();
                // The exact order is not guaranteed because we batch by
                // day, but every message must be present exactly once.
                let mut sorted = messages.clone();
                sorted.sort();
                let mut expected: Vec<String> = (0..n).map(|i| format!("msg-{i}")).collect();
                expected.sort();
                assert_eq!(sorted, expected);
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("burst did not land in time");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_clone_shares_channel() {
        let (writer, dir) = fresh_writer("clone");
        let writer2 = writer.clone();
        writer.log_info("from-1", LogCategory::App);
        writer2.log_warning("from-2", LogCategory::App);

        let day = writer.paths().day_string(Utc::now());
        wait_for_file(&dir, &day).await;
        for _ in 0..200 {
            let lines = read_lines(&dir.join(format!("{day}.jsonl")));
            if lines.len() >= 2 {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("clone writer did not flush both entries");
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_directory_reflects_paths() {
        let (writer, dir) = fresh_writer("dir");
        assert_eq!(writer.directory(), dir.as_path());
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_is_alive_until_drop() {
        let (writer, _dir) = fresh_writer("alive");
        assert!(writer.is_alive());
        drop(writer);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn writer_log_error_with_field_iter() {
        let (writer, dir) = fresh_writer("iter");
        writer.log_error_with(
            "proxy down",
            LogCategory::Mihomo,
            vec![("port", "7890"), ("reason", "timeout")],
        );
        let day = writer.paths().day_string(Utc::now());
        wait_for_file(&dir, &day).await;
        let lines = read_lines(&dir.join(format!("{day}.jsonl")));
        let entry: LogEntry = serde_json::from_str(&lines[0]).unwrap();
        assert_eq!(entry.level, LogLevel::Error);
        assert_eq!(entry.fields.get("port").unwrap(), "7890");
        assert_eq!(entry.fields.get("reason").unwrap(), "timeout");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// B3.4 QA tests (task: B3 — Logbook 17 个 Rust 测试(writer 8 + store 6 + paths 3))
//
// These tests live in a separate module so they don't collide with the
// producer's `mod tests` block above. They cover the specific behavior matrix
// spelled out in the B3.4 task description (one test per bullet, no overlap).
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod b3_4_tests {
    use super::*;
    use crate::core::logbook::entry::{LogCategory, LogEntry, LogLevel};
    use crate::core::logbook::paths::LogbookPaths;
    use chrono::{TimeZone, Utc};
    use std::time::{Duration, Instant};

    /// Build a writer rooted at a unique temp dir. Returns the writer and
    /// the temp path so tests can read back what was written.
    fn fresh_writer(tag: &str) -> (LogbookWriter, std::path::PathBuf) {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "riptide-logbook-b34-{}-{}",
            tag,
            Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        let _ = std::fs::remove_dir_all(&p);
        let paths = LogbookPaths::resolve(&p);
        (LogbookWriter::spawn(paths), p)
    }

    /// Wait until `path/<UTC day>.jsonl` exists, or panic. Polls every
    /// 10ms up to a 2s budget.
    async fn wait_for_file(path: &std::path::Path, day: &str) {
        let target = path.join(format!("{day}.jsonl"));
        for _ in 0..200 {
            if target.exists() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("timed out waiting for {:?}", target);
    }

    /// Wait until `path/<UTC day>.jsonl` contains at least `n` lines.
    async fn wait_for_n_lines(path: &std::path::Path, day: &str, n: usize) -> Vec<String> {
        let target = path.join(format!("{day}.jsonl"));
        for _ in 0..500 {
            if target.exists() {
                let raw = std::fs::read_to_string(&target).expect("read jsonl");
                let lines: Vec<String> = raw
                    .lines()
                    .filter(|l| !l.trim().is_empty())
                    .map(|s| s.to_string())
                    .collect();
                if lines.len() >= n {
                    return lines;
                }
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("timed out waiting for {n} lines in {:?}", target);
    }

    /// Read all non-empty lines of a JSONL file. Local re-implementation
    /// to avoid reaching across module boundaries into the producer's
    /// `mod tests` helper.
    fn read_lines(path: &std::path::Path) -> Vec<String> {
        let raw = std::fs::read_to_string(path).expect("read jsonl");
        raw.lines()
            .filter(|l| !l.trim().is_empty())
            .map(|s| s.to_string())
            .collect()
    }

    /// Wait until `path/<UTC day>.jsonl` stops growing — used after drop() to
    /// confirm the final flush has fully landed.
    async fn wait_for_size_stable(path: &std::path::Path, day: &str) -> u64 {
        let target = path.join(format!("{day}.jsonl"));
        let mut last: u64 = 0;
        let mut stable_count: u32 = 0;
        for _ in 0..200 {
            if target.exists() {
                let sz = std::fs::metadata(&target).map(|m| m.len()).unwrap_or(0);
                if sz == last && sz > 0 {
                    stable_count += 1;
                    if stable_count >= 5 {
                        return sz;
                    }
                } else {
                    stable_count = 0;
                    last = sz;
                }
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("file size never stabilised: {:?}", target);
    }

    // ── Test 1: 写一条 entry 后 JSONL 文件大小增加 ─────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_file_size_grows_after_one_entry() {
        let (writer, dir) = fresh_writer("size-grow");
        let day = writer.paths().day_string(Utc::now());
        let path = dir.join(format!("{day}.jsonl"));

        // Sanity: the file does not exist before the first write.
        assert!(!path.exists(), "file should not exist before any write");

        writer.log_info("hello", LogCategory::App);
        wait_for_file(&dir, &day).await;

        let size_after = std::fs::metadata(&path).expect("file").len();
        assert!(size_after > 0, "file size should be > 0 after one write, got {size_after}");
    }

    // ── Test 2: 多条 entry 都被持久化 ─────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_persists_all_entries() {
        let (writer, dir) = fresh_writer("persist-all");
        let n: usize = 50;
        for i in 0..n {
            writer.log_info(format!("msg-{i:03}"), LogCategory::App);
        }
        let day = writer.paths().day_string(Utc::now());
        let lines = wait_for_n_lines(&dir, &day, n).await;

        assert_eq!(lines.len(), n, "expected {n} lines, got {}", lines.len());

        // Every line must be valid JSON with the matching message.
        let mut messages: Vec<String> = lines
            .iter()
            .map(|l| serde_json::from_str::<LogEntry>(l).unwrap().message)
            .collect();
        messages.sort();
        let mut expected: Vec<String> = (0..n).map(|i| format!("msg-{i:03}")).collect();
        expected.sort();
        assert_eq!(messages, expected, "all {n} messages must be persisted");
    }

    // ── Test 3: 写完后 close() flush 完 ───────────────────────────────
    // The writer does not expose a `close()` API — drop()ing the handle
    // closes the channel and the background task drains + flushes + exits.
    // We assert that after drop, the file is final (no half-written line)
    // and contains every entry we produced.
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_drop_completes_final_flush() {
        let (writer, dir) = fresh_writer("drop-flush");
        let n: usize = 20;
        for i in 0..n {
            writer.log_info(format!("tail-{i:02}"), LogCategory::Service);
        }
        // drop the writer — its background task must drain + flush + exit.
        drop(writer);

        let day_str = LogbookPaths::resolve(&dir).day_string(Utc::now());
        let size = wait_for_size_stable(&dir, &day_str).await;

        let raw = std::fs::read_to_string(dir.join(format!("{day_str}.jsonl"))).unwrap();
        let lines: Vec<&str> = raw.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(
            lines.len(),
            n,
            "all {n} entries must be flushed after drop, got {}",
            lines.len()
        );
        // No partial last line — every line must be a valid LogEntry.
        for (idx, l) in lines.iter().enumerate() {
            let entry: LogEntry = serde_json::from_str(l)
                .unwrap_or_else(|e| panic!("line {idx} not valid JSON after drop: {e} — {l:?}"));
            assert!(entry.message.starts_with("tail-"));
        }
        assert!(size > 0, "file size must be > 0 after drop flush, got {size}");
    }

    // ── Test 4: fire-and-forget — 模拟 IO 错误不 panic ─────────────────
    // We point the writer at a path whose parent is a *regular file*. The
    // `create_dir_all` inside `flush_blocking` will then fail, the writer
    // must swallow the error (log::warn!) and the producer's calls must
    // return without blocking. The test passes if the writer never panics
    // and remains alive after the IO error.
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_swallows_io_errors_silently() {
        // Build a parent path, then place a *file* at the intermediate
        // component so `create_dir_all` on the deeper path will fail.
        let mut base = std::env::temp_dir();
        base.push(format!(
            "riptide-logbook-b34-io-{}",
            Utc::now().timestamp_nanos_opt().unwrap_or(0)
        ));
        std::fs::create_dir_all(&base).unwrap();
        let blocker = base.join("blocker.txt");
        std::fs::write(&blocker, b"i am a file, not a dir").unwrap();

        // logbook dir sits *under* a regular file ⇒ create_dir_all fails.
        let bad_dir = blocker.join("logbook");
        let paths = LogbookPaths {
            directory: bad_dir.clone(),
        };
        let writer = LogbookWriter::spawn(paths);

        // Produce a burst of entries. Each call is fire-and-forget and must
        // return immediately. The background task will repeatedly try to
        // flush and fail; we just make sure we don't panic.
        for i in 0..32 {
            writer.log_info(format!("io-fail-{i}"), LogCategory::App);
        }

        // Give the background task a chance to attempt (and fail) the flush.
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(writer.is_alive(), "writer must remain alive after IO error");

        // The bad dir must not have been created.
        assert!(!bad_dir.exists(), "bad dir must not exist after IO failure");

        // Producer side is non-blocking: time a single send.
        let t0 = Instant::now();
        writer.log_warning("after-failure", LogCategory::App);
        assert!(
            t0.elapsed() < Duration::from_millis(5),
            "log_warning must be fire-and-forget, took {:?}",
            t0.elapsed()
        );

        drop(writer);
        let _ = std::fs::remove_dir_all(&base);
    }

    // ── Test 5: 50ms batch flush 触发 ─────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_batch_flush_triggers_within_window() {
        let (writer, dir) = fresh_writer("flush-50ms");
        let day = writer.paths().day_string(Utc::now());
        let target = dir.join(format!("{day}.jsonl"));

        let t0 = Instant::now();
        writer.log_info("first-and-only", LogCategory::App);
        // Wait up to FLUSH_INTERVAL + generous slack (5x = 250ms).
        let mut appeared_in: Option<Duration> = None;
        for _ in 0..50 {
            if target.exists() {
                let sz = std::fs::metadata(&target).map(|m| m.len()).unwrap_or(0);
                if sz > 0 {
                    appeared_in = Some(t0.elapsed());
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        let elapsed = appeared_in.expect("file must appear within 500ms of write");
        // Bound: 50ms interval + scheduling slack. 500ms is comfortable.
        assert!(
            elapsed < Duration::from_millis(500),
            "batch flush took too long: {:?}",
            elapsed
        );
        // Sanity: the bound is also non-trivially larger than 0.
        assert!(
            elapsed >= Duration::from_millis(10),
            "batch flush must take at least the interval, got {:?}",
            elapsed
        );
    }

    // ── Test 6: 同一天的 entry 进同一个文件 ────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_same_day_entries_share_one_file() {
        let (writer, dir) = fresh_writer("same-day");
        // Use the explicit timestamp constructor so all three entries land
        // on 2026-06-05 regardless of the host clock.
        let ts = Utc.with_ymd_and_hms(2026, 6, 5, 8, 30, 0).unwrap();
        for i in 0..3 {
            let entry = LogEntry::with_timestamp(ts, LogLevel::Info, LogCategory::App, format!("sd-{i}"));
            writer.send(entry);
        }

        let day = "2026-06-05";
        wait_for_n_lines(&dir, day, 3).await;

        let files: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".jsonl"))
            .collect();
        assert_eq!(files.len(), 1, "same-day entries must share one file, got {files:?}");
        assert_eq!(files[0], "2026-06-05.jsonl");
    }

    // ── Test 7: 跨天的 entry 切换文件 ─────────────────────────────────
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_cross_day_entries_split_into_files() {
        let (writer, dir) = fresh_writer("cross-day");
        // Three timestamps, two distinct UTC days.
        let d1 = Utc.with_ymd_and_hms(2026, 6, 5, 23, 59, 0).unwrap();
        let d2 = Utc.with_ymd_and_hms(2026, 6, 6, 0, 0, 1).unwrap();
        let d3 = Utc.with_ymd_and_hms(2026, 6, 6, 12, 0, 0).unwrap();
        writer.send(LogEntry::with_timestamp(d1, LogLevel::Info, LogCategory::App, "d1-a"));
        writer.send(LogEntry::with_timestamp(d2, LogLevel::Info, LogCategory::App, "d2-a"));
        writer.send(LogEntry::with_timestamp(d3, LogLevel::Info, LogCategory::App, "d2-b"));

        wait_for_n_lines(&dir, "2026-06-05", 1).await;
        wait_for_n_lines(&dir, "2026-06-06", 2).await;

        let files: std::collections::BTreeSet<String> = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().to_string())
            .filter(|n| n.ends_with(".jsonl"))
            .collect();
        assert_eq!(
            files,
            ["2026-06-05.jsonl".to_string(), "2026-06-06.jsonl".to_string()]
                .into_iter()
                .collect()
        );

        // Spot-check the contents per file.
        let d1_lines = read_lines(&dir.join("2026-06-05.jsonl"));
        assert_eq!(d1_lines.len(), 1);
        assert!(d1_lines[0].contains("d1-a"));

        let d2_lines = read_lines(&dir.join("2026-06-06.jsonl"));
        assert_eq!(d2_lines.len(), 2);
        let d2_msgs: Vec<String> = d2_lines
            .iter()
            .map(|l| serde_json::from_str::<LogEntry>(l).unwrap().message)
            .collect();
        assert!(d2_msgs.contains(&"d2-a".to_string()));
        assert!(d2_msgs.contains(&"d2-b".to_string()));
    }

    // ── Test 8: malformed JSON 不会让 writer 死锁 ─────────────────────
    // The writer is append-only and never reads. A garbage line in the file
    // (e.g. from a hand-edit or a process crash mid-flush) must not stop
    // the writer from continuing to write more valid entries.
    #[tokio::test(flavor = "current_thread")]
    async fn b3_4_writer_recovers_from_malformed_json() {
        let (writer, dir) = fresh_writer("malformed");
        let day = writer.paths().day_string(Utc::now());
        let target = dir.join(format!("{day}.jsonl"));

        // 1) write two good entries
        writer.log_info("good-1", LogCategory::App);
        writer.log_info("good-2", LogCategory::App);
        wait_for_n_lines(&dir, &day, 2).await;

        // 2) inject garbage directly into the on-disk file
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(&target)
            .expect("open for append");
        f.write_all(b"this is not json at all\n{\"ts\":\"broken\n").expect("write garbage");
        f.flush().expect("flush garbage");
        drop(f);

        // 3) write more good entries — writer must not deadlock, panic, or skip
        for i in 0..5 {
            writer.log_info(format!("after-garbage-{i}"), LogCategory::App);
        }

        // The on-disk file should now contain 2 + 1 garbage + 1 broken + 5 good
        // entries (the garbage lines are bytes; the writer doesn't touch them).
        // We poll until the 5 trailing good entries have all landed.
        let mut good_after: usize = 0;
        for _ in 0..200 {
            let raw = std::fs::read_to_string(&target).expect("read");
            good_after = raw
                .lines()
                .filter(|l| l.contains("after-garbage-"))
                .count();
            if good_after >= 5 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(
            good_after, 5,
            "writer must keep producing after malformed JSON injection, got {good_after}"
        );

        // 4) drop the writer and confirm the final file still contains both
        //    original good entries (the writer never reads or rewrites).
        drop(writer);
        let raw = std::fs::read_to_string(&target).expect("read final");
        assert!(raw.contains("good-1"));
        assert!(raw.contains("good-2"));
        assert!(raw.contains("this is not json at all"));
    }
}

