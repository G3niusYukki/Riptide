//! Per-proxy CRUD inside a profile.
//!
//! Operates on a profile's `proxies:` list without disturbing other top-level
//! keys (rules, dns, etc.). We round-trip through `serde_yaml::Value` rather
//! than `ClashRawConfig` so that fields the parser doesn't know about — older
//! mihomo experimental flags, vendor extensions, comments-as-keys — survive
//! the edit.
//!
//! Proxy identity is the `name` field; mihomo treats names as unique within a
//! config. Renames are handled by passing `original_name` alongside the new
//! proxy struct.

use crate::cmds::config::AppState;
use crate::config::parser::ClashRawProxy;
use crate::config::profiles::storage;
use serde_yaml::Value;
use tauri::State;

fn parse_yaml_document(content: &str) -> Result<Value, String> {
    if content.trim().is_empty() {
        return Ok(Value::Mapping(serde_yaml::Mapping::new()));
    }
    serde_yaml::from_str(content).map_err(|e| format!("YAML parse error: {}", e))
}

fn serialize_yaml_document(value: &Value) -> Result<String, String> {
    serde_yaml::to_string(value).map_err(|e| format!("YAML serialize error: {}", e))
}

fn proxies_sequence_mut(doc: &mut Value) -> Result<&mut Vec<Value>, String> {
    let map = doc
        .as_mapping_mut()
        .ok_or_else(|| "Profile root is not a YAML mapping".to_string())?;
    let key = Value::String("proxies".into());
    if !map.contains_key(&key) {
        map.insert(key.clone(), Value::Sequence(Vec::new()));
    }
    let seq = map
        .get_mut(&key)
        .and_then(|v| v.as_sequence_mut())
        .ok_or_else(|| "'proxies' is not a YAML sequence".to_string())?;
    Ok(seq)
}

fn read_proxies_list(doc: &Value) -> Vec<ClashRawProxy> {
    let Some(seq) = doc.get("proxies").and_then(|v| v.as_sequence()) else {
        return Vec::new();
    };
    seq.iter()
        .filter_map(|item| serde_yaml::from_value::<ClashRawProxy>(item.clone()).ok())
        .collect()
}

fn proxy_to_value(proxy: &ClashRawProxy) -> Result<Value, String> {
    serde_yaml::to_value(proxy).map_err(|e| format!("Failed to encode proxy: {}", e))
}

fn name_of(item: &Value) -> Option<String> {
    item.get("name")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// Read the current proxies list of a profile.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn list_profile_proxies(
    profile_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<ClashRawProxy>, String> {
    let content = {
        let profiles = state.profiles.lock().unwrap();
        let p = profiles
            .iter()
            .find(|p| p.id == profile_id)
            .ok_or_else(|| "Profile not found".to_string())?;
        p.content.clone()
    };
    let doc = parse_yaml_document(&content)?;
    Ok(read_proxies_list(&doc))
}

/// Append a new proxy. Errors if the name collides with an existing entry.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn add_profile_proxy(
    profile_id: String,
    proxy: ClashRawProxy,
    state: State<'_, AppState>,
) -> Result<(), String> {
    if proxy.name.trim().is_empty() {
        return Err("Proxy name cannot be empty".into());
    }

    let new_content = {
        let mut profiles = state.profiles.lock().unwrap();
        let profile = profiles
            .iter_mut()
            .find(|p| p.id == profile_id)
            .ok_or_else(|| "Profile not found".to_string())?;

        let mut doc = parse_yaml_document(&profile.content)?;
        {
            let seq = proxies_sequence_mut(&mut doc)?;
            if seq.iter().any(|item| name_of(item).as_deref() == Some(&proxy.name)) {
                return Err(format!("Proxy '{}' already exists", proxy.name));
            }
            seq.push(proxy_to_value(&proxy)?);
        }
        let new_content = serialize_yaml_document(&doc)?;
        storage::update_profile_content(profile, new_content.clone())
            .map_err(|e| format!("Failed to save profile: {}", e))?;
        new_content
    };

    log::info!("Added proxy '{}' to profile '{}' ({} bytes)", proxy.name, profile_id, new_content.len());
    Ok(())
}

/// Update an existing proxy in place, identified by `original_name`. A rename
/// is supported by passing a different `proxy.name`; we verify the new name
/// isn't already taken by a *different* entry.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn update_profile_proxy(
    profile_id: String,
    original_name: String,
    proxy: ClashRawProxy,
    state: State<'_, AppState>,
) -> Result<(), String> {
    if proxy.name.trim().is_empty() {
        return Err("Proxy name cannot be empty".into());
    }

    let mut profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter_mut()
        .find(|p| p.id == profile_id)
        .ok_or_else(|| "Profile not found".to_string())?;

    let mut doc = parse_yaml_document(&profile.content)?;
    {
        let seq = proxies_sequence_mut(&mut doc)?;

        if proxy.name != original_name
            && seq
                .iter()
                .any(|item| name_of(item).as_deref() == Some(&proxy.name))
        {
            return Err(format!("Proxy '{}' already exists", proxy.name));
        }

        let idx = seq
            .iter()
            .position(|item| name_of(item).as_deref() == Some(&original_name))
            .ok_or_else(|| format!("Proxy '{}' not found", original_name))?;

        seq[idx] = proxy_to_value(&proxy)?;
    }

    let new_content = serialize_yaml_document(&doc)?;
    storage::update_profile_content(profile, new_content)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    log::info!(
        "Updated proxy '{}' (was '{}') in profile '{}'",
        proxy.name,
        original_name,
        profile_id
    );
    Ok(())
}

/// Remove a proxy by name. No-op (with an error) if the name doesn't exist.
#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn delete_profile_proxy(
    profile_id: String,
    name: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let mut profiles = state.profiles.lock().unwrap();
    let profile = profiles
        .iter_mut()
        .find(|p| p.id == profile_id)
        .ok_or_else(|| "Profile not found".to_string())?;

    let mut doc = parse_yaml_document(&profile.content)?;
    {
        let seq = proxies_sequence_mut(&mut doc)?;
        let idx = seq
            .iter()
            .position(|item| name_of(item).as_deref() == Some(&name))
            .ok_or_else(|| format!("Proxy '{}' not found", name))?;
        seq.remove(idx);
    }

    let new_content = serialize_yaml_document(&doc)?;
    storage::update_profile_content(profile, new_content)
        .map_err(|e| format!("Failed to save profile: {}", e))?;

    log::info!("Deleted proxy '{}' from profile '{}'", name, profile_id);
    Ok(())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn list_profile_proxies(
    _profile_id: String,
    _state: State<'_, AppState>,
) -> Result<Vec<ClashRawProxy>, String> {
    Err("Proxy editor only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn add_profile_proxy(
    _profile_id: String,
    _proxy: ClashRawProxy,
    _state: State<'_, AppState>,
) -> Result<(), String> {
    Err("Proxy editor only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn update_profile_proxy(
    _profile_id: String,
    _original_name: String,
    _proxy: ClashRawProxy,
    _state: State<'_, AppState>,
) -> Result<(), String> {
    Err("Proxy editor only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn delete_profile_proxy(
    _profile_id: String,
    _name: String,
    _state: State<'_, AppState>,
) -> Result<(), String> {
    Err("Proxy editor only available on Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_doc() -> Value {
        serde_yaml::from_str(
            r#"
mode: rule
proxies:
  - name: A
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pw1
rules:
  - MATCH,DIRECT
"#,
        )
        .unwrap()
    }

    #[test]
    fn read_proxies_returns_parsed_entries() {
        let doc = sample_doc();
        let list = read_proxies_list(&doc);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "A");
        assert_eq!(list[0].proxy_type.as_deref(), Some("ss"));
    }

    #[test]
    fn proxies_sequence_mut_creates_when_missing() {
        let mut doc: Value = serde_yaml::from_str("mode: rule").unwrap();
        proxies_sequence_mut(&mut doc).unwrap().push(
            proxy_to_value(&ClashRawProxy {
                name: "B".into(),
                proxy_type: Some("trojan".into()),
                ..Default::default()
            })
            .unwrap(),
        );
        let list = read_proxies_list(&doc);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "B");
    }

    #[test]
    fn round_trip_preserves_unknown_root_keys() {
        let mut doc = sample_doc();
        proxies_sequence_mut(&mut doc).unwrap().push(
            proxy_to_value(&ClashRawProxy {
                name: "C".into(),
                proxy_type: Some("vmess".into()),
                ..Default::default()
            })
            .unwrap(),
        );
        let out = serialize_yaml_document(&doc).unwrap();
        // 'rules' is unrelated to ClashRawProxy; must survive a YAML round trip.
        assert!(out.contains("rules:"));
        assert!(out.contains("MATCH,DIRECT"));
    }
}
