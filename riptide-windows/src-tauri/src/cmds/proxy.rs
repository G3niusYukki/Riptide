//! Proxy control commands

use crate::core::mihomo::MihomoManager;
use crate::core::mihomo_api::{ProxyInfo, ProxyGroupDetail};
use std::collections::HashMap;
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
    
    // Filter to only groups (types: select, url-test, fallback, load-balance, relay)
    let group_types = ["select", "url-test", "fallback", "load-balance", "relay"];
    let groups: Vec<ProxyGroupDetail> = proxies
        .into_iter()
        .filter_map(|(name, proxy)| {
            if group_types.contains(&proxy.proxy_type.as_str()) {
                Some(ProxyGroupDetail {
                    name,
                    group_type: proxy.proxy_type,
                    proxies: vec![],
                    now: None,
                    url: None,
                    interval: None,
                    tolerance: None,
                    delay: proxy.delay,
                })
            } else {
                None
            }
        })
        .collect();
    
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
    
    let mut results = HashMap::new();
    
    // Test the group's own delay (represents selected proxy)
    match api_client.test_proxy_delay(&group, None, Some(5000)).await {
        Ok(delay) => {
            results.insert(group, delay);
        }
        Err(e) => {
            log::warn!("Failed to test group {}: {}", group, e);
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
