//! Windows TUN mode support using Wintun driver
//!
//! This module provides TUN (virtual network interface) functionality on Windows
//! using the wintun library (Rust wrapper for WireGuard's Wintun driver).
//! Reference: mihomo's Windows TUN implementation and Clash Verge Rev approach.

use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use std::path::PathBuf;

/// Errors that can occur when managing Windows TUN
#[derive(Debug, thiserror::Error)]
pub enum TUNError {
    #[error("Adapter creation failed: {0}")]
    AdapterCreationFailed(String),

    #[error("Session creation failed: {0}")]
    SessionCreationFailed(String),

    #[error("Wintun driver not installed")]
    DriverNotInstalled,

    #[error("Invalid TUN configuration: {0}")]
    InvalidConfiguration(String),

    #[error("TUN is already running")]
    AlreadyRunning,

    #[error("TUN is not running")]
    NotRunning,

    #[error("Failed to load wintun.dll: {0}")]
    DllLoadFailed(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Packet processing error: {0}")]
    PacketProcessingError(String),
}

/// TUN adapter configuration
#[derive(Debug, Clone)]
pub struct TUNConfig {
    /// Adapter name displayed in Windows Network Connections
    pub adapter_name: String,
    /// Tunnel type identifier (e.g., "Riptide", "Mihomo")
    pub tunnel_type: String,
    /// Virtual interface IP address (e.g., "198.18.0.1")
    pub interface_ip: String,
    /// Gateway IP address (e.g., "198.18.0.2")
    pub gateway: String,
    /// MTU size for the virtual interface
    pub mtu: u16,
    /// DNS servers to use
    pub dns_servers: Vec<String>,
    /// Routes to add (CIDR notation)
    pub routes: Vec<String>,
}

impl Default for TUNConfig {
    fn default() -> Self {
        Self {
            adapter_name: "Riptide TUN".to_string(),
            tunnel_type: "Riptide".to_string(),
            interface_ip: "198.18.0.1".to_string(),
            gateway: "198.18.0.2".to_string(),
            mtu: 9000,
            dns_servers: vec!["8.8.8.8".to_string(), "8.8.4.4".to_string()],
            routes: vec!["0.0.0.0/0".to_string()], // Default route all traffic
        }
    }
}

/// Status of the TUN connection
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TUNStatus {
    /// TUN is not initialized
    Stopped,
    /// TUN adapter is created but not started
    AdapterCreated,
    /// TUN session is running
    Running,
    /// TUN is in an error state
    Error,
}

impl std::fmt::Display for TUNStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TUNStatus::Stopped => write!(f, "stopped"),
            TUNStatus::AdapterCreated => write!(f, "adapter_created"),
            TUNStatus::Running => write!(f, "running"),
            TUNStatus::Error => write!(f, "error"),
        }
    }
}

/// Windows TUN Manager
///
/// Manages the lifecycle of a Wintun virtual network adapter including:
/// - Loading the wintun.dll driver
/// - Creating the virtual adapter
/// - Starting/stopping packet processing
/// - Integration with mihomo for traffic forwarding
#[cfg(target_os = "windows")]
pub struct WindowsTUNManager {
    /// Current TUN configuration
    config: TUNConfig,
    /// Wintun adapter handle
    adapter: Option<wintun::Adapter>,
    /// Wintun session handle
    session: Option<Arc<wintun::Session>>,
    /// Channel for receiving packets from TUN
    packet_receiver: Option<mpsc::Receiver<Vec<u8>>>,
    /// Channel for sending packets to TUN
    packet_sender: Option<mpsc::Sender<Vec<u8>>>,
    /// Current running status
    status: Arc<RwLock<TUNStatus>>,
    /// Packet processing task handle
    packet_task: Option<tokio::task::JoinHandle<()>>,
    /// Path to wintun.dll
    wintun_dll_path: PathBuf,
}

#[cfg(target_os = "windows")]
impl WindowsTUNManager {
    /// Create a new Windows TUN manager with default configuration
    pub fn new(wintun_dll_path: PathBuf) -> Self {
        Self {
            config: TUNConfig::default(),
            adapter: None,
            session: None,
            packet_receiver: None,
            packet_sender: None,
            status: Arc::new(RwLock::new(TUNStatus::Stopped)),
            packet_task: None,
            wintun_dll_path,
        }
    }

    /// Create a new TUN manager with custom configuration
    pub fn with_config(wintun_dll_path: PathBuf, config: TUNConfig) -> Self {
        Self {
            config,
            adapter: None,
            session: None,
            packet_receiver: None,
            packet_sender: None,
            status: Arc::new(RwLock::new(TUNStatus::Stopped)),
            packet_task: None,
            wintun_dll_path,
        }
    }

    /// Create the TUN adapter
    ///
    /// This loads the wintun.dll and creates a virtual network adapter in Windows.
    pub fn create_adapter(&mut self) -> Result<(), TUNError> {
        // Check if already running
        let status = *self.status.blocking_read();
        if status != TUNStatus::Stopped {
            return Err(TUNError::AlreadyRunning);
        }

        // Tell wintun where to find the DLL
        log::info!("Setting WINTUN_COMPATIBLE_DLL_PATH to: {:?}", self.wintun_dll_path);
        std::env::set_var("WINTUN_COMPATIBLE_DLL_PATH", &self.wintun_dll_path);

        // Create adapter with display name and tunnel type
        let adapter_name = format!("{} {}", self.config.adapter_name, self.config.tunnel_type);
        log::info!("Creating TUN adapter: {}", adapter_name);

        let adapter = unsafe {
            wintun::Adapter::create(
                &adapter_name,
                &self.config.tunnel_type,
                None, // No GUID specified - let Windows generate one
            )
            .map_err(|e| TUNError::AdapterCreationFailed(e.to_string()))?
        };

        log::info!("TUN adapter created successfully: {}", adapter_name);
        self.adapter = Some(adapter);

        // Update status
        *self.status.blocking_write() = TUNStatus::AdapterCreated;

        Ok(())
    }

    /// Start the TUN session and packet processing
    ///
    /// This starts the wintun session and spawns packet processing tasks.
    pub async fn start(&mut self) -> Result<(), TUNError> {
        let status = *self.status.read().await;
        if status == TUNStatus::Running {
            return Err(TUNError::AlreadyRunning);
        }

        // Ensure adapter is created
        if self.adapter.is_none() {
            self.create_adapter()?;
        }

        let adapter = self.adapter.as_ref()
            .ok_or_else(|| TUNError::InvalidConfiguration("Adapter not created".to_string()))?;

        // Start wintun session with 4 MiB ring capacity for best performance
        let capacity: u32 = 0x400000;
        log::info!("Starting TUN session with capacity: {}", capacity);
        let session = adapter.start_session(capacity)
            .map_err(|e| TUNError::SessionCreationFailed(e.to_string()))?;

        let session_arc = Arc::new(session);
        self.session = Some(session_arc.clone());

        // Create packet channels
        let (tx, rx) = mpsc::channel::<Vec<u8>>(1000);
        self.packet_sender = Some(tx);
        self.packet_receiver = Some(rx);

        // Update status
        *self.status.write().await = TUNStatus::Running;
        let status_clone = self.status.clone();

        // Spawn packet receive task
        let receive_task = tokio::spawn(async move {
            Self::packet_receive_loop(session_arc, status_clone).await;
        });

        self.packet_task = Some(receive_task);

        log::info!("TUN mode started successfully");
        Ok(())
    }

    /// Stop the TUN session
    ///
    /// This gracefully shuts down the wintun session and cleans up resources.
    pub async fn stop(&mut self) -> Result<(), TUNError> {
        let status = *self.status.read().await;
        if status == TUNStatus::Stopped {
            return Err(TUNError::NotRunning);
        }

        log::info!("Stopping TUN mode...");

        // Shutdown packet processing task
        if let Some(task) = self.packet_task.take() {
            task.abort();
        }

        // Shutdown session
        if let Some(session) = self.session.take() {
            // wintun session shutdown happens automatically when dropped
            drop(session);
        }

        // Update status
        *self.status.write().await = TUNStatus::Stopped;

        // Clear channels
        self.packet_sender = None;
        self.packet_receiver = None;

        // Keep adapter for reuse, but clear it if you want full cleanup:
        // self.adapter = None;

        log::info!("TUN mode stopped");
        Ok(())
    }

    /// Get current TUN status
    pub async fn get_status(&self) -> TUNStatus {
        *self.status.read().await
    }

    /// Check if TUN is currently running
    pub async fn is_running(&self) -> bool {
        *self.status.read().await == TUNStatus::Running
    }

    /// Send a packet to the TUN interface
    pub async fn send_packet(&self, packet: Vec<u8>) -> Result<(), TUNError> {
        if let Some(sender) = &self.packet_sender {
            sender.send(packet).await
                .map_err(|e| TUNError::PacketProcessingError(e.to_string()))?;
            Ok(())
        } else {
            Err(TUNError::NotRunning)
        }
    }

    /// Receive packets from the TUN interface (non-blocking)
    pub fn try_receive_packet(&mut self) -> Option<Vec<u8>> {
        if let Some(ref mut receiver) = self.packet_receiver {
            receiver.try_recv().ok()
        } else {
            None
        }
    }

    /// Get the current configuration
    pub fn get_config(&self) -> &TUNConfig {
        &self.config
    }

    /// Update configuration (only when stopped)
    pub fn set_config(&mut self, config: TUNConfig) -> Result<(), TUNError> {
        let status = *self.status.blocking_read();
        if status != TUNStatus::Stopped {
            return Err(TUNError::AlreadyRunning);
        }
        self.config = config;
        Ok(())
    }

    /// Packet receive loop - runs in background task
    async fn packet_receive_loop(
        session: Arc<wintun::Session>,
        status: Arc<RwLock<TUNStatus>>,
    ) {
        log::info!("TUN packet receive loop started");

        loop {
            // Check if we should stop
            if *status.read().await != TUNStatus::Running {
                break;
            }

            // Receive packet from wintun
            // Note: This is a blocking call, so we use spawn_blocking
            let session_clone = session.clone();
            let packet_result = tokio::task::spawn_blocking(move || {
                session_clone.receive_blocking()
            }).await;

            match packet_result {
                Ok(Ok(packet)) => {
                    // Process the packet - in real implementation, forward to mihomo
                    let packet_bytes = packet.bytes().to_vec();
                    log::debug!("Received packet from TUN: {} bytes", packet_bytes.len());

                    // Send packet to mihomo or process internally
                    // For now, just acknowledge receipt
                    drop(packet);
                }
                Ok(Err(e)) => {
                    log::warn!("Error receiving packet from TUN: {}", e);
                    tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
                }
                Err(e) => {
                    log::error!("Task panic in packet receive: {}", e);
                    break;
                }
            }
        }

        log::info!("TUN packet receive loop stopped");
    }
}

/// Non-Windows stub implementation
#[cfg(not(target_os = "windows"))]
pub struct WindowsTUNManager {
    config: TUNConfig,
    status: Arc<RwLock<TUNStatus>>,
}

#[cfg(not(target_os = "windows"))]
impl WindowsTUNManager {
    pub fn new(_wintun_dll_path: PathBuf) -> Self {
        Self {
            config: TUNConfig::default(),
            status: Arc::new(RwLock::new(TUNStatus::Stopped)),
        }
    }

    pub fn with_config(_wintun_dll_path: PathBuf, config: TUNConfig) -> Self {
        Self {
            config,
            status: Arc::new(RwLock::new(TUNStatus::Stopped)),
        }
    }

    pub fn create_adapter(&mut self) -> Result<(), TUNError> {
        Err(TUNError::DriverNotInstalled)
    }

    pub async fn start(&mut self) -> Result<(), TUNError> {
        Err(TUNError::DriverNotInstalled)
    }

    pub async fn stop(&mut self) -> Result<(), TUNError> {
        Ok(())
    }

    pub async fn get_status(&self) -> TUNStatus {
        TUNStatus::Stopped
    }

    pub async fn is_running(&self) -> bool {
        false
    }

    pub async fn send_packet(&self, _packet: Vec<u8>) -> Result<(), TUNError> {
        Err(TUNError::DriverNotInstalled)
    }

    pub fn try_receive_packet(&mut self) -> Option<Vec<u8>> {
        None
    }

    pub fn get_config(&self) -> &TUNConfig {
        &self.config
    }

    pub fn set_config(&mut self, config: TUNConfig) -> Result<(), TUNError> {
        self.config = config;
        Ok(())
    }
}

/// Builder for WindowsTUNManager
#[derive(Debug, Default)]
pub struct WindowsTUNManagerBuilder {
    wintun_dll_path: Option<PathBuf>,
    config: Option<TUNConfig>,
}

impl WindowsTUNManagerBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn wintun_dll_path(mut self, path: PathBuf) -> Self {
        self.wintun_dll_path = Some(path);
        self
    }

    pub fn config(mut self, config: TUNConfig) -> Self {
        self.config = Some(config);
        self
    }

    pub fn build(self) -> Result<WindowsTUNManager, TUNError> {
        let dll_path = self.wintun_dll_path
            .ok_or_else(|| TUNError::InvalidConfiguration("wintun_dll_path is required".to_string()))?;

        let manager = if let Some(config) = self.config {
            WindowsTUNManager::with_config(dll_path, config)
        } else {
            WindowsTUNManager::new(dll_path)
        };

        Ok(manager)
    }
}

/// DTO for TUN status serialization
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct TUNStatusDto {
    pub status: String,
    pub running: bool,
    pub adapter_name: Option<String>,
    pub interface_ip: Option<String>,
    pub gateway: Option<String>,
}

impl From<&WindowsTUNManager> for TUNStatusDto {
    fn from(manager: &WindowsTUNManager) -> Self {
        let status = manager.get_status();
        let config = manager.get_config();

        Self {
            status: format!("{}", status),
            running: status == TUNStatus::Running,
            adapter_name: Some(config.adapter_name.clone()),
            interface_ip: Some(config.interface_ip.clone()),
            gateway: Some(config.gateway.clone()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tun_config_default() {
        let config = TUNConfig::default();
        assert_eq!(config.adapter_name, "Riptide TUN");
        assert_eq!(config.tunnel_type, "Riptide");
        assert_eq!(config.interface_ip, "198.18.0.1");
        assert_eq!(config.mtu, 9000);
        assert!(!config.dns_servers.is_empty());
    }

    #[test]
    fn test_tun_status_display() {
        assert_eq!(format!("{}", TUNStatus::Stopped), "stopped");
        assert_eq!(format!("{}", TUNStatus::Running), "running");
        assert_eq!(format!("{}", TUNStatus::Error), "error");
    }

    #[test]
    fn test_tun_error_display() {
        let err = TUNError::DriverNotInstalled;
        assert!(err.to_string().contains("not installed"));

        let err = TUNError::AlreadyRunning;
        assert!(err.to_string().contains("already running"));
    }

    #[test]
    fn test_builder_missing_fields() {
        let result = WindowsTUNManagerBuilder::new().build();
        assert!(result.is_err());
    }

    #[test]
    fn test_builder_with_path() {
        let result = WindowsTUNManagerBuilder::new()
            .wintun_dll_path(PathBuf::from("wintun.dll"))
            .build();
        assert!(result.is_ok());
    }

    #[test]
    fn test_config_custom() {
        let custom_config = TUNConfig {
            adapter_name: "Custom TUN".to_string(),
            tunnel_type: "Test".to_string(),
            interface_ip: "10.0.0.1".to_string(),
            gateway: "10.0.0.2".to_string(),
            mtu: 1500,
            dns_servers: vec!["1.1.1.1".to_string()],
            routes: vec!["0.0.0.0/0".to_string()],
        };

        let dto = TUNStatusDto {
            status: "stopped".to_string(),
            running: false,
            adapter_name: Some(custom_config.adapter_name.clone()),
            interface_ip: Some(custom_config.interface_ip.clone()),
            gateway: Some(custom_config.gateway.clone()),
        };

        assert_eq!(dto.adapter_name, Some("Custom TUN".to_string()));
        assert_eq!(dto.interface_ip, Some("10.0.0.1".to_string()));
    }
}
