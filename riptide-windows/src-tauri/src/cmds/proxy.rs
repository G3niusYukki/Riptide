//! Proxy control commands

use crate::core::mihomo::MihomoManager;
use crate::core::mihomo_api::{ProxyInfo, ProxyGroupDetail};
use std::collections::{HashMap, HashSet};
use tauri::State;

/// Start the proxy service
#[tauri::command]
pub async fn start_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.start().await.map_err(|e| e.to_string())
}

/// Stop the proxy service
#[tauri::command]
pub async fn stop_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.stop().await.map_err(|e| e.to_string())
}

/// Restart the proxy service
#[tauri::command]
pub async fn restart_proxy(state: State<'_, MihomoManager>) -> Result<(), String> {
    state.restart().await.map_err(|e| e.to_string())
}

/// Get proxy status
#[tauri::command]
pub async fn get_proxy_status(state: State<'_, MihomoManager>) -> Result<bool, String> {
    Ok(state.is_running().await)
}

/// Test proxy delay for a specific node
#[tauri::command]
pub async fn test_proxy_delay(
    state: State<'_, MihomoManager>,
    name: String,
    url: Option<String>,
) -> Result<u32, String> {
    // Get API client from mihomo manager
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    // Test delay via mihomo API
    let delay = api_client
        .test_proxy_delay(&name, url.as_deref(), Some(5000))
        .await
        .map_err(|e| format!("Delay test failed: {}", e))?;
    
    Ok(delay)
}

/// Get all proxy groups
#[tauri::command]
pub async fn get_proxy_groups(
    state: State<'_, MihomoManager>,
) -> Result<Vec<ProxyGroupDetail>, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    let proxies = api_client
        .get_proxies()
        .await
        .map_err(|e| format!("Failed to get proxies: {}", e))?;

    let group_types = ["select", "url-test", "fallback", "load-balance", "relay"];
    let mut groups = Vec::new();

    for (name, proxy) in proxies {
        if !group_types.contains(&proxy.proxy_type.as_str()) {
            continue;
        }

        let group = api_client
            .get_proxy_group(&name)
            .await
            .map_err(|e| format!("Failed to get proxy group {name}: {e}"))?;
        groups.push(group);
    }

    Ok(groups)
}

/// Get all individual proxies (non-groups)
#[tauri::command]
pub async fn get_all_proxies(
    state: State<'_, MihomoManager>,
) -> Result<Vec<ProxyInfo>, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    let proxies = api_client
        .get_proxies()
        .await
        .map_err(|e| format!("Failed to get proxies: {}", e))?;
    
    // Filter out groups, keep only individual proxies
    let group_types = ["select", "url-test", "fallback", "load-balance", "relay"];
    let individual_proxies: Vec<ProxyInfo> = proxies
        .into_iter()
        .filter(|(_, proxy)| !group_types.contains(&proxy.proxy_type.as_str()))
        .map(|(_, proxy)| proxy)
        .collect();
    
    Ok(individual_proxies)
}

/// Switch proxy in a group
#[tauri::command]
pub async fn switch_proxy(
    state: State<'_, MihomoManager>,
    group: String,
    proxy_name: String,
) -> Result<(), String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    api_client
        .switch_proxy(&group, &proxy_name)
        .await
        .map_err(|e| format!("Failed to switch proxy: {}", e))?;
    
    Ok(())
}

/// Test all proxies in a group
#[tauri::command]
pub async fn test_group_delay(
    state: State<'_, MihomoManager>,
    group: String,
) -> Result<HashMap<String, u32>, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    let group_detail = api_client
        .get_proxy_group(&group)
        .await
        .map_err(|e| format!("Failed to get proxy group: {}", e))?;

    let mut results = HashMap::new();
    let mut seen = HashSet::new();

    for proxy_name in group_detail.proxies {
        if !seen.insert(proxy_name.clone()) {
            continue;
        }

        match api_client.test_proxy_delay(&proxy_name, None, Some(5000)).await {
            Ok(delay) => {
                results.insert(proxy_name, delay);
            }
            Err(e) => {
                log::warn!("Failed to test proxy {} in group {}: {}", proxy_name, group, e);
            }
        }
    }

    Ok(results)
}

/// Get active connections
#[tauri::command]
pub async fn get_connections(
    state: State<'_, MihomoManager>,
) -> Result<Vec<crate::core::mihomo_api::ConnectionInfo>, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    let connections = api_client
        .get_connections()
        .await
        .map_err(|e| format!("Failed to get connections: {}", e))?;
    
    Ok(connections)
}

/// Close a specific connection
#[tauri::command]
pub async fn close_connection(
    state: State<'_, MihomoManager>,
    id: String,
) -> Result<(), String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    api_client
        .close_connection(&id)
        .await
        .map_err(|e| format!("Failed to close connection: {}", e))?;
    
    Ok(())
}

/// Close all connections
#[tauri::command]
pub async fn close_all_connections(
    state: State<'_, MihomoManager>,
) -> Result<(), String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;
    
    api_client
        .close_all_connections()
        .await
        .map_err(|e| format!("Failed to close all connections: {}", e))?;
    
    Ok(())
}

/// Get routing rules
#[tauri::command]
pub async fn get_rules(
    state: State<'_, MihomoManager>,
) -> Result<Vec<crate::core::mihomo_api::RuleInfo>, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;

    let rules = api_client
        .get_rules()
        .await
        .map_err(|e| format!("Failed to get rules: {}", e))?;

    Ok(rules)
}

/// Get mihomo logs
#[tauri::command]
pub async fn get_logs(
    state: State<'_, MihomoManager>,
    level: Option<String>,
    lines: Option<u32>,
) -> Result<String, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;

    let log_text = api_client
        .get_logs(&level.unwrap_or_else(|| "info".to_string()), lines.unwrap_or(100))
        .await
        .map_err(|e| format!("Failed to get logs: {}", e))?;

    Ok(log_text)
}

/// Get traffic statistics
#[tauri::command]
pub async fn get_traffic(
    state: State<'_, MihomoManager>,
) -> Result<crate::core::mihomo_api::TrafficData, String> {
    let api_client = state.get_api_client().await
        .map_err(|e| format!("Failed to get API client: {}", e))?;

    let traffic = api_client
        .get_traffic()
        .await
        .map_err(|e| format!("Failed to get traffic: {}", e))?;

    Ok(traffic)
}
