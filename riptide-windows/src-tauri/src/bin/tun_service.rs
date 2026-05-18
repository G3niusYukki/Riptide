// Riptide TUN Service — a tiny Windows service that wraps mihomo with
// SYSTEM-level privileges so TUN device creation succeeds without UAC on every
// app launch.
//
// Flow:
//   1. SCM launches this binary with no args (the service entry is the only path).
//   2. We register a service handler that responds to Stop/Shutdown.
//   3. On start, we read `%PROGRAMDATA%\Riptide\service.conf` (JSON with
//      `mihomo_path`, `config_path`, `working_dir`) — written by the UI app
//      before calling StartService.
//   4. We spawn `mihomo -f <config> -d <dir>` and watch the child. If the child
//      exits unexpectedly, the service exits non-zero so SCM marks it failed.
//   5. On Stop, we kill the child and exit cleanly.
//
// The UI continues to talk to mihomo's REST API on 127.0.0.1:9090 — the
// service has no IPC surface of its own.

#![cfg_attr(not(target_os = "windows"), allow(dead_code))]

#[cfg(target_os = "windows")]
fn main() -> windows_service::Result<()> {
    use windows_service::service_dispatcher;
    service_dispatcher::start(SERVICE_NAME, ffi_service_main)
}

#[cfg(not(target_os = "windows"))]
fn main() {
    eprintln!("riptide-tun-service is Windows-only.");
    std::process::exit(1);
}

#[cfg(target_os = "windows")]
const SERVICE_NAME: &str = "RiptideTUN";

#[cfg(target_os = "windows")]
windows_service::define_windows_service!(ffi_service_main, service_main);

#[cfg(target_os = "windows")]
fn service_main(_args: Vec<std::ffi::OsString>) {
    if let Err(e) = run_service() {
        // Logging at this layer is best-effort — service init errors land in
        // the Windows Event Viewer via SetServiceStatus exit codes anyway.
        eprintln!("riptide-tun-service: fatal: {}", e);
    }
}

#[cfg(target_os = "windows")]
fn run_service() -> anyhow::Result<()> {
    use std::sync::mpsc;
    use std::time::Duration;
    use windows_service::service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    };
    use windows_service::service_control_handler::{self, ServiceControlHandlerResult};

    let (shutdown_tx, shutdown_rx) = mpsc::channel::<()>();

    // Register the SCM callback before doing any heavy work — SCM will time us
    // out if we don't transition to Running within ~30s.
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop | ServiceControl::Shutdown => {
                let _ = shutdown_tx.send(());
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };
    let status_handle = service_control_handler::register(SERVICE_NAME, event_handler)?;

    let set_status = |state: ServiceState, exit_code: ServiceExitCode| {
        let _ = status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: state,
            controls_accepted: ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
            exit_code,
            checkpoint: 0,
            wait_hint: Duration::from_secs(5),
            process_id: None,
        });
    };

    set_status(ServiceState::StartPending, ServiceExitCode::Win32(0));

    // Read the service launch config written by the UI.
    let svc_conf = ServiceConfig::load().map_err(|e| {
        set_status(
            ServiceState::Stopped,
            ServiceExitCode::ServiceSpecific(101), // 101 = missing config
        );
        anyhow::anyhow!("Failed to load service config: {}", e)
    })?;

    let mut child = std::process::Command::new(&svc_conf.mihomo_path)
        .arg("-f")
        .arg(&svc_conf.config_path)
        .arg("-d")
        .arg(&svc_conf.working_dir)
        // Avoid attaching a console window when running under SCM.
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| {
            set_status(
                ServiceState::Stopped,
                ServiceExitCode::ServiceSpecific(102), // 102 = mihomo spawn failed
            );
            anyhow::anyhow!("Failed to spawn mihomo: {}", e)
        })?;

    set_status(ServiceState::Running, ServiceExitCode::Win32(0));

    // Watch loop: wait for either SCM stop OR mihomo to exit.
    loop {
        // SCM-initiated stop. Kill the child and bail.
        if shutdown_rx.recv_timeout(Duration::from_millis(500)).is_ok() {
            let _ = child.kill();
            let _ = child.wait();
            break;
        }
        // mihomo died on its own. Treat as a service failure so SCM logs it.
        if let Ok(Some(status)) = child.try_wait() {
            let code = status.code().unwrap_or(-1);
            set_status(
                ServiceState::Stopped,
                ServiceExitCode::ServiceSpecific(code as u32),
            );
            return Err(anyhow::anyhow!(
                "mihomo exited unexpectedly with code {}",
                code
            ));
        }
    }

    set_status(ServiceState::Stopped, ServiceExitCode::Win32(0));
    Ok(())
}

#[cfg(target_os = "windows")]
#[derive(serde::Deserialize)]
struct ServiceConfig {
    mihomo_path: std::path::PathBuf,
    config_path: std::path::PathBuf,
    working_dir: std::path::PathBuf,
}

#[cfg(target_os = "windows")]
impl ServiceConfig {
    fn load() -> anyhow::Result<Self> {
        let path = service_config_path();
        let contents = std::fs::read_to_string(&path)
            .map_err(|e| anyhow::anyhow!("Reading {:?}: {}", path, e))?;
        let cfg: ServiceConfig = serde_json::from_str(&contents)?;
        Ok(cfg)
    }
}

/// Location of the service's launch config (written by the UI installer).
/// Lives under `%PROGRAMDATA%` because the service runs as SYSTEM and may not
/// see the launching user's `%APPDATA%`.
#[cfg(target_os = "windows")]
fn service_config_path() -> std::path::PathBuf {
    let programdata = std::env::var_os("PROGRAMDATA")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("C:\\ProgramData"));
    programdata.join("Riptide").join("service.conf")
}
