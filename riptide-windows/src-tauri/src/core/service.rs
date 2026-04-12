//! Windows Service for TUN mode

use windows_service::{
    service::ServiceAccess,
    service::{ServiceErrorControl, ServiceStartType, ServiceType},
    service_manager::{ServiceManager, ServiceManagerAccess},
};

const SERVICE_NAME: &str = "RiptideTUN";
const SERVICE_DISPLAY_NAME: &str = "Riptide TUN Service";

/// Install the Windows service
pub fn install_service() -> anyhow::Result<()> {
    let manager =
        ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CREATE_SERVICE)?;

    // Get the path to the current executable
    let executable_path = std::env::current_exe()?;
    let executable_path_str = executable_path.to_string_lossy();

    // Create service info
    let service_info = windows_service::service::ServiceInfo {
        name: std::ffi::OsString::from(SERVICE_NAME),
        display_name: std::ffi::OsString::from(SERVICE_DISPLAY_NAME),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::OnDemand,
        error_control: ServiceErrorControl::Normal,
        executable_path: std::path::PathBuf::from(executable_path_str.as_ref()),
        launch_arguments: vec![],
        dependencies: vec![],
        account_name: None,
        account_password: None,
    };

    let _service = manager.create_service(&service_info, ServiceAccess::START)?;

    log::info!("Service '{}' installed successfully", SERVICE_NAME);
    Ok(())
}

/// Uninstall the Windows service
pub fn uninstall_service() -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;

    let service = manager.open_service(SERVICE_NAME, ServiceAccess::DELETE)?;
    service.delete()?;

    log::info!("Service '{}' uninstalled successfully", SERVICE_NAME);
    Ok(())
}

/// Start the Windows service
pub fn start_service() -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;

    let service = manager.open_service(SERVICE_NAME, ServiceAccess::START)?;
    service.start(&[] as &[&std::ffi::OsStr])?;

    log::info!("Service '{}' started", SERVICE_NAME);
    Ok(())
}

/// Stop the Windows service
pub fn stop_service() -> anyhow::Result<()> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;

    let service = manager.open_service(SERVICE_NAME, ServiceAccess::STOP)?;
    service.stop()?;

    log::info!("Service '{}' stopped", SERVICE_NAME);
    Ok(())
}

/// Check if the service is installed
pub fn is_service_installed() -> bool {
    let manager = match ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
    {
        Ok(m) => m,
        Err(_) => return false,
    };

    manager
        .open_service(SERVICE_NAME, ServiceAccess::QUERY_STATUS)
        .is_ok()
}
