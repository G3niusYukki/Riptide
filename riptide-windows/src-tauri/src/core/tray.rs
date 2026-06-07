//! System tray menu — quick-access controls without bringing up the main window.
//!
//! Items:
//!   - Show / Hide window
//!   - Mode → Off | System Proxy | TUN (radio)
//!   - Quit
//!
//! Built via Tauri's native tray APIs. Mode entries delegate to the
//! `ModeCoordinator` so the same locks/events apply as in-app clicks.

use tauri::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, Wry};

use crate::cmds::config::{resolve_active_profile_content, AppState};
use crate::core::mihomo::MihomoManager;
use crate::core::mode_coordinator::ModeCoordinator;
use crate::core::sysproxy::SystemProxyController;

/// Configure the tray. Call once during `setup()`. The trayIcon entry in
/// `tauri.conf.json` produces the base icon; this fn wires the menu and
/// event handlers on top of it.
pub fn install(app: &AppHandle) -> tauri::Result<()> {
    let show_item = MenuItem::with_id(app, "show", "显示窗口", true, None::<&str>)?;
    let hide_item = MenuItem::with_id(app, "hide", "隐藏窗口", true, None::<&str>)?;
    let mode_off = MenuItem::with_id(app, "mode_off", "模式：关闭", true, None::<&str>)?;
    let mode_sysproxy =
        MenuItem::with_id(app, "mode_sysproxy", "模式：系统代理", true, None::<&str>)?;
    let mode_tun = MenuItem::with_id(app, "mode_tun", "模式：TUN", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit_item = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[
            &show_item,
            &hide_item,
            &separator,
            &mode_off,
            &mode_sysproxy,
            &mode_tun,
            &separator,
            &quit_item,
        ],
    )?;

    // `id = "main"` matches the trayIcon entry in tauri.conf.json so we attach
    // the menu to the icon Tauri already created rather than instantiating a
    // second one.
    let _tray = TrayIconBuilder::with_id("main")
        .menu(&menu)
        .on_menu_event(handle_menu_event)
        .on_tray_icon_event(handle_icon_event)
        .build(app)?;

    Ok(())
}

fn handle_menu_event(app: &AppHandle, event: MenuEvent) {
    match event.id.as_ref() {
        "show" => show_window(app),
        "hide" => hide_window(app),
        "quit" => {
            log::info!("Tray: quit requested");
            app.exit(0);
        }
        "mode_off" => spawn_mode_switch(app.clone(), ModeTarget::Off),
        "mode_sysproxy" => spawn_mode_switch(app.clone(), ModeTarget::SystemProxy),
        "mode_tun" => spawn_mode_switch(app.clone(), ModeTarget::Tun),
        _ => {}
    }
}

fn handle_icon_event(tray: &tauri::tray::TrayIcon<Wry>, event: TrayIconEvent) {
    // Left-click toggles the main window — the standard convention.
    if let TrayIconEvent::Click {
        button: tauri::tray::MouseButton::Left,
        button_state: tauri::tray::MouseButtonState::Up,
        ..
    } = event
    {
        let app = tray.app_handle();
        if let Some(window) = app.get_webview_window("main") {
            let visible = window.is_visible().unwrap_or(false);
            if visible {
                let _ = window.hide();
            } else {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    }
}

fn show_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn hide_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

enum ModeTarget {
    Off,
    SystemProxy,
    Tun,
}

fn spawn_mode_switch(app: AppHandle, target: ModeTarget) {
    tauri::async_runtime::spawn(async move {
        let coordinator = match app.try_state::<ModeCoordinator>() {
            Some(c) => c,
            None => return,
        };
        let mihomo = match app.try_state::<MihomoManager>() {
            Some(m) => m,
            None => return,
        };
        let sysproxy = match app.try_state::<SystemProxyController>() {
            Some(s) => s,
            None => return,
        };
        let app_state = match app.try_state::<AppState>() {
            Some(s) => s,
            None => return,
        };

        let result = match target {
            ModeTarget::Off => coordinator.switch_off(&mihomo, &sysproxy).await,
            ModeTarget::SystemProxy => {
                coordinator
                    .switch_to_system_proxy(&mihomo, &sysproxy, &app_state, 7890, Some(7891))
                    .await
            }
            ModeTarget::Tun => {
                // Reading the profile content explicitly here mirrors the UI's
                // pre-flight; this isn't required to switch, but it surfaces
                // missing-profile errors before we touch mihomo.
                if let Err(e) = resolve_active_profile_content(&app_state) {
                    log::warn!("Tray TUN switch: no profile resolved: {}", e);
                    return;
                }
                coordinator
                    .switch_to_tun(&mihomo, &sysproxy, &app_state)
                    .await
            }
        };

        if let Err(e) = result {
            log::warn!("Tray mode switch failed: {}", e);
        }
    });
}
