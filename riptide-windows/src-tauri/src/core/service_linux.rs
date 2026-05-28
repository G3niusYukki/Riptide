//! Linux stub for the Windows service module.
//! On Linux there is no SCM; TUN runs directly in-process via tokio-tun.

#[derive(Debug, Clone, serde::Serialize)]
pub enum ServiceStatusKind {
    Running,
    Stopped,
    Unknown,
}

pub fn status() -> ServiceStatusKind {
    ServiceStatusKind::Unknown
}

pub fn install() -> anyhow::Result<()> {
    anyhow::bail!("Service install not supported on Linux")
}

pub fn uninstall() -> anyhow::Result<()> {
    Ok(())
}
