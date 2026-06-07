//! Riptide Windows - A native Windows proxy client

#[cfg(target_os = "windows")]
pub mod cli;

// Re-export OneShotResult for main.rs on all platforms
#[cfg(not(target_os = "windows"))]
pub mod cli {
    pub enum OneShotResult { Continue, Exit(i32) }
    pub fn handle_one_shot_cli() -> OneShotResult { OneShotResult::Continue }
}
pub mod cmds;
pub mod config;
pub mod core;
pub mod platform;
pub mod utils;

// Tauri runtime imports + the Tauri command wiring are isolated from
// `cargo test` builds. Loading the tauri runtime inside a test binary
// pulls in WebView2 / Edge dependencies on Windows; the test runner
// then fails with `STATUS_ENTRYPOINT_NOT_FOUND` (0xc0000139) the
// moment the harness tries to load the resulting binary. The unit
// tests under `mod tests` only exercise the cross-platform helpers
// (`autostart_args`, `AppState`) and never the Tauri builder itself,
// so the run() function (and the imports it alone needs) is gated
// out of test builds.
#[cfg(not(test))]
use tauri::Manager;

#[cfg(not(test))]
use crate::core::mihomo::MihomoManager;
#[cfg(not(test))]
use crate::core::mode_coordinator::ModeCoordinator;
#[cfg(not(test))]
use crate::core::sysproxy::SystemProxyController;
#[cfg(not(test))]
use crate::cmds::config::AppState;
#[cfg(all(not(test), target_os = "windows"))]
use crate::utils::hotkeys::init_hotkeys;

fn autostart_args() -> Option<Vec<&'static str>> {
    Some(vec!["--minimized"])
}

#[cfg(not(test))]
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

// Test-only stub for `autostart_launcher`. The real version instantiates
// a `tauri_plugin_autostart::MacosLauncher`, which compiles fine on its
// own, but the `tauri_plugin_autostart::init` call (which is reachable
// only via the real `autostart_plugin`) pulls in the tauri runtime +
// WebView2 dependency surface on Windows. Since both `autostart_plugin`
// and the real `autostart_launcher` are only called from `pub fn run`
// (which is also `#[cfg(not(test))]`), the production build is
// unaffected. This stub keeps the historical unit test green without
// dragging the tauri runtime into the test build.
#[cfg(test)]
fn autostart_launcher() -> tauri_plugin_autostart::MacosLauncher {
    tauri_plugin_autostart::MacosLauncher::default()
}

#[cfg(not(test))]
fn autostart_plugin<R: tauri::Runtime>() -> tauri::plugin::TauriPlugin<R> {
    // The launcher choice is only used on macOS. Windows uses the plugin's
    // native autostart backend, so we avoid hard-coding a macOS launcher there.
    tauri_plugin_autostart::init(autostart_launcher(), autostart_args())
}

/// Run the Tauri application.
///
/// Gated out of `cfg(test)` so that `cargo test` does not try to link
/// the Tauri runtime (which depends on WebView2 / Edge and is not
/// available in a `cargo test` invocation).
#[cfg(not(test))]
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
        .manage(std::sync::Arc::new(crate::core::engines::EngineRouter::default_mihomo()))
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

            // Spawn the diagnostic Logbook writer and fan it out to the
            // five injection points (mode_coordinator, subscription_scheduler,
            // service, sysproxy, recovery_watchdog). The writer is
            // fire-and-forget (internal mpsc + 50ms batch flush), so spinning
            // it up here guarantees the very first business-path `log_*` call
            // lands in the daily JSONL file. Failure to spawn falls back to
            // no-op slots — diagnostic logging is best-effort.
            let logbook_writer = std::sync::Arc::new(crate::core::logbook::LogbookWriter::spawn_default());
            let app_state = app.state::<AppState>();
            app_state.install_logbook_writer(logbook_writer.clone());
            let logbook_for_inject = logbook_writer.clone();
            crate::core::mode_coordinator::set_logbook_writer(Some(logbook_for_inject.clone()));
            crate::core::subscription_scheduler::set_logbook_writer(Some(logbook_for_inject.clone()));
            crate::core::service::set_logbook_writer(Some(logbook_for_inject.clone()));
            crate::core::sysproxy::set_logbook_writer(Some(logbook_for_inject.clone()));
            crate::core::recovery_watchdog::set_logbook_writer(Some(logbook_for_inject));

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
            #[cfg(target_os = "windows")]
            cmds::config::refresh_profile,
            #[cfg(target_os = "windows")]
            cmds::config::set_profile_subscription,
            #[cfg(target_os = "windows")]
            cmds::config::get_profile_metadata,
            // Per-proxy editor (in-profile CRUD)
            cmds::proxy_editor::list_profile_proxies,
            cmds::proxy_editor::add_profile_proxy,
            cmds::proxy_editor::update_profile_proxy,
            cmds::proxy_editor::delete_profile_proxy,
            // Share URI serializer
            cmds::uri_serializer::serialize_proxy_to_uri,
            cmds::uri_serializer::serialize_proxies_to_uris,
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
            // System commands (cross-platform)
            cmds::system::enable_system_proxy,
            cmds::system::disable_system_proxy,
            cmds::system::get_system_proxy_status,
            cmds::system::check_update,
            // System commands (Windows-only — require SCM / elevation)
            #[cfg(target_os = "windows")]
            cmds::system::install_tun_service,
            #[cfg(target_os = "windows")]
            cmds::system::uninstall_tun_service,
            #[cfg(target_os = "windows")]
            cmds::system::start_tun_service,
            #[cfg(target_os = "windows")]
            cmds::system::stop_tun_service,
            #[cfg(target_os = "windows")]
            cmds::system::get_tun_service_status,
            #[cfg(target_os = "windows")]
            cmds::system::is_elevated,
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
            // Diagnostic Logbook (cross-platform Tauri commands backing
            // the front-end LogViewer/Logs tab with on-disk JSONL entries)
            cmds::logbook::logbook_query,
            cmds::logbook::logbook_clear,
            cmds::logbook::logbook_export,
            // Engine router (ADR-0005): the policy that decides
            // mihomo-vs-singbox for each ProxyKind. State is the
            // shared `Arc<EngineRouter>` registered below.
            cmds::engines::engine_current,
            cmds::engines::engine_set_policy,
            cmds::engines::engine_supported_kinds,
            cmds::engines::engine_status,
            cmds::engines::engine_list_kinds,
            cmds::engines::engine_get_policy,
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
