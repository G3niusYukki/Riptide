//! Profile management

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub content: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Profile {
    pub fn new(name: String, content: String) -> Self {
        let id = uuid::Uuid::new_v4().to_string();
        let now = Utc::now();

        Self {
            id,
            name,
            content,
            created_at: now,
            updated_at: now,
        }
    }

    /// Parse YAML content to verify validity
    pub fn validate(&self) -> Result<(), String> {
        // TODO: Implement YAML validation
        Ok(())
    }

    /// Get proxies from profile
    pub fn get_proxies(&self) -> Vec<Proxy> {
        // TODO: Parse YAML and extract proxies
        Vec::new()
    }

    /// Get proxy groups from profile
    pub fn get_proxy_groups(&self) -> Vec<ProxyGroup> {
        // TODO: Parse YAML and extract proxy groups
        Vec::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Proxy {
    pub name: String,
    pub server: String,
    pub port: u16,
    pub proxy_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyGroup {
    pub name: String,
    pub group_type: String, // select, url-test, fallback, load-balance
    pub proxies: Vec<String>,
    pub url: Option<String>,
    pub interval: Option<u32>,
}
