//! On-disk shape of a single Logbook entry.
//!
//! One JSON object per line in a daily `YYYY-MM-DD.jsonl` file:
//!
//! ```text
//! {"ts":"2026-06-05T22:00:00.123Z","level":"info","category":"mode",
//!  "message":"switched to system_proxy","fields":{"from":"off"}}
//! ```
//!
//! `fields` is intentionally `BTreeMap<String, String>` (not `HashMap`) so the
//! serialized line is byte-stable: tests that diff the on-disk file don't
//! have to absorb hash-randomized key order.

use std::collections::BTreeMap;

use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};

/// Severity of a single logbook event.
///
/// Serialized lowercase to match the macOS shape (`"info" | "warning" | "error"`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    Info,
    Warning,
    Error,
}

impl LogLevel {
    /// Lowercase string form. Useful for log filter URLs / debug prints.
    pub fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Info => "info",
            LogLevel::Warning => "warning",
            LogLevel::Error => "error",
        }
    }

    /// Parse the lowercase form. Returns `None` for unknown strings.
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "info" => Some(LogLevel::Info),
            "warning" | "warn" => Some(LogLevel::Warning),
            "error" | "err" => Some(LogLevel::Error),
            _ => None,
        }
    }
}

/// Tag attached to every entry. Used by the store to filter and by the UI to
/// colour-code. The first ten values mirror the macOS module; the last three
/// (`Service`, `Sysproxy`, `Recovery`) are Windows-specific and have no
/// macOS counterpart yet.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LogCategory {
    #[serde(rename = "mode")]
    Mode,
    #[serde(rename = "subscription")]
    Subscription,
    #[serde(rename = "profile")]
    Profile,
    #[serde(rename = "helper")]
    Helper,
    #[serde(rename = "mihomo")]
    Mihomo,
    #[serde(rename = "override")]
    Override,
    #[serde(rename = "rule")]
    Rule,
    #[serde(rename = "dns")]
    Dns,
    #[serde(rename = "diagnostic")]
    Diagnostic,
    #[serde(rename = "app")]
    App,
    #[serde(rename = "service")]
    Service,
    #[serde(rename = "sysproxy")]
    Sysproxy,
    #[serde(rename = "recovery")]
    Recovery,
}

impl LogCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            LogCategory::Mode => "mode",
            LogCategory::Subscription => "subscription",
            LogCategory::Profile => "profile",
            LogCategory::Helper => "helper",
            LogCategory::Mihomo => "mihomo",
            LogCategory::Override => "override",
            LogCategory::Rule => "rule",
            LogCategory::Dns => "dns",
            LogCategory::Diagnostic => "diagnostic",
            LogCategory::App => "app",
            LogCategory::Service => "service",
            LogCategory::Sysproxy => "sysproxy",
            LogCategory::Recovery => "recovery",
        }
    }

    /// Parse the wire format. Returns `None` for unknown strings — used by the
    /// `logbook_query` / `logbook_clear` Tauri commands to accept the category
    /// as a plain string from the JS layer.
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "mode" => Some(LogCategory::Mode),
            "subscription" | "sub" => Some(LogCategory::Subscription),
            "profile" => Some(LogCategory::Profile),
            "helper" | "service_install" => Some(LogCategory::Helper),
            "mihomo" | "core" => Some(LogCategory::Mihomo),
            "override" => Some(LogCategory::Override),
            "rule" => Some(LogCategory::Rule),
            "dns" => Some(LogCategory::Dns),
            "diagnostic" | "diagnostics" => Some(LogCategory::Diagnostic),
            "app" | "lifecycle" => Some(LogCategory::App),
            "service" => Some(LogCategory::Service),
            "sysproxy" | "system_proxy" => Some(LogCategory::Sysproxy),
            "recovery" | "watchdog" => Some(LogCategory::Recovery),
            _ => None,
        }
    }
}

/// A single logbook event.
///
/// `ts` is a pre-formatted ISO 8601 string in UTC with millisecond precision
/// and a trailing `Z`. We don't store a `DateTime<Utc>` here because (a) the
/// on-disk format is text and (b) the macOS reference uses the same approach,
/// which keeps cross-platform tooling trivial.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LogEntry {
    pub ts: String,
    pub level: LogLevel,
    pub category: LogCategory,
    pub message: String,
    #[serde(default)]
    pub fields: BTreeMap<String, String>,
}

impl LogEntry {
    /// Build a new entry stamped with the current UTC time.
    pub fn new(level: LogLevel, category: LogCategory, message: impl Into<String>) -> Self {
        let ts = Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true);
        Self {
            ts,
            level,
            category,
            message: message.into(),
            fields: BTreeMap::new(),
        }
    }

    /// Build a new entry stamped with a specific UTC time. Used by tests and
    /// by the query-then-replay path inside `LogbookStore::export`.
    pub fn with_timestamp(
        ts: DateTime<Utc>,
        level: LogLevel,
        category: LogCategory,
        message: impl Into<String>,
    ) -> Self {
        Self {
            ts: ts.to_rfc3339_opts(SecondsFormat::Millis, true),
            level,
            category,
            message: message.into(),
            fields: BTreeMap::new(),
        }
    }

    /// Insert a single key/value pair into `fields`. Returns `self` for
    /// chaining in the same expression that constructs the entry.
    pub fn with_field(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.fields.insert(key.into(), value.into());
        self
    }

    /// Insert a batch of key/value pairs. Existing keys in `fields` win —
    /// this matches the `extend` semantics and avoids accidental overwrites
    /// when chaining `.with_field()` after `.with_fields()`.
    pub fn with_fields(mut self, extra: BTreeMap<String, String>) -> Self {
        for (k, v) in extra {
            self.fields.entry(k).or_insert(v);
        }
        self
    }

    /// Re-parse `ts` back into a `DateTime<Utc>`. Returns `None` for entries
    /// that were hand-crafted with a non-RFC3339 timestamp — callers that
    /// need to filter by time should treat `None` as "outside range".
    pub fn timestamp(&self) -> Option<DateTime<Utc>> {
        DateTime::parse_from_rfc3339(&self.ts)
            .ok()
            .map(|d| d.with_timezone(&Utc))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn level_serializes_lowercase() {
        let json = serde_json::to_string(&LogLevel::Warning).unwrap();
        assert_eq!(json, "\"warning\"");
    }

    #[test]
    fn level_round_trips() {
        for level in [LogLevel::Info, LogLevel::Warning, LogLevel::Error] {
            let json = serde_json::to_string(&level).unwrap();
            let back: LogLevel = serde_json::from_str(&json).unwrap();
            assert_eq!(back, level);
        }
    }

    #[test]
    fn level_parse_accepts_aliases() {
        assert_eq!(LogLevel::parse("INFO").unwrap(), LogLevel::Info);
        assert_eq!(LogLevel::parse("warn").unwrap(), LogLevel::Warning);
        assert_eq!(LogLevel::parse("Err").unwrap(), LogLevel::Error);
        assert!(LogLevel::parse("debug").is_none());
    }

    #[test]
    fn category_round_trips() {
        for cat in [
            LogCategory::Mode,
            LogCategory::Subscription,
            LogCategory::Profile,
            LogCategory::Helper,
            LogCategory::Mihomo,
            LogCategory::Override,
            LogCategory::Rule,
            LogCategory::Dns,
            LogCategory::Diagnostic,
            LogCategory::App,
            LogCategory::Service,
            LogCategory::Sysproxy,
            LogCategory::Recovery,
        ] {
            let json = serde_json::to_string(&cat).unwrap();
            let back: LogCategory = serde_json::from_str(&json).unwrap();
            assert_eq!(back, cat);
        }
    }

    #[test]
    fn entry_new_stamps_recent_utc_timestamp() {
        let before = Utc::now();
        let entry = LogEntry::new(LogLevel::Info, LogCategory::Mode, "hello");
        let after = Utc::now();
        let ts = entry.timestamp().expect("ts parses");
        // millisecond precision can floor, so allow a 1ms slack on the
        // "before" bound.
        assert!(ts >= before - chrono::Duration::milliseconds(1));
        assert!(ts <= after);
    }

    #[test]
    fn entry_with_field_is_chainable() {
        let entry = LogEntry::new(LogLevel::Error, LogCategory::Service, "x")
            .with_field("attempt", "3")
            .with_field("op", "install");
        assert_eq!(entry.fields.get("attempt").map(String::as_str), Some("3"));
        assert_eq!(entry.fields.get("op").map(String::as_str), Some("install"));
    }

    #[test]
    fn entry_with_fields_does_not_overwrite_existing_keys() {
        let mut existing = BTreeMap::new();
        existing.insert("k".into(), "first".into());
        let mut extra = BTreeMap::new();
        extra.insert("k".into(), "second".into());
        extra.insert("n".into(), "new".into());

        let entry = LogEntry::new(LogLevel::Info, LogCategory::App, "x")
            .with_fields(existing)
            .with_fields(extra);

        assert_eq!(entry.fields.get("k").unwrap(), "first");
        assert_eq!(entry.fields.get("n").unwrap(), "new");
    }

    #[test]
    fn entry_serializes_with_empty_fields_object() {
        let entry = LogEntry::new(LogLevel::Info, LogCategory::App, "boot");
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"fields\":{}"));
    }

    #[test]
    fn entry_deserializes_skips_missing_fields() {
        // `fields` defaults to empty BTreeMap when omitted.
        let json =
            r#"{"ts":"2026-06-05T22:00:00.123Z","level":"info","category":"app","message":"x"}"#;
        let entry: LogEntry = serde_json::from_str(json).unwrap();
        assert!(entry.fields.is_empty());
    }
}
