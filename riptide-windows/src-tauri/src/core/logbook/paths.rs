//! Resolves on-disk locations for the diagnostic Logbook.
//!
//! Files are partitioned by UTC day under `directory` as `YYYY-MM-DD.jsonl`
//! (one JSON object per line). The default Windows root is
//! `%APPDATA%\Riptide\logbook\`, which matches `WindowsDirs::config_dir()`.

use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};

/// Resolves on-disk locations for the daily Logbook JSONL files.
#[derive(Debug, Clone)]
pub struct LogbookPaths {
    /// Directory holding daily `*.jsonl` files. Created on demand by
    /// [`create_dir_if_needed`](Self::create_dir_if_needed).
    pub directory: PathBuf,
}

impl LogbookPaths {
    /// Build paths rooted at `<base>/logbook`. Used by tests and by the
    /// service binary (`riptide-tun-service.exe`), which can't depend on
    /// the Tauri app handle.
    pub fn resolve(base: &Path) -> Self {
        Self {
            directory: base.join("logbook"),
        }
    }

    /// The canonical location: `%APPDATA%\Riptide\logbook\` on Windows.
    ///
    /// On non-Windows hosts (e.g. CI on Linux) this still resolves to a
    /// `Riptide/logbook` directory under `WindowsDirs::config_dir()` —
    /// which uses `$XDG_CONFIG_HOME/riptide` on Linux. The intent is
    /// "the user-config dir, whatever it is" so the local dev loop
    /// works the same as a Windows install.
    pub fn default_windows() -> Self {
        let base = crate::utils::windows_dirs::WindowsDirs::config_dir();
        Self::resolve(&base)
    }

    /// Create `directory` (and any missing parents) if it does not exist.
    /// Safe to call repeatedly.
    pub fn create_dir_if_needed(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.directory)
    }

    /// Path of the JSONL file for the UTC day containing `date`.
    pub fn file_path(&self, date: DateTime<Utc>) -> PathBuf {
        self.directory
            .join(format!("{}.jsonl", self.day_string(date)))
    }

    /// Stable `YYYY-MM-DD` string for `date` (always UTC). Used both for
    /// the on-disk filename and for the per-day date filter inside
    /// `LogbookStore::query`.
    pub fn day_string(&self, date: DateTime<Utc>) -> String {
        date.format("%Y-%m-%d").to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn resolve_appends_logbook_subdir() {
        let base = PathBuf::from("/tmp/riptide-test");
        let paths = LogbookPaths::resolve(&base);
        assert_eq!(paths.directory, base.join("logbook"));
    }

    #[test]
    fn file_path_uses_utc_day() {
        let paths = LogbookPaths::resolve(Path::new("/tmp/x"));
        // 2026-06-05T22:00:00Z is on 2026-06-05 UTC.
        let ts = Utc.with_ymd_and_hms(2026, 6, 5, 22, 0, 0).unwrap();
        assert_eq!(
            paths.file_path(ts),
            PathBuf::from("/tmp/x/logbook/2026-06-05.jsonl")
        );
    }

    #[test]
    fn day_string_is_zero_padded() {
        let paths = LogbookPaths::resolve(Path::new("/tmp/x"));
        let ts = Utc.with_ymd_and_hms(2026, 1, 9, 0, 0, 0).unwrap();
        assert_eq!(paths.day_string(ts), "2026-01-09");
    }

    #[test]
    fn default_windows_contains_logbook_subdir() {
        let paths = LogbookPaths::default_windows();
        let s = paths.directory.to_string_lossy();
        assert!(
            s.contains("logbook"),
            "default_windows should produce a path ending in /logbook, got {s}"
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// B3.4 QA tests (task: B3 — Logbook 17 个 Rust 测试(writer 8 + store 6 + paths 3))
//
// Three tests, one per bullet in the task description:
//   1. file_path  (the B3 description called it `paths_for_date`)
//      produces YYYY-MM-DD.jsonl
//   2. 跨月 / 跨年文件名正确
//   3. 路径用 WindowsDirs 验证
// ─────────────────────────────────────────────────────────────────────────────
#[cfg(test)]
mod b3_4_tests {
    use super::*;
    use crate::utils::windows_dirs::WindowsDirs;
    use chrono::TimeZone;

    // ── Test 1: paths_for_date 生成 YYYY-MM-DD.jsonl ───────────────────
    // The Rust API exposes `file_path(date)`; the task description
    // referred to the same operation as `paths_for_date`. This test
    // confirms the filename shape and extension.
    #[test]
    fn b3_4_file_path_uses_yyyy_mm_dd_jsonl() {
        let base = std::path::PathBuf::from("/tmp/riptide-b34-paths");
        let paths = LogbookPaths::resolve(&base);

        // Mid-month, mid-year date.
        let ts = Utc.with_ymd_and_hms(2026, 6, 5, 22, 0, 0).unwrap();
        let p = paths.file_path(ts);
        assert_eq!(
            p.file_name().and_then(|s| s.to_str()),
            Some("2026-06-05.jsonl"),
            "expected YYYY-MM-DD.jsonl filename, got {:?}",
            p.file_name()
        );

        // The path must also be inside the logbook sub-directory of `base`.
        assert_eq!(p.parent(), Some(base.join("logbook").as_path()));
    }

    // ── Test 2: 跨月 / 跨年文件名正确 ──────────────────────────────────
    #[test]
    fn b3_4_file_path_handles_month_and_year_rollover() {
        let base = std::path::PathBuf::from("/tmp/riptide-b34-paths-rollover");
        let paths = LogbookPaths::resolve(&base);

        // 1) Cross-month: May 31 → June 1
        let may31 = Utc.with_ymd_and_hms(2026, 5, 31, 23, 59, 59).unwrap();
        let jun01 = Utc.with_ymd_and_hms(2026, 6, 1, 0, 0, 1).unwrap();
        assert_eq!(
            paths.file_path(may31).file_name().and_then(|s| s.to_str()),
            Some("2026-05-31.jsonl")
        );
        assert_eq!(
            paths.file_path(jun01).file_name().and_then(|s| s.to_str()),
            Some("2026-06-01.jsonl")
        );

        // 2) Cross-year: Dec 31 → Jan 1
        let dec31 = Utc.with_ymd_and_hms(2025, 12, 31, 23, 59, 59).unwrap();
        let jan01 = Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 1).unwrap();
        assert_eq!(
            paths.file_path(dec31).file_name().and_then(|s| s.to_str()),
            Some("2025-12-31.jsonl")
        );
        assert_eq!(
            paths.file_path(jan01).file_name().and_then(|s| s.to_str()),
            Some("2026-01-01.jsonl")
        );

        // 3) Leap-day sanity (2024 is a leap year; 2026 is not).
        let leap = Utc.with_ymd_and_hms(2024, 2, 29, 12, 0, 0).unwrap();
        let non_leap_feb = Utc.with_ymd_and_hms(2026, 2, 28, 12, 0, 0).unwrap();
        assert_eq!(
            paths.file_path(leap).file_name().and_then(|s| s.to_str()),
            Some("2024-02-29.jsonl")
        );
        assert_eq!(
            paths
                .file_path(non_leap_feb)
                .file_name()
                .and_then(|s| s.to_str()),
            Some("2026-02-28.jsonl")
        );
    }

    // ── Test 3: 路径用 WindowsDirs 验证 ────────────────────────────────
    #[test]
    fn b3_4_default_windows_path_uses_windows_dirs() {
        let paths = LogbookPaths::default_windows();
        let config_dir = WindowsDirs::config_dir();

        // 1) The default_windows path must be a sub-path of
        //    WindowsDirs::config_dir() (i.e. it lives under the app data
        //    root — the same root every other persisted module uses).
        assert!(
            paths.directory.starts_with(&config_dir),
            "default_windows path {:?} must start with WindowsDirs::config_dir() {:?}",
            paths.directory,
            config_dir
        );

        // 2) The default_windows path must end with the `logbook` segment.
        assert_eq!(
            paths.directory.file_name().and_then(|s| s.to_str()),
            Some("logbook"),
            "default_windows path must end in /logbook, got {:?}",
            paths.directory
        );

        // 3) The path must use forward- or back-slash separators; on Windows
        //    we expect a PathBuf whose components include "Riptide" + "logbook".
        let components: Vec<String> = paths
            .directory
            .components()
            .map(|c| c.as_os_str().to_string_lossy().to_string())
            .collect();
        assert!(
            components.contains(&"Riptide".to_string()),
            "default_windows path must contain a 'Riptide' segment, got {components:?}"
        );
        assert!(
            components.contains(&"logbook".to_string()),
            "default_windows path must contain a 'logbook' segment, got {components:?}"
        );
    }
}
