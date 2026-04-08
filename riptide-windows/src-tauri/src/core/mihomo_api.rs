//! Mihomo REST API client
//! 
//! Provides async access to mihomo's REST API endpoints on port 9090
//! Reference: https://github.com/MetaCubeX/mihomo/blob/master/docs/api.md

use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

const DEFAULT_API_URL: &str = "http://127.0.0.1:9090";
const DEFAULT_TEST_URL: &str = "http://www.gstatic.com/generate_204";
const DEFAULT_TIMEOUT_MS: u32 = 5000;

/// Errors that can occur when calling the mihomo API
#[derive(Debug, thiserror::Error)]
pub enum MihomoError {
    #[error("HTTP request failed: {0}")]
    RequestFailed(#[from] reqwest::Error),
    
    #[error("API error: {message} (status: {status})")]
    ApiError { status: StatusCode, message: String },
    
    #[error("Proxy '{name}' not found")]
    ProxyNotFound { name: String },
    
    #[error("Connection '{id}' not found")]
    ConnectionNotFound { id: String },
    
    #[error("Invalid response format: {0}")]
    InvalidResponse(String),
}

/// Proxy information from mihomo API
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProxyInfo {
    pub name: String,
    #[serde(rename = "type")]
    pub proxy_type: String,
    pub alive: Option<bool>,
    pub delay: Option<u32>,
    pub history: Option<Vec<DelayHistory>>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DelayHistory {
    pub time: String,
    pub delay: u32,
}

/// Proxy group information
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProxyGroupDetail {
    pub name: String,
    #[serde(rename = "type")]
    pub group_type: String,
    pub proxies: Vec<String>,
    pub now: Option<String>,
    pub url: Option<String>,
    pub interval: Option<u32>,
    pub tolerance: Option<u32>,
    pub delay: Option<u32>,
}

/// Connection metadata
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ConnectionMetadata {
    pub network: String,
    #[serde(rename = "type")]
    pub connection_type: String,
    #[serde(rename = "sourceIP")]
    pub source_ip: String,
    #[serde(rename = "destinationIP")]
    pub destination_ip: Option<String>,
    pub host: Option<String>,
    #[serde(rename = "sourcePort")]
    pub source_port: String,
    #[serde(rename = "destinationPort")]
    pub destination_port: String,
}

/// Active connection information
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ConnectionInfo {
    pub id: String,
    pub metadata: ConnectionMetadata,
    pub upload: u64,
    pub download: u64,
    pub start: String,
    pub chains: Vec<String>,
    pub rule: Option<String>,
}

/// Traffic statistics
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TrafficData {
    pub up: u64,
    pub down: u64,
}

/// Version information
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct VersionInfo {
    pub version: String,
    #[serde(rename = "premium")]
    pub is_premium: Option<bool>,
}

/// Request body for switching proxy
#[derive(Debug, Serialize)]
struct SwitchProxyRequest {
    name: String,
}

/// Response wrapper for proxies endpoint
#[derive(Debug, Deserialize)]
struct ProxiesResponse {
    proxies: HashMap<String, serde_json::Value>,
}

/// Response wrapper for connections endpoint
#[derive(Debug, Deserialize)]
struct ConnectionsResponse {
    connections: Vec<ConnectionInfo>,
}

/// Mihomo API client
#[derive(Debug, Clone)]
pub struct MihomoApiClient {
    client: Client,
    base_url: String,
    secret: Option<String>,
}

impl MihomoApiClient {
    /// Create a new API client
    pub fn new(base_url: impl Into<String>, secret: Option<String>) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.into(),
            secret,
        }
    }

    /// Create client with default URL
    pub fn default_with_secret(secret: Option<String>) -> Self {
        Self::new(DEFAULT_API_URL, secret)
    }

    /// Build request with optional secret header
    fn build_request(&self, method: reqwest::Method, path: &str) -> reqwest::RequestBuilder {
        let url = format!("{}{}", self.base_url, path);
        let mut request = self.client.request(method, &url);
        
        if let Some(secret) = &self.secret {
            request = request.header("Authorization", format!("Bearer {}", secret));
        }
        
        request
    }

    /// Check if mihomo API is healthy
    pub async fn health_check(&self) -> Result<bool, MihomoError> {
        match self.client.get(format!("{}/version", self.base_url)).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    /// Get mihomo version
    pub async fn get_version(&self) -> Result<VersionInfo, MihomoError> {
        let response = self.build_request(reqwest::Method::GET, "/version")
            .send()
            .await?;
        
        if response.status().is_success() {
            let version = response.json().await?;
            Ok(version)
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Get all proxies (including groups)
    pub async fn get_proxies(&self) -> Result<HashMap<String, ProxyInfo>, MihomoError> {
        let response = self.build_request(reqwest::Method::GET, "/proxies")
            .send()
            .await?;
        
        if response.status().is_success() {
            let data: ProxiesResponse = response.json().await?;
            
            // Convert JSON values to ProxyInfo
            let mut proxies = HashMap::new();
            for (name, value) in data.proxies {
                let proxy_info: ProxyInfo = serde_json::from_value(value)
                    .map_err(|e| MihomoError::InvalidResponse(e.to_string()))?;
                proxies.insert(name, proxy_info);
            }
            
            Ok(proxies)
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Get specific proxy info
    pub async fn get_proxy(&self, name: &str) -> Result<ProxyInfo, MihomoError> {
        let path = format!("/proxies/{}", urlencoding::encode(name));
        let response = self.build_request(reqwest::Method::GET, &path)
            .send()
            .await?;
        
        if response.status().is_success() {
            let proxy = response.json().await?;
            Ok(proxy)
        } else if response.status() == StatusCode::NOT_FOUND {
            Err(MihomoError::ProxyNotFound { name: name.to_string() })
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Test proxy delay
    pub async fn test_proxy_delay(
        &self,
        name: &str,
        url: Option<&str>,
        timeout_ms: Option<u32>,
    ) -> Result<u32, MihomoError> {
        let path = format!("/proxies/{}/delay", urlencoding::encode(name));
        let test_url = url.unwrap_or(DEFAULT_TEST_URL);
        let timeout = timeout_ms.unwrap_or(DEFAULT_TIMEOUT_MS);
        
        let response = self.build_request(reqwest::Method::GET, &path)
            .query(&[("url", test_url), ("timeout", &timeout.to_string())])
            .send()
            .await?;
        
        if response.status().is_success() {
            #[derive(Deserialize)]
            struct DelayResponse {
                delay: u32,
            }
            let data: DelayResponse = response.json().await?;
            Ok(data.delay)
        } else if response.status() == StatusCode::NOT_FOUND {
            Err(MihomoError::ProxyNotFound { name: name.to_string() })
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Switch proxy in a group
    pub async fn switch_proxy(&self, group: &str, proxy_name: &str) -> Result<(), MihomoError> {
        let path = format!("/proxies/{}", urlencoding::encode(group));
        let body = SwitchProxyRequest {
            name: proxy_name.to_string(),
        };
        
        let response = self.build_request(reqwest::Method::PUT, &path)
            .json(&body)
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(())
        } else if response.status() == StatusCode::NOT_FOUND {
            Err(MihomoError::ProxyNotFound { name: group.to_string() })
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Get all active connections
    pub async fn get_connections(&self) -> Result<Vec<ConnectionInfo>, MihomoError> {
        let response = self.build_request(reqwest::Method::GET, "/connections")
            .send()
            .await?;
        
        if response.status().is_success() {
            let data: ConnectionsResponse = response.json().await?;
            Ok(data.connections)
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Close a specific connection
    pub async fn close_connection(&self, id: &str) -> Result<(), MihomoError> {
        let path = format!("/connections/{}", urlencoding::encode(id));
        let response = self.build_request(reqwest::Method::DELETE, &path)
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(())
        } else if response.status() == StatusCode::NOT_FOUND {
            Err(MihomoError::ConnectionNotFound { id: id.to_string() })
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Close all connections
    pub async fn close_all_connections(&self) -> Result<(), MihomoError> {
        let response = self.build_request(reqwest::Method::DELETE, "/connections")
            .send()
            .await?;
        
        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Get traffic statistics
    pub async fn get_traffic(&self) -> Result<TrafficData, MihomoError> {
        let response = self.build_request(reqwest::Method::GET, "/traffic")
            .send()
            .await?;
        
        if response.status().is_success() {
            let data = response.json().await?;
            Ok(data)
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Get logs (returns raw text)
    pub async fn get_logs(&self, level: &str, lines: u32) -> Result<String, MihomoError> {
        let response = self.build_request(reqwest::Method::GET, "/logs")
            .query(&[("level", level), ("lines", &lines.to_string())])
            .send()
            .await?;
        
        if response.status().is_success() {
            let text = response.text().await?;
            Ok(text)
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }

    /// Reload mihomo config
    pub async fn reload_config(&self, path: Option<&str>) -> Result<(), MihomoError> {
        let mut request = self.build_request(reqwest::Method::PUT, "/configs");
        
        if let Some(path) = path {
            #[derive(Serialize)]
            struct ReloadRequest {
                path: String,
            }
            request = request.json(&ReloadRequest {
                path: path.to_string(),
            });
        }
        
        let response = request.send().await?;
        
        if response.status().is_success() {
            Ok(())
        } else {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            Err(MihomoError::ApiError { status, message: text })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = MihomoApiClient::default_with_secret(None);
        assert_eq!(client.base_url, DEFAULT_API_URL);
        
        let client_with_secret = MihomoApiClient::default_with_secret(Some("test".to_string()));
        assert!(client_with_secret.secret.is_some());
    }

    #[tokio::test]
    async fn test_health_check_when_not_running() {
        // This should fail since mihomo is not running on default port
        let client = MihomoApiClient::default_with_secret(None);
        let healthy = client.health_check().await.unwrap();
        assert!(!healthy);
    }
}
