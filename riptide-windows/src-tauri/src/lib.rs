//! Riptide Windows - A native Windows proxy client

pub mod cli;
pub mod cmds;
pub mod config;
pub mod core;
pub mod utils;

use tauri::Manager;

use crate::core::mihomo::MihomoManager;
use crate::core::mode_coordinator::ModeCoordinator;
use crate::core::sysproxy::SystemProxyController;
use crate::cmds::config::AppState;
use crate::utils::hotkeys::init_hotkeys;

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
    // Initialise tracing-based logging. Failure here shouldn't block app launch
    // (the user can still see stderr), so warn instead of panic.
    if let Err(e) = crate::utils::logger::init_logger() {
        eprintln!("Failed to initialise logger: {}", e);
    }

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            // Second launch — focus the existing window instead of opening a new one.
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(autostart_plugin())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState::new())
        .setup(|app| {
            // Initialize state
            let app_handle = app.handle().clone();
            app.manage(MihomoManager::new(app_handle.clone()));
            let sysproxy = SystemProxyController::new();
            // Arm the guard's event emitter before any enable() can spawn it.
            {
                let handle = app_handle.clone();
                tauri::async_runtime::block_on(async {
                    sysproxy.bind_app_handle(handle).await;
                });
            }
            app.manage(sysproxy);
            app.manage(ModeCoordinator::new(app_handle.clone()));

            // Initialize Windows-specific state
            #[cfg(target_os = "windows")]
            {
                // Initialize Windows directories
                if let Err(e) = crate::utils::windows_dirs::WindowsDirs::ensure_dirs() {
                    log::warn!("Failed to create Windows config directories: {}", e);
                } else {
                    log::info!("Windows config directories initialized");
                }

                // Restore the persisted active-profile pointer from active.json.
                // Must happen after ensure_dirs() so the config dir exists, and
                // before any UI query, so get_active_profile reflects disk state.
                app.state::<AppState>().load_active_from_disk();

                match crate::cmds::windows::init_windows_proxy_state(&app_handle) {
                    Ok(state) => {
                        app.manage(state);
                        log::info!("Windows proxy state initialized");
                    }
                    Err(e) => {
                        log::warn!("Failed to initialize Windows proxy state: {}", e);
                    }
                }
            }

            // Check if mihomo binary exists. If missing, kick off a background
            // download — the UI listens for `mihomo_bootstrap_progress` events
            // and surfaces progress; start_proxy will fail with a clear error
            // until the download lands.
            if !core::mihomo::check_mihomo_binary(&app_handle) {
                log::warn!("mihomo binary not found — starting background download");
                let handle = app_handle.clone();
                tauri::async_runtime::spawn(async move {
                    if let Err(e) = core::mihomo_bootstrap::ensure_mihomo_binary(&handle).await {
                        log::error!("mihomo bootstrap failed: {}", e);
                    }
                });
            }

            // Boot the subscription auto-refresh scheduler. Lifecycle = app lifecycle.
            core::subscription_scheduler::spawn(app_handle.clone());

            // Background-fetch geoip/geosite if missing.
            core::geo_assets::ensure_present_async(app_handle.clone());

            // Recovery watchdog: detects sleep/wake and network changes, then
            // health-probes mihomo and restarts if necessary.
            core::recovery_watchdog::spawn(app_handle.clone());

            // Silent start: if `--minimized` is on the command line (set by
            // the autostart plugin), hide the main window so the app only
            // surfaces in the tray. The user can show it again from there.
            if std::env::args().any(|a| a == "--minimized") {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                    log::info!("Silent start: window hidden (--minimized flag)");
                }
            }

            // Install the tray menu (show/hide, mode switch, quit).
            if let Err(e) = core::tray::install(&app_handle) {
                log::warn!("Failed to install tray menu: {}", e);
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
            // Profile management (disk-backed)
            cmds::config::create_profile,
            cmds::config::list_profiles,
            cmds::config::delete_profile,
            cmds::config::update_profile,
            cmds::config::import_profile_from_url,
            cmds::config::import_share_uri,
            cmds::config::import_profile_from_file,
            cmds::config::export_profile,
            cmds::config::validate_config,
            cmds::config::get_active_profile,
            cmds::config::set_active_profile,
            cmds::config::refresh_profile,
            cmds::config::set_profile_subscription,
            cmds::config::get_profile_metadata,
            // Per-proxy editor (in-profile CRUD)
            cmds::proxy_editor::list_profile_proxies,
            cmds::proxy_editor::add_profile_proxy,
            cmds::proxy_editor::update_profile_proxy,
            cmds::proxy_editor::delete_profile_proxy,
            // mihomo lifecycle
            core::mihomo_bootstrap::download_mihomo,
            // WARP integration
            core::warp::register_warp_profile,
            // Geo assets
            core::geo_assets::get_geo_assets,
            core::geo_assets::download_geo_assets,
            // DNS policy
            cmds::dns::get_dns_policy,
            cmds::dns::set_dns_policy,
            // Rewrite rules
            cmds::rewrite::get_rewrite_rules,
            cmds::rewrite::set_rewrite_rules,
            cmds::rewrite::add_rewrite_rule,
            cmds::rewrite::delete_rewrite_rule,
            cmds::rewrite::toggle_rewrite_rule,
            // Gateway / ICS
            #[cfg(target_os = "windows")]
            cmds::gateway::enable_gateway,
            #[cfg(target_os = "windows")]
            cmds::gateway::disable_gateway,
            #[cfg(target_os = "windows")]
            cmds::gateway::is_gateway_enabled,
            #[cfg(target_os = "windows")]
            cmds::gateway::get_gateway_devices,
            // WebDAV sync
            cmds::webdav::webdav_get_config,
            cmds::webdav::webdav_set_config,
            cmds::webdav::webdav_test_connection,
            cmds::webdav::webdav_backup_now,
            cmds::webdav::webdav_restore_now,
            // Kill switch
            core::kill_switch::get_kill_switch_state,
            core::kill_switch::set_kill_switch_enabled,
            core::kill_switch::kill_switch_release,
            // Diagnostics
            core::diagnostics::collect_diagnostic_report,
            // Region presets
            core::region_presets::get_region_preset,
            core::region_presets::set_region_preset,
            // TLS tricks
            core::tls_tricks::get_tls_tricks,
            core::tls_tricks::set_tls_tricks,
            // Mode coordinator
            cmds::mode::mode_current,
            cmds::mode::mode_switch_to_system_proxy,
            cmds::mode::mode_switch_to_tun,
            cmds::mode::mode_switch_off,
            // System commands
            cmds::system::enable_system_proxy,
            cmds::system::disable_system_proxy,
            cmds::system::get_system_proxy_status,
            cmds::system::install_tun_service,
            cmds::system::uninstall_tun_service,
            cmds::system::start_tun_service,
            cmds::system::stop_tun_service,
            cmds::system::get_tun_service_status,
            cmds::system::is_elevated,
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
            #[cfg(target_os = "windows")]
            cmds::windows::set_tun_options,
            #[cfg(target_os = "windows")]
            cmds::windows::get_tun_options,
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
