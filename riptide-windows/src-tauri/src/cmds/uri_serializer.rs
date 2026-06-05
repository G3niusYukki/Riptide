//! Tauri commands for share-URI serialization.
//!
//! Wraps `config::uri_serializer` for the JS layer:
//!   * `serialize_proxy_to_uri` — turn one `ClashRawProxy` into a share URI
//!   * `serialize_proxies_to_uris` — turn all proxies in a profile into share URIs
//!
//! Lives in a separate file (not in `cmds/config.rs`) to keep the
//! conflict surface with the in-flight Phase B logbook work minimal.

use crate::config::parser::ClashRawProxy;
use crate::config::uri_serializer::proxy_to_uri_strict;

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn serialize_proxy_to_uri(proxy: ClashRawProxy) -> Result<String, String> {
    proxy_to_uri_strict(&proxy).map_err(|e| e.to_string())
}

#[cfg(target_os = "windows")]
#[tauri::command]
pub async fn serialize_proxies_to_uris(
    profile_id: String,
) -> Result<Vec<(String, String)>, String> {
    // The Tauri command signature requires `State<'_, AppState>`, but
    // the profile-id-based variant of this command needs synchronous
    // access to the AppState's profile list. Until the B3 producer's
    // logbook wiring is complete, AppState's profile list isn't
    // reliably populated, so we accept the parameter and return an
    // explanatory error pointing the caller to the per-proxy command.
    let _ = profile_id;
    Err("serialize_proxies_to_uris requires AppState (pending B3 producer wire-up); \
         call serialize_proxy_to_uri for each proxy until then"
        .into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn serialize_proxy_to_uri(_proxy: ClashRawProxy) -> Result<String, String> {
    Err("Share URI serializer only available on Windows".into())
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub async fn serialize_proxies_to_uris(
    _profile_id: String,
) -> Result<Vec<(String, String)>, String> {
    Err("Share URI serializer only available on Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::parser::ClashRawProxy;

    #[test]
    fn single_proxy_command_compiles_and_validates_input() {
        // The Tauri command layer is a thin wrapper; round-trip is
        // exercised at the lib level. Here we just verify the
        // wrapper's error path returns the message as a String.
        let p = ClashRawProxy {
            name: "broken".into(),
            server: None,
            port: None,
            proxy_type: Some("ss".into()),
            ..Default::default()
        };
        let result = std::panic::catch_unwind(|| {
            // simulate the command body inline (we can't drive the
            // #[tauri::command] attribute from a unit test, but we
            // can call the body)
            proxy_to_uri_strict(&p).map_err(|e| e.to_string())
        });
        let result = result.expect("wrapper should not panic");
        assert!(result.is_err());
    }
}
