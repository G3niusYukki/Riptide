//! Rule management

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    pub rule_type: String,
    pub value: String,
    pub policy: String,
}

impl Rule {
    pub fn new(rule_type: String, value: String, policy: String) -> Self {
        Self {
            rule_type,
            value,
            policy,
        }
    }

    /// Parse rule from string (e.g., "DOMAIN,google.com,DIRECT")
    pub fn parse(rule_str: &str) -> Result<Self, String> {
        let parts: Vec<&str> = rule_str.split(',').collect();
        if parts.len() < 3 {
            return Err("Invalid rule format".to_string());
        }

        Ok(Self::new(
            parts[0].to_string(),
            parts[1].to_string(),
            parts[2].to_string(),
        ))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleSet {
    pub name: String,
    pub rules: Vec<Rule>,
}
