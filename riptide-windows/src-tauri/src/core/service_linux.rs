//! Linux stub for the Windows service module.
//! On Linux there is no SCM; TUN runs directly in-process via tokio-tun.

#[derive(Debug, Clone, serde::Serialize)]
pub enum ServiceStatusKind {
    Running,
    Stopped,
    Unknown,
}

pub fn query_status() -> ServiceStatusKind {
    ServiceStatusKind::Unknown
}
pub fn install_service() -> anyhow::Result<()> {
    anyhow::bail!("Service not supported on Linux")
}
pub fn uninstall_service() -> anyhow::Result<()> {
    Ok(())
}
pub fn start_service() -> anyhow::Result<()> {
    anyhow::bail!("Service not supported on Linux")
}
pub fn stop_service() -> anyhow::Result<()> {
    Ok(())
}
pub fn write_service_config(_cfg: &()) -> anyhow::Result<()> {
    Ok(())
}
pub fn service_launch_config_from_app(_handle: &tauri::AppHandle) -> anyhow::Result<()> {
    Ok(())
}
