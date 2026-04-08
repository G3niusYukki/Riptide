//! mihomo sidecar process management

use std::process::{Child, Command};
use std::sync::Mutex;
use tauri::AppHandle;
use tauri_plugin_shell::ShellExt;

pub struct MihomoManager {
    app_handle: AppHandle,
    process: Mutex<Option<Child>>,
}

impl MihomoManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            app_handle,
            process: Mutex::new(None),
        }
    }

    /// Start mihomo process
    pub async fn start(&self) -> anyhow::Result<()> {
        let mut process = self.process.lock().unwrap();
        
        if process.is_some() {
            return Err(anyhow::anyhow!("mihomo is already running"));
        }

        // Get mihomo binary path
        let mihomo_path = crate::utils::dirs::get_mihomo_binary_path(&self.app_handle)?;
        let config_path = crate::utils::dirs::get_config_path(&self.app_handle)?;

        // Start mihomo process
        let child = Command::new(&mihomo_path)
            .arg("-f")
            .arg(&config_path)
            .arg("-d")
            .arg(crate::utils::dirs::get_app_data_dir(&self.app_handle)?)
            .spawn()?;

        *process = Some(child);
        log::info!("mihomo started with PID: {:?}", process.as_ref().map(|p| p.id()));
        
        Ok(())
    }

    /// Stop mihomo process
    pub async fn stop(&self) -> anyhow::Result<()> {
        let mut process = self.process.lock().unwrap();
        
        if let Some(mut child) = process.take() {
            child.kill()?;
            log::info!("mihomo stopped");
        }
        
        Ok(())
    }

    /// Restart mihomo process
    pub async fn restart(&self) -> anyhow::Result<()> {
        self.stop().await?;
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        self.start().await
    }

    /// Check if mihomo is running
    pub async fn is_running(&self) -> bool {
        let mut process = self.process.lock().unwrap();
        if let Some(ref mut child) = *process {
            // Try to check if process is still alive
            // On Windows, we can check by trying to get exit code
            matches!(child.try_wait(), Ok(None))
        } else {
            false
        }
    }

    /// Generate mihomo config from profile
    pub fn generate_config(&self, profile_content: &str) -> anyhow::Result<String> {
        // TODO: Parse profile and generate mihomo config
        // For now, just return the profile content as-is
        Ok(profile_content.to_string())
    }
}

/// Check if mihomo binary exists
pub fn check_mihomo_binary(app_handle: &AppHandle) -> bool {
    crate::utils::dirs::get_mihomo_binary_path(app_handle)
        .map(|p| p.exists())
        .unwrap_or(false)
}
