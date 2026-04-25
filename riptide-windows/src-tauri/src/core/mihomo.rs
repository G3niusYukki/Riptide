//! mihomo sidecar process management

use std::process::{Child, Command, Stdio};
use std::fs;
use tauri::AppHandle;
use tokio::sync::Mutex;

use crate::core::mihomo_api::MihomoApiClient;

pub struct MihomoManager {
    app_handle: AppHandle,
    process: Mutex<Option<Child>>,
    api_port: Mutex<u16>,
    api_secret: Mutex<Option<String>>,
}

impl MihomoManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            app_handle,
            process: Mutex::new(None),
            api_port: Mutex::new(9090), // Default mihomo API port
            api_secret: Mutex::new(None),
        }
    }

    /// Start mihomo process
    pub async fn start(&self) -> anyhow::Result<()> {
        let mut process = self.process.lock().await;

        if process.is_some() {
            return Err(anyhow::anyhow!("mihomo is already running"));
        }

        // Get mihomo binary path
        let mihomo_path = crate::utils::dirs::get_mihomo_binary_path(&self.app_handle)?;
        let config_path = crate::utils::dirs::get_config_path(&self.app_handle)?;
        let app_data = crate::utils::dirs::get_app_data_dir(&self.app_handle)?;

        // Open log file for mihomo stdout/stderr
        let log_dir = crate::utils::dirs::get_logs_dir(&self.app_handle)?;
        let log_file = log_dir.join("mihomo.log");
        let stdout_file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_file)?;

        // Start mihomo process with stdout/stderr redirected to log file
        let child = Command::new(&mihomo_path)
            .arg("-f")
            .arg(&config_path)
            .arg("-d")
            .arg(app_data)
            .stdout(Stdio::from(stdout_file.try_clone()?))
            .stderr(Stdio::from(stdout_file))
            .spawn()?;

        *process = Some(child);
        log::info!("mihomo started (logs: {:?})", log_file);

        // Wait a moment for mihomo to start its API
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

        Ok(())
    }

    /// Stop mihomo process
    pub async fn stop(&self) -> anyhow::Result<()> {
        let mut process = self.process.lock().await;
        
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
        let mut process = self.process.lock().await;
        if let Some(ref mut child) = *process {
            // Try to check if process is still alive
            // On Windows, we can check by trying to get exit code
            matches!(child.try_wait(), Ok(None))
        } else {
            false
        }
    }

    /// Get the API client for making requests to mihomo
    pub async fn get_api_client(&self) -> anyhow::Result<MihomoApiClient> {
        let port = *self.api_port.lock().await;
        let secret = self.api_secret.lock().await.clone();
        let base_url = format!("http://127.0.0.1:{}", port);
        
        Ok(MihomoApiClient::new(base_url, secret))
    }

    /// Update API configuration (port and secret)
    pub async fn set_api_config(&self, port: u16, secret: Option<String>) {
        *self.api_port.lock().await = port;
        *self.api_secret.lock().await = secret;
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
