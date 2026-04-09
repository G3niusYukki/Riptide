//! Riptide Windows - A native Windows proxy client

pub mod cmds;
pub mod config;
pub mod core;
pub mod utils;

use tauri::Manager;
use std::sync::Mutex;

use crate::core::mihomo::MihomoManager;
use crate::core::sysproxy::SystemProxyController;
use crate::config::profiles::Profile;

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
        .setup(|app| {
            // Initialize state
            let app_handle = app.handle().clone();
            app.manage(MihomoManager::new(app_handle.clone()));
            app.manage(SystemProxyController::new());

            // Check if mihomo binary exists
            if !core::mihomo::check_mihomo_binary(&app_handle) {
                log::warn!("mihomo binary not found. Please download it first.");
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
            // Config commands
            cmds::config::get_profiles,
            cmds::config::add_profile,
            cmds::config::remove_profile,
            cmds::config::update_profile,
            cmds::config::import_profile_from_url,
            cmds::config::get_active_profile,
            cmds::config::set_active_profile,
            // System commands
            cmds::system::enable_system_proxy,
            cmds::system::disable_system_proxy,
            cmds::system::get_system_proxy_status,
            cmds::system::install_tun_service,
            cmds::system::uninstall_tun_service,
            cmds::system::start_tun_service,
            cmds::system::stop_tun_service,
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
}
