//! Windows-specific proxy process manager
//!
//! This module provides Windows-optimized process management for the mihomo proxy,
//! including better process tracking and Windows-specific process control.

use std::process::{Command, Child};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::AppHandle;

/// Errors that can occur when managing the Windows proxy
#[derive(Debug, thiserror::Error)]
pub enum ProxyError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    #[error("Process is not running")]
    ProcessNotRunning,
    
    #[error("Process already running")]
    ProcessAlreadyRunning,
    
    #[error("Failed to get process exit code")]
    ProcessExitCodeError,
}

/// Windows-specific proxy manager for mihomo process
/// 
/// This manager handles the lifecycle of the mihomo proxy process on Windows,
/// providing Windows-optimized process control and monitoring.
pub struct WindowsProxyManager {
    mihomo_path: PathBuf,
    config_path: PathBuf,
    working_dir: PathBuf,
    process_handle: Mutex<Option<Child>>,
}

impl WindowsProxyManager {
    /// Create a new Windows proxy manager
    /// 
    /// # Arguments
    /// * `mihomo_path` - Path to the mihomo executable
    /// * `config_path` - Path to the mihomo configuration file
    /// * `working_dir` - Working directory for the process
    pub fn new(mihomo_path: PathBuf, config_path: PathBuf, working_dir: PathBuf) -> Self {
        Self {
            mihomo_path,
            config_path,
            working_dir,
            process_handle: Mutex::new(None),
        }
    }

    /// Create a new Windows proxy manager from app handle
    /// 
    /// Automatically resolves paths using the app's data directory
    pub fn from_app_handle(app_handle: &AppHandle) -> anyhow::Result<Self> {
        let mihomo_path = crate::utils::dirs::get_mihomo_binary_path(app_handle)?;
        let config_path = crate::utils::dirs::get_config_path(app_handle)?;
        let working_dir = crate::utils::dirs::get_app_data_dir(app_handle)?;
        
        Ok(Self::new(mihomo_path, config_path, working_dir))
    }

    /// Start the mihomo proxy process
    /// 
    /// # Returns
    /// * `Ok(())` if the process started successfully
    /// * `Err(ProxyError::ProcessAlreadyRunning)` if a process is already running
    /// * `Err(ProxyError::Io)` if there was an IO error starting the process
    pub fn start(&self) -> Result<(), ProxyError> {
        let mut handle = self.process_handle.lock().unwrap();
        
        if handle.is_some() {
            // Check if the existing process is actually still running
            if Self::child_alive(&handle) {
                return Err(ProxyError::ProcessAlreadyRunning);
            }
            // Process died, clear the handle
            *handle = None;
        }

        log::info!("Starting mihomo process: {:?}", self.mihomo_path);
        log::info!("Config path: {:?}", self.config_path);
        log::info!("Working directory: {:?}", self.working_dir);

        let child = Command::new(&self.mihomo_path)
            .arg("-f")
            .arg(&self.config_path)
            .arg("-d")
            .arg(&self.working_dir)
            .creation_flags(0x08000000) // CREATE_NO_WINDOW - don't show console window
            .spawn()?;

        log::info!("mihomo started with PID: {:?}", child.id());
        *handle = Some(child);
        Ok(())
    }

    /// Stop the mihomo proxy process
    /// 
    /// # Returns
    /// * `Ok(())` if the process was stopped (or wasn't running)
    /// * `Err(ProxyError::Io)` if there was an error killing the process
    pub fn stop(&self) -> Result<(), ProxyError> {
        let mut handle = self.process_handle.lock().unwrap();
        
        if let Some(mut child) = handle.take() {
            log::info!("Stopping mihomo process (PID: {:?})", child.id());
            
            // Try to kill the process
            match child.kill() {
                Ok(()) => {
                    // Wait for the process to fully terminate
                    let _ = child.wait();
                    log::info!("mihomo process stopped");
                }
                Err(e) => {
                    log::warn!("Error killing mihomo process: {}", e);
                    // If the process is already dead, that's fine
                    if e.kind() != std::io::ErrorKind::InvalidInput {
                        return Err(ProxyError::Io(e));
                    }
                }
            }
        } else {
            log::debug!("mihomo process was not running");
        }
        
        Ok(())
    }

    /// Check if the proxy process is currently running
    pub fn is_running(&self) -> bool {
        let handle = self.process_handle.lock().unwrap();
        Self::child_alive(&handle)
    }

    /// Get the process ID if the process is running
    pub fn get_pid(&self) -> Option<u32> {
        let handle = self.process_handle.lock().unwrap();
        handle.as_ref().map(|c| c.id())
    }

    /// Restart the proxy process
    pub fn restart(&self) -> Result<(), ProxyError> {
        self.stop()?;
        // Small delay to ensure process cleanup
        std::thread::sleep(std::time::Duration::from_millis(500));
        self.start()
    }

    /// Internal helper to check if a process is alive
    fn child_alive(handle: &Option<Child>) -> bool {
        match handle.as_ref() {
            Some(child) => {
                // On Windows, try_wait returns Ok(None) if process is still running
                let mut child_ref = child;
                unsafe {
                    // try_wait requires &mut — we're the only thread accessing right now
                    matches!((&mut *(child_ref as *const Child as *mut Child)).try_wait(), Ok(None))
                }
            }
            None => false,
        }
    }
}

impl Drop for WindowsProxyManager {
    fn drop(&mut self) {
        // Ensure process is cleaned up when manager is dropped
        let _ = self.stop();
    }
}

/// Builder for WindowsProxyManager
pub struct WindowsProxyManagerBuilder {
    mihomo_path: Option<PathBuf>,
    config_path: Option<PathBuf>,
    working_dir: Option<PathBuf>,
}

impl WindowsProxyManagerBuilder {
    pub fn new() -> Self {
        Self {
            mihomo_path: None,
            config_path: None,
            working_dir: None,
        }
    }

    pub fn mihomo_path(mut self, path: PathBuf) -> Self {
        self.mihomo_path = Some(path);
        self
    }

    pub fn config_path(mut self, path: PathBuf) -> Self {
        self.config_path = Some(path);
        self
    }

    pub fn working_dir(mut self, path: PathBuf) -> Self {
        self.working_dir = Some(path);
        self
    }

    pub fn build(self) -> anyhow::Result<WindowsProxyManager> {
        let mihomo_path = self.mihomo_path
            .ok_or_else(|| anyhow::anyhow!("mihomo_path is required"))?;
        let config_path = self.config_path
            .ok_or_else(|| anyhow::anyhow!("config_path is required"))?;
        let working_dir = self.working_dir
            .unwrap_or_else(|| std::env::temp_dir());

        Ok(WindowsProxyManager::new(mihomo_path, config_path, working_dir))
    }
}

impl Default for WindowsProxyManagerBuilder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_error_display() {
        let io_err = ProxyError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "file not found"
        ));
        assert!(io_err.to_string().contains("IO error"));
        
        let not_running = ProxyError::ProcessNotRunning;
        assert_eq!(not_running.to_string(), "Process is not running");
        
        let already_running = ProxyError::ProcessAlreadyRunning;
        assert_eq!(already_running.to_string(), "Process already running");
    }

    #[test]
    fn test_builder_missing_fields() {
        let result = WindowsProxyManagerBuilder::new().build();
        assert!(result.is_err());
        
        let result = WindowsProxyManagerBuilder::new()
            .mihomo_path(PathBuf::from("/test/mihomo.exe"))
            .build();
        assert!(result.is_err()); // Missing config_path
    }
}
