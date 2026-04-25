//! Riptide Windows - A native Windows proxy client

pub mod cmds;
pub mod config;
pub mod core;
pub mod utils;

use tauri::Manager;
use std::sync::Mutex;

use crate::core::mihomo::MihomoManager;
use crate::core::sysproxy::SystemProxyController;
use crate::core::windows_tun::WindowsTUNManager;
use crate::config::profiles::Profile;
use crate::cmds::config::AppState;
use crate::utils::hotkeys::{HotkeyManager, init_hotkeys};

fn autostart_args() -> Option<Vec<&'static str>> {
    Some(vec!["--minimized"])
}

fn autostart_launcher() -> tauri_plugin_autostart::MacosLauncher {
    #[cfg(target_os = "macos")]
    {
        tauri_plugin_autostart::MacosLauncher::LaunchAgent
    }

    #[cfg(not(target_os = "macos"))]
    {
        tauri_plugin_autostart::MacosLauncher::default()
    }
}

fn autostart_plugin<R: tauri::Runtime>() -> tauri::plugin::TauriPlugin<R> {
    // The launcher choice is only used on macOS. Windows uses the plugin's
    // native autostart backend, so we avoid hard-coding a macOS launcher there.
    tauri_plugin_autostart::init(autostart_launcher(), autostart_args())
}

/// Run the Tauri application
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize logger
    env_logger::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(autostart_plugin())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_fs::init())
        .manage(Mutex::new(Vec::<Profile>::new()))
        .manage(AppState::new())
        .setup(|app| {
            // Initialize state
            let app_handle = app.handle().clone();
            app.manage(MihomoManager::new(app_handle.clone()));
            app.manage(SystemProxyController::new());

            // Initialize Windows-specific state
            #[cfg(target_os = "windows")]
            {
                // Initialize Windows directories
                if let Err(e) = crate::utils::windows_dirs::WindowsDirs::ensure_dirs() {
                    log::warn!("Failed to create Windows config directories: {}", e);
                } else {
                    log::info!("Windows config directories initialized");
                }

                match crate::cmds::windows::init_windows_proxy_state(&app_handle) {
                    Ok(state) => {
                        app.manage(state);
                        log::info!("Windows proxy state initialized");
                    }
                    Err(e) => {
                        log::warn!("Failed to initialize Windows proxy state: {}", e);
                    }
                }

                // Initialize TUN state
                match crate::cmds::windows::init_windows_tun_state(&app_handle) {
                    Ok(state) => {
                        app.manage(state);
                        log::info!("Windows TUN state initialized");
                    }
                    Err(e) => {
                        log::warn!("Failed to initialize Windows TUN state: {}", e);
                    }
                }
            }

            // Check if mihomo binary exists
            if !core::mihomo::check_mihomo_binary(&app_handle) {
                log::warn!("mihomo binary not found. Please download it first.");
            }

            // Initialize global hotkeys
            #[cfg(target_os = "windows")]
            match init_hotkeys(app_handle.clone()) {
                Ok(hotkey_manager) => {
                    app.manage(std::sync::Mutex::new(hotkey_manager));
                    log::info!("Global hotkeys initialized (Ctrl+Alt+P, Ctrl+Alt+M)");
                }
                Err(e) => {
                    log::warn!("Failed to initialize global hotkeys: {}", e);
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Proxy commands
            cmds::proxy::start_proxy,
            cmds::proxy::stop_proxy,
            cmds::proxy::restart_proxy,
            cmds::proxy::get_proxy_status,
            cmds::proxy::test_proxy_delay,
            cmds::proxy::get_proxy_groups,
            cmds::proxy::get_all_proxies,
            cmds::proxy::switch_proxy,
            cmds::proxy::test_group_delay,
            // Connection commands
            cmds::proxy::get_connections,
            cmds::proxy::close_connection,
            cmds::proxy::close_all_connections,
            cmds::proxy::get_traffic,
            cmds::proxy::get_rules,
            cmds::proxy::get_logs,
            // Legacy config commands
            cmds::config::get_profiles,
            cmds::config::add_profile,
            cmds::config::remove_profile,
            cmds::config::update_profile,
            cmds::config::import_profile_from_url,
            cmds::config::import_share_uri,
            cmds::config::get_active_profile,
            cmds::config::set_active_profile,
            // Windows profile management commands
            cmds::config::create_profile,
            cmds::config::list_profiles,
            cmds::config::delete_profile,
            cmds::config::import_profile_from_file,
            cmds::config::export_profile,
            cmds::config::validate_config,
            // System commands
            cmds::system::enable_system_proxy,
            cmds::system::disable_system_proxy,
            cmds::system::get_system_proxy_status,
            cmds::system::install_tun_service,
            cmds::system::uninstall_tun_service,
            cmds::system::start_tun_service,
            cmds::system::stop_tun_service,
            cmds::system::check_update,
            // Windows-specific commands
            #[cfg(target_os = "windows")]
            cmds::windows::start_windows_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::stop_windows_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::restart_windows_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::get_windows_proxy_status,
            #[cfg(target_os = "windows")]
            cmds::windows::get_windows_proxy_pid,
            #[cfg(target_os = "windows")]
            cmds::windows::enable_windows_system_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::enable_windows_socks_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::enable_windows_both_proxies,
            #[cfg(target_os = "windows")]
            cmds::windows::disable_windows_system_proxy,
            #[cfg(target_os = "windows")]
            cmds::windows::get_windows_system_proxy_config,
            // TUN mode commands
            #[cfg(target_os = "windows")]
            cmds::windows::start_tun_mode,
            #[cfg(target_os = "windows")]
            cmds::windows::stop_tun_mode,
            #[cfg(target_os = "windows")]
            cmds::windows::get_tun_status,
            // Hotkey commands
            #[cfg(target_os = "windows")]
            utils::hotkeys::get_hotkeys,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{autostart_args, autostart_launcher};

    #[test]
    fn autostart_passes_minimized_flag() {
        assert_eq!(autostart_args(), Some(vec!["--minimized"]));
    }

    #[test]
    fn autostart_uses_platform_appropriate_launcher_configuration() {
        #[cfg(target_os = "macos")]
        assert!(matches!(
            autostart_launcher(),
            tauri_plugin_autostart::MacosLauncher::LaunchAgent
        ));

        #[cfg(not(target_os = "macos"))]
        {
            let _ = autostart_launcher();
        }
    }

    #[test]
    fn app_state_default_works() {
        use crate::cmds::config::AppState;
        let state = AppState::default();
        let profiles = state.profiles.lock().unwrap();
        assert!(profiles.is_empty());
    }

    #[test]
    fn app_state_new_works() {
        use crate::cmds::config::AppState;
        let state = AppState::new();
        let active_id = state.active_profile_id.lock().unwrap();
        assert!(active_id.is_none());
    }
}
