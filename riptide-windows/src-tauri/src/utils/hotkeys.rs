//! Global hotkey management for Riptide Windows
//!
//! Provides system-wide keyboard shortcuts for quick proxy control:
//! - Ctrl+Alt+P: Toggle proxy on/off
//! - Ctrl+Alt+M: Toggle proxy mode (System Proxy / TUN)

use global_hotkey::hotkey::{Code, HotKey, Modifiers};
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager};
use std::sync::Arc;
use std::thread;
use tauri::{AppHandle, Emitter};
use thiserror::Error;

/// Errors that can occur during hotkey operations
#[derive(Debug, Error)]
pub enum HotkeyError {
    #[error("Failed to initialize global hotkey manager: {0}")]
    InitFailed(String),
    #[error("Failed to register hotkey: {0}")]
    RegistrationFailed(String),
    #[error("Failed to unregister hotkey: {0}")]
    UnregistrationFailed(String),
    #[error("Hotkey already registered")]
    AlreadyRegistered,
    #[error("Hotkey not registered")]
    NotRegistered,
}

/// Type of hotkey action
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyAction {
    /// Toggle proxy on/off
    ToggleProxy,
    /// Toggle proxy mode
    ToggleMode,
}

/// Hotkey configuration
#[derive(Debug, Clone)]
pub struct HotkeyConfig {
    pub action: HotkeyAction,
    pub hotkey: HotKey,
    pub description: String,
}

/// Manager for global hotkeys
pub struct HotkeyManager {
    manager: Arc<GlobalHotKeyManager>,
    registered_keys: Vec<HotkeyConfig>,
    app_handle: Option<AppHandle>,
}

// Safe: GlobalHotKeyManager operations are internally synchronized via OS APIs
unsafe impl Send for HotkeyManager {}
unsafe impl Sync for HotkeyManager {}

impl HotkeyManager {
    /// Create a new hotkey manager
    pub fn new() -> Result<Self, HotkeyError> {
        let manager =
            GlobalHotKeyManager::new().map_err(|e| HotkeyError::InitFailed(e.to_string()))?;

        Ok(Self {
            manager: Arc::new(manager),
            registered_keys: Vec::new(),
            app_handle: None,
        })
    }

    /// Set the app handle for emitting events
    pub fn set_app_handle(&mut self, app_handle: AppHandle) {
        self.app_handle = Some(app_handle);
    }

    /// Register default hotkeys
    /// - Ctrl+Alt+P: Toggle proxy
    /// - Ctrl+Alt+M: Toggle mode
    ///
    /// Individual registrations are tolerated to fail (the OS may have another
    /// app holding that combo); we log a warning and continue so at least the
    /// remaining shortcuts are usable. Only a manager-init failure is fatal.
    pub fn register_default_hotkeys(&mut self) -> Result<(), HotkeyError> {
        self.try_register(
            HotkeyAction::ToggleProxy,
            HotKey::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyP),
            "Ctrl+Alt+P: Toggle Proxy",
        );
        self.try_register(
            HotkeyAction::ToggleMode,
            HotKey::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyM),
            "Ctrl+Alt+M: Toggle Mode",
        );

        if self.registered_keys.is_empty() {
            log::warn!("No global hotkeys were registered (all combos conflicted)");
        }
        Ok(())
    }

    fn try_register(&mut self, action: HotkeyAction, hotkey: HotKey, description: &str) {
        match self.manager.register(hotkey) {
            Ok(()) => {
                self.registered_keys.push(HotkeyConfig {
                    action,
                    hotkey,
                    description: description.to_string(),
                });
                log::info!("Registered global hotkey: {}", description);
            }
            Err(e) => {
                log::warn!(
                    "Skipping global hotkey '{}' — another app likely owns it: {}",
                    description,
                    e
                );
            }
        }
    }

    /// Register a custom hotkey
    pub fn register_hotkey(
        &mut self,
        action: HotkeyAction,
        modifiers: Option<Modifiers>,
        key: Code,
        description: String,
    ) -> Result<(), HotkeyError> {
        let hotkey = HotKey::new(modifiers, key);
        self.manager
            .register(hotkey)
            .map_err(|e| HotkeyError::RegistrationFailed(e.to_string()))?;

        self.registered_keys.push(HotkeyConfig {
            action,
            hotkey,
            description,
        });

        Ok(())
    }

    /// Unregister all hotkeys
    pub fn unregister_all(&mut self) -> Result<(), HotkeyError> {
        for config in &self.registered_keys {
            self.manager
                .unregister(config.hotkey)
                .map_err(|e| HotkeyError::UnregistrationFailed(e.to_string()))?;
        }

        self.registered_keys.clear();
        log::info!("Unregistered all global hotkeys");

        Ok(())
    }

    /// Get list of registered hotkeys
    pub fn get_registered_hotkeys(&self) -> &[HotkeyConfig] {
        &self.registered_keys
    }

    /// Start listening for hotkey events
    /// This spawns a new thread that listens for hotkey events
    pub fn start_listener<F>(&self, callback: F)
    where
        F: Fn(HotkeyAction) + Send + 'static,
    {
        let registered_keys = self.registered_keys.clone();

        thread::spawn(move || {
            let receiver = GlobalHotKeyEvent::receiver();

            log::info!("Global hotkey listener started");

            loop {
                if let Ok(event) = receiver.recv() {
                    // Find which action corresponds to this hotkey
                    for config in &registered_keys {
                        if config.hotkey.id() == event.id {
                            log::info!("Hotkey triggered: {}", config.description);
                            callback(config.action);
                            break;
                        }
                    }
                }
            }
        });
    }

    /// Emit a hotkey event to the frontend
    pub fn emit_hotkey_event(&self, action: HotkeyAction) {
        if let Some(ref app_handle) = self.app_handle {
            let event_name = match action {
                HotkeyAction::ToggleProxy => "hotkey-toggle-proxy",
                HotkeyAction::ToggleMode => "hotkey-toggle-mode",
            };

            if let Err(e) = app_handle.emit(event_name, ()) {
                log::error!("Failed to emit hotkey event: {}", e);
            }
        }
    }
}

impl Drop for HotkeyManager {
    fn drop(&mut self) {
        if let Err(e) = self.unregister_all() {
            log::error!("Failed to unregister hotkeys on drop: {}", e);
        }
    }
}

/// Initialize global hotkeys with default settings. The listener thread
/// forwards each press to the frontend as a Tauri event (`hotkey-toggle-proxy`
/// / `hotkey-toggle-mode`) — the UI subscribes and dispatches the actual
/// action through the Mode Coordinator.
pub fn init_hotkeys(app_handle: AppHandle) -> Result<HotkeyManager, HotkeyError> {
    let mut manager = HotkeyManager::new()?;
    manager.set_app_handle(app_handle.clone());
    manager.register_default_hotkeys()?;

    // Start the listener — clone the registered keys (cheap, they're tiny)
    // into the worker thread so it can map ids back to actions without
    // borrowing the manager.
    let registered = manager.get_registered_hotkeys().to_vec();
    thread::spawn(move || {
        let receiver = GlobalHotKeyEvent::receiver();
        log::info!("Global hotkey listener started");
        loop {
            let Ok(event) = receiver.recv() else { break };
            // Only fire on Pressed; Released would double-trigger.
            if event.state != global_hotkey::HotKeyState::Pressed {
                continue;
            }
            for config in &registered {
                if config.hotkey.id() == event.id {
                    let event_name = match config.action {
                        HotkeyAction::ToggleProxy => "hotkey-toggle-proxy",
                        HotkeyAction::ToggleMode => "hotkey-toggle-mode",
                    };
                    if let Err(e) = app_handle.emit(event_name, ()) {
                        log::warn!("Failed to emit {}: {}", event_name, e);
                    } else {
                        log::info!("Hotkey fired: {}", config.description);
                    }
                    break;
                }
            }
        }
    });

    Ok(manager)
}

/// Command to get registered hotkeys (for frontend)
#[tauri::command]
pub fn get_hotkeys(
    state: tauri::State<'_, std::sync::Mutex<HotkeyManager>>,
) -> Result<Vec<String>, String> {
    let manager = state.lock().map_err(|e| e.to_string())?;
    let descriptions: Vec<String> = manager
        .get_registered_hotkeys()
        .iter()
        .map(|c| c.description.clone())
        .collect();
    Ok(descriptions)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hotkey_manager_creation() {
        let manager = HotkeyManager::new();
        assert!(manager.is_ok());
    }

    #[test]
    fn test_hotkey_action_enum() {
        let actions = vec![HotkeyAction::ToggleProxy, HotkeyAction::ToggleMode];
        assert_eq!(actions.len(), 2);
        assert!(actions.contains(&HotkeyAction::ToggleProxy));
        assert!(actions.contains(&HotkeyAction::ToggleMode));
    }
}
