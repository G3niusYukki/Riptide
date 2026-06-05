//! Windows Service control for the RiptideTUN service.
//!
//! The service binary lives in `riptide-tun-service.exe` (built from
//! `src/bin/tun_service.rs`) and runs as LocalSystem. The UI talks to it
//! entirely via:
//!   - the on-disk `%PROGRAMDATA%\Riptide\service.conf` (which we write here)
//!   - the SCM API (install/uninstall/start/stop/query)
//!   - mihomo's REST API on 127.0.0.1:9090 (once running)
//!
//! Installation requires admin. The UI must run this from an elevated context;
//! the launcher uses ShellExecute(verb=runas) to trigger the UAC prompt once.

use serde::Serialize;
use std::ffi::OsStr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex as StdMutex, OnceLock};

use crate::core::logbook::{LogCategory, LogEntry, LogLevel, LogbookWriter};
use windows_service::{
    service::{
        ServiceAccess, ServiceErrorControl, ServiceInfo, ServiceStartType, ServiceState,
        ServiceType,
    },
    service_manager::{ServiceManager, ServiceManagerAccess},
};

const SERVICE_NAME: &str = "RiptideTUN";
const SERVICE_DISPLAY_NAME: &str = "Riptide TUN Service";
const SERVICE_DESCRIPTION: &str =
    "Runs the mihomo proxy core for Riptide's TUN mode with SYSTEM privileges.";

/// Module-level writer slot — the service module is a bag of free
/// functions called from commands; the writer is keyed off a `OnceLock`
/// in module scope so the call sites can `log_event` without holding
/// state on a struct.
static SERVICE_LOGBOOK: OnceLock<StdMutex<Option<Arc<LogbookWriter>>>> = OnceLock::new();

fn service_cell() -> &'static StdMutex<Option<Arc<LogbookWriter>>> {
    SERVICE_LOGBOOK.get_or_init(|| StdMutex::new(None))
}

/// Install the diagnostic Logbook writer for the TUN service control
/// module. Called once at app startup, right after
/// `AppState::install_logbook_writer`.
pub fn set_logbook_writer(writer: Option<Arc<LogbookWriter>>) {
    if let Ok(mut g) = service_cell().lock() {
        *g = writer;
    }
}

#[allow(dead_code)]
fn log_event(level: LogLevel, message: impl Into<String>) {
    let Some(writer) = service_cell().lock().ok().and_then(|g| g.clone()) else {
        return;
    };
    writer.send(LogEntry::new(level, LogCategory::Service, message));
}

/// Status reported back to the UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ServiceStatusKind {
    NotInstalled,
    Stopped,
    StartPending,
    Running,
    StopPending,
    Paused,
    PausePending,
    ContinuePending,
    Unknown,
}

impl From<ServiceState> for ServiceStatusKind {
    fn from(state: ServiceState) -> Self {
        match state {
            ServiceState::Stopped => Self::Stopped,
            ServiceState::StartPending => Self::StartPending,
            ServiceState::StopPending => Self::StopPending,
            ServiceState::Running => Self::Running,
            ServiceState::ContinuePending => Self::ContinuePending,
            ServiceState::PausePending => Self::PausePending,
            ServiceState::Paused => Self::Paused,
        }
    }
}

/// Service launch parameters serialized to `%PROGRAMDATA%\Riptide\service.conf`.
#[derive(Debug, Clone, Serialize)]
pub struct ServiceLaunchConfig {
    pub mihomo_path: PathBuf,
    pub config_path: PathBuf,
    pub working_dir: PathBuf,
}

/// Path to the service launch config (LocalSystem-readable).
pub fn service_config_path() -> PathBuf {
    let programdata = std::env::var_os("PROGRAMDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("C:\\ProgramData"));
    programdata.join("Riptide").join("service.conf")
}

/// Write the service launch config. Must be called before `start_service()`
/// — otherwise the service binary exits with code 101 (missing config).
pub fn write_service_config(cfg: &ServiceLaunchConfig) -> anyhow::Result<()> {
    let path = service_config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(cfg)?;
    // Atomic-ish: write to sibling tmp, then rename.
    let tmp = path.with_extension("conf.tmp");
    std::fs::write(&tmp, json)?;
    std::fs::rename(&tmp, &path)?;
    log::info!("Wrote service launch config to {:?}", path);
    Ok(())
}

/// Resolve the path to `riptide-tun-service.exe`, assumed to sit next to the
/// UI executable. In dev (`cargo run`), Cargo places both in `target/debug/`.
pub fn service_binary_path() -> anyhow::Result<PathBuf> {
    let exe = std::env::current_exe()?;
    let dir = exe
        .parent()
        .ok_or_else(|| anyhow::anyhow!("Could not resolve current exe parent"))?;
    let candidate = dir.join("riptide-tun-service.exe");
    if !candidate.exists() {
        return Err(anyhow::anyhow!(
            "Service binary not found at {:?}",
            candidate
        ));
    }
    Ok(candidate)
}

/// Install the service. Requires elevation; surfaces a friendly error otherwise.
pub fn install_service() -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(
        None::<&str>,
        ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE,
    )
    .map_err(map_scm_error)?;

    let binary = service_binary_path()?;

    let info = ServiceInfo {
        name: std::ffi::OsString::from(SERVICE_NAME),
        display_name: std::ffi::OsString::from(SERVICE_DISPLAY_NAME),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::OnDemand,
        error_control: ServiceErrorControl::Normal,
        executable_path: binary,
        launch_arguments: vec![],
        dependencies: vec![],
        account_name: None, // LocalSystem
        account_password: None,
    };

    let service = manager
        .create_service(&info, ServiceAccess::CHANGE_CONFIG)
        .map_err(map_scm_error)?;

    // Best-effort description — failure here doesn't justify rolling back the install.
    if let Err(e) = service.set_description(SERVICE_DESCRIPTION) {
        log::warn!("Failed to set service description: {}", e);
    }

    log::info!("Service '{}' installed", SERVICE_NAME);
    Ok(())
}

pub fn uninstall_service() -> anyhow::Result<()> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).map_err(map_scm_error)?;
    let service = manager
        .open_service(SERVICE_NAME, ServiceAccess::DELETE | ServiceAccess::STOP | ServiceAccess::QUERY_STATUS)
        .map_err(map_scm_error)?;
    // Best-effort stop before delete so a running instance gets cleaned up.
    if let Ok(status) = service.query_status() {
        if status.current_state == ServiceState::Running {
            let _ = service.stop();
        }
    }
    service.delete().map_err(map_scm_error)?;
    log::info!("Service '{}' uninstalled", SERVICE_NAME);
    Ok(())
}

pub fn start_service() -> anyhow::Result<()> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).map_err(map_scm_error)?;
    let service = manager
        .open_service(SERVICE_NAME, ServiceAccess::START | ServiceAccess::QUERY_STATUS)
        .map_err(map_scm_error)?;
    service.start(&[] as &[&OsStr]).map_err(map_scm_error)?;
    log::info!("Service '{}' start requested", SERVICE_NAME);
    Ok(())
}

pub fn stop_service() -> anyhow::Result<()> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT).map_err(map_scm_error)?;
    let service = manager
        .open_service(SERVICE_NAME, ServiceAccess::STOP)
        .map_err(map_scm_error)?;
    service.stop().map_err(map_scm_error)?;
    log::info!("Service '{}' stop requested", SERVICE_NAME);
    Ok(())
}

pub fn query_status() -> ServiceStatusKind {
    let manager = match ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
    {
        Ok(m) => m,
        Err(_) => return ServiceStatusKind::Unknown,
    };
    let service = match manager.open_service(SERVICE_NAME, ServiceAccess::QUERY_STATUS) {
        Ok(s) => s,
        Err(windows_service::Error::Winapi(io_err))
            if io_err.raw_os_error() == Some(1060 /* ERROR_SERVICE_DOES_NOT_EXIST */) =>
        {
            return ServiceStatusKind::NotInstalled;
        }
        Err(_) => return ServiceStatusKind::Unknown,
    };
    service
        .query_status()
        .map(|s| ServiceStatusKind::from(s.current_state))
        .unwrap_or(ServiceStatusKind::Unknown)
}

pub fn is_service_installed() -> bool {
    !matches!(query_status(), ServiceStatusKind::NotInstalled | ServiceStatusKind::Unknown)
}

/// Translate the windows-service error types into anyhow with a hint about
/// elevation when the OS returns ERROR_ACCESS_DENIED (5).
fn map_scm_error(err: windows_service::Error) -> anyhow::Error {
    if let windows_service::Error::Winapi(ref io_err) = err {
        if io_err.raw_os_error() == Some(5) {
            return anyhow::anyhow!(
                "Access denied. Service install/uninstall requires administrator privileges."
            );
        }
    }
    anyhow::anyhow!("{}", err)
}

/// Convenience: build a `ServiceLaunchConfig` from the app handle by resolving
/// mihomo path + config path through the existing `utils::dirs` helpers.
pub fn service_launch_config_from_app(
    app_handle: &tauri::AppHandle,
) -> anyhow::Result<ServiceLaunchConfig> {
    Ok(ServiceLaunchConfig {
        mihomo_path: crate::utils::dirs::get_mihomo_binary_path(app_handle)?,
        config_path: crate::utils::dirs::get_config_path(app_handle)?,
        working_dir: crate::utils::dirs::get_app_data_dir(app_handle)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn service_config_path_under_programdata() {
        let p = service_config_path();
        let s = p.to_string_lossy();
        assert!(s.contains("Riptide"));
        assert!(s.contains("service.conf"));
    }

    #[test]
    fn service_status_kind_is_serializable() {
        let json = serde_json::to_string(&ServiceStatusKind::NotInstalled).unwrap();
        assert_eq!(json, "\"not_installed\"");
    }
}
