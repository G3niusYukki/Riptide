//! Tauri commands for HTTP rewrite rules management.

use tauri::command;
use crate::config::rewrite::{self, RewriteRule};

#[command]
pub fn get_rewrite_rules() -> Vec<RewriteRule> {
    rewrite::load_rules()
}

#[command]
pub fn set_rewrite_rules(rules: Vec<RewriteRule>) -> Result<(), String> {
    rewrite::save_rules(&rules)
}

#[command]
pub fn add_rewrite_rule(rule: RewriteRule) -> Result<(), String> {
    let mut rules = rewrite::load_rules();
    rules.push(rule);
    rewrite::save_rules(&rules)
}

#[command]
pub fn delete_rewrite_rule(id: String) -> Result<(), String> {
    let mut rules = rewrite::load_rules();
    rules.retain(|r| r.id != id);
    rewrite::save_rules(&rules)
}

#[command]
pub fn toggle_rewrite_rule(id: String, enabled: bool) -> Result<(), String> {
    let mut rules = rewrite::load_rules();
    if let Some(rule) = rules.iter_mut().find(|r| r.id == id) {
        rule.enabled = enabled;
    }
    rewrite::save_rules(&rules)
}
