//! Riptide Windows - A native Windows proxy client

pub mod cmds;
pub mod config;
pub mod core;
pub mod utils;

use tauri::AppHandle;
use tauri::Manager;
use std::sync::Mutex;

use crate::core::mihomo::MihomoManager;
use crate::core::sysproxy::SystemProxyController;
use crate::config::profiles::Profile;

/// Run the Tauri application
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize logger
    env_logger::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--minimized"]) ))
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
