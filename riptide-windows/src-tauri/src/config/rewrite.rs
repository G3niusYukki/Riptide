//! HTTP Rewrite rules engine.
//!
//! Persisted to `%APPDATA%\Riptide\rewrite_rules.json`.
//! Format is Surge-compatible: URL regex → REJECT / REDIRECT / HEADER-MODIFY.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

const REWRITE_RULES_FILENAME: &str = "rewrite_rules.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RewriteRule {
    pub id: String,
    pub pattern: String,
    pub action: RewriteAction,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum RewriteAction {
    Reject,
    Redirect(String),
    #[serde(rename = "ModifyHeader")]
    ModifyHeader { key: String, value: String },
    #[serde(rename = "ModifyResponseHeader")]
    ModifyResponseHeader { key: String, value: String },
}

fn path() -> PathBuf {
    crate::utils::windows_dirs::WindowsDirs::config_dir().join(REWRITE_RULES_FILENAME)
}

pub fn load_rules() -> Vec<RewriteRule> {
    match fs::read_to_string(path()) {
        Ok(content) => serde_json::from_str(&content).unwrap_or_default(),
        Err(_) => vec![],
    }
}

pub fn save_rules(rules: &[RewriteRule]) -> Result<(), String> {
    let p = path();
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir: {}", e))?;
    }
    let json = serde_json::to_string_pretty(rules).map_err(|e| e.to_string())?;
    let tmp = p.with_extension("json.tmp");
    fs::write(&tmp, json).map_err(|e| e.to_string())?;
    fs::rename(&tmp, &p).map_err(|e| e.to_string())?;
    Ok(())
}
