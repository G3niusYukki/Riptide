//! HTTP Rewrite rules engine.
//!
//! Persisted to `%APPDATA%\Riptide\rewrite_rules.json`.
//! Rules are applied to HTTP requests (plaintext) in the proxy path.
//! Format is Surge-compatible: URL regex → REJECT / REDIRECT / HEADER-MODIFY.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::utils::dirs;

const REWRITE_RULES_FILENAME: &str = "rewrite_rules.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RewriteRule {
    pub id: String,
    /// Regex pattern for URL matching.
    pub pattern: String,
    /// Action to apply when matched.
    pub action: RewriteAction,
    /// Whether this rule is active.
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "value")]
pub enum RewriteAction {
    /// Block the request (return 403).
    Reject,
    /// Redirect to a different URL.
    Redirect(String),
    /// Modify a request header.
    ModifyHeader { key: String, value: String },
    /// Modify a response header.
    ModifyResponseHeader { key: String, value: String },
}

/// Load rewrite rules from disk. Returns empty vec if file doesn't exist.
pub fn load_rewrite_rules() -> Vec<RewriteRule> {
    let path = rewrite_rules_path();
    match fs::read_to_string(&path) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => vec![],
    }
}

/// Save rewrite rules to disk.
pub fn save_rewrite_rules(rules: &[RewriteRule]) -> std::io::Result<()> {
    let path = rewrite_rules_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(rules)?;
    fs::write(path, json)
}

fn rewrite_rules_path() -> PathBuf {
    dirs::app_data_dir().join(REWRITE_RULES_FILENAME)
}
