//! mihomo sidecar process management

use std::process::{Child, Command, Stdio};
use std::fs;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;

use crate::core::mihomo_api::MihomoApiClient;
use serde_yaml;

/// Tunnel routing mode. Selects which transport mihomo exposes:
///   - `SystemProxy` — only the HTTP/SOCKS mixed-port; user/system must point at it.
///   - `Tun` — mihomo creates a TUN device and absorbs all OS traffic. Requires
///     admin (or the helper service) because TUN device creation is privileged.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum TunnelMode {
    SystemProxy,
    Tun,
}

impl Default for TunnelMode {
    fn default() -> Self {
        TunnelMode::SystemProxy
    }
}

/// TUN-specific configuration. Defaults align with mihomo's "just works on
/// Windows" preset: gvisor stack (safer than system, doesn't touch the kernel),
/// strict-route on, DNS hijacked. Override individual fields in the UI later.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TunOptions {
    pub device: String,
    pub stack: String,
    pub auto_route: bool,
    pub auto_detect_interface: bool,
    pub strict_route: bool,
    pub mtu: u32,
    pub dns_hijack: Vec<String>,
}

impl Default for TunOptions {
    fn default() -> Self {
        Self {
            device: "Riptide".to_string(),
            stack: "gvisor".to_string(),
            auto_route: true,
            auto_detect_interface: true,
            strict_route: true,
            mtu: 9000,
            dns_hijack: vec!["any:53".to_string()],
        }
    }
}

pub struct MihomoManager {
    app_handle: AppHandle,
    process: Arc<Mutex<Option<Child>>>,
    api_port: Mutex<u16>,
    api_secret: Mutex<Option<String>>,
    // Mode and TUN options are non-async-lock candidates: short-held, no awaits.
    mode: StdMutex<TunnelMode>,
    tun_options: StdMutex<TunOptions>,
    /// Set true by `stop()` so the crash watcher knows the next exit was
    /// deliberate and shouldn't surface as a crash event.
    expected_exit: Arc<StdMutex<bool>>,
}

impl MihomoManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            app_handle,
            process: Arc::new(Mutex::new(None)),
            api_port: Mutex::new(9090), // Default mihomo API port
            api_secret: Mutex::new(None),
            mode: StdMutex::new(TunnelMode::default()),
            tun_options: StdMutex::new(TunOptions::default()),
            expected_exit: Arc::new(StdMutex::new(false)),
        }
    }

    /// Set the tunnel mode. Takes effect on the next `write_config` + start/restart.
    pub fn set_mode(&self, mode: TunnelMode) {
        *self.mode.lock().unwrap() = mode;
    }

    pub fn current_mode(&self) -> TunnelMode {
        *self.mode.lock().unwrap()
    }

    pub fn set_tun_options(&self, options: TunOptions) {
        *self.tun_options.lock().unwrap() = options;
    }

    pub fn current_tun_options(&self) -> TunOptions {
        self.tun_options.lock().unwrap().clone()
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

        // Reset the "expected exit" flag — any exit from here on is unexpected
        // until the next stop() call sets it.
        *self.expected_exit.lock().unwrap() = false;

        // Spawn a watcher: polls try_wait every 500ms; on exit, distinguishes
        // expected vs crash and emits the appropriate event.
        let process_arc = self.process.clone();
        let expected_arc = self.expected_exit.clone();
        let app = self.app_handle.clone();
        let mode = self.current_mode();
        tokio::spawn(async move {
            watch_for_exit(process_arc, expected_arc, app, mode).await;
        });

        // Wait a moment for mihomo to start its API
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

        Ok(())
    }

    /// Stop mihomo process
    pub async fn stop(&self) -> anyhow::Result<()> {
        // Mark the upcoming exit as expected so the watcher doesn't fire a
        // crash event when it observes the process going away.
        *self.expected_exit.lock().unwrap() = true;

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

    /// Snapshot helpers used by the recovery watchdog to build an API client
    /// without holding the manager's locks across awaits.
    pub async fn api_port_snapshot(&self) -> u16 {
        *self.api_port.lock().await
    }

    pub async fn api_secret_snapshot(&self) -> Option<String> {
        self.api_secret.lock().await.clone()
    }

    /// Generate mihomo config from profile YAML, injecting runtime settings
    /// (mixed-port, external-controller, log-level, ipv6) that the user
    /// shouldn't have to manually configure. When `mode == Tun`, also injects
    /// a `tun:` block from the supplied `TunOptions` (user-supplied tun fields
    /// in the profile are merged-not-replaced: profile values win per-field).
    /// Always overlays the persisted `DnsPolicy` onto the profile's `dns:` block.
    pub fn generate_config(
        &self,
        profile_content: &str,
        mode: TunnelMode,
        tun_options: &TunOptions,
    ) -> anyhow::Result<String> {
        let mut config: crate::config::parser::ClashRawConfig =
            serde_yaml::from_str(profile_content)
                .map_err(|e| anyhow::anyhow!("Failed to parse config YAML: {}", e))?;

        // Inject runtime settings (only if not already set by the user)
        if config.mixed_port.is_none() {
            config.mixed_port = Some(7890);
        }
        if config.external_controller.is_none() {
            config.external_controller = Some("127.0.0.1:9090".to_string());
        }
        if config.log_level.is_none() {
            config.log_level = Some("info".to_string());
        }
        if config.ipv6.is_none() {
            config.ipv6 = Some(true);
        }

        match mode {
            TunnelMode::SystemProxy => {
                // Force-disable TUN if the profile shipped with it enabled, to
                // avoid a surprise admin prompt when the user picked System Proxy.
                if let Some(ref mut tun) = config.tun {
                    tun.enable = Some(false);
                }
            }
            TunnelMode::Tun => {
                let existing = config.tun.clone().unwrap_or_default();
                config.tun = Some(merge_tun(existing, tun_options));
            }
        }

        // Apply region preset first — it can prepend rules and replace the DNS
        // block wholesale. DnsPolicy below then layers per-field tweaks on top.
        let region = crate::core::region_presets::RegionState::load();
        crate::core::region_presets::apply_to_config(&mut config, region.active);

        // Stamp global TLS tricks (e.g., client-fingerprint) onto each proxy
        // before DnsPolicy — proxies are independent of the DNS block.
        let tls_tricks = crate::core::tls_tricks::TlsTricks::load();
        crate::core::tls_tricks::apply_to_config(&mut config, &tls_tricks);

        // Overlay the user-managed DNS policy. If the user hasn't enabled an
        // override, this is a no-op and the profile's dns block (if any) wins.
        let dns_policy = crate::config::dns_policy::DnsPolicy::load();
        if let Some(merged_dns) = dns_policy.apply_to(config.dns.clone()) {
            config.dns = Some(merged_dns);
        }

        serde_yaml::to_string(&config)
            .map_err(|e| anyhow::anyhow!("Failed to serialize config: {}", e))
    }

    /// Generate the merged config from a profile and write it to the path
    /// mihomo will read on launch. Must be called before `start()` whenever
    /// the active profile or mode changes.
    pub fn write_config(&self, profile_content: &str) -> anyhow::Result<()> {
        let mode = self.current_mode();
        let tun_options = self.current_tun_options();
        let merged = self.generate_config(profile_content, mode, &tun_options)?;
        let config_path = crate::utils::dirs::get_config_path(&self.app_handle)?;
        if let Some(parent) = config_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(&config_path, merged)?;
        log::info!(
            "Wrote merged mihomo config to {:?} (mode: {:?})",
            config_path,
            mode
        );
        Ok(())
    }
}

/// Merge UI-managed TUN options into the profile's existing tun block.
/// Profile-provided fields win — the UI's options only fill gaps. The single
/// exception is `enable`, which we always force to `true` here since the
/// caller asked for TUN mode.
fn merge_tun(
    mut existing: crate::config::parser::ClashRawTUN,
    opts: &TunOptions,
) -> crate::config::parser::ClashRawTUN {
    existing.enable = Some(true);
    if existing.device.is_none() {
        existing.device = Some(opts.device.clone());
    }
    if existing.stack.is_none() {
        existing.stack = Some(opts.stack.clone());
    }
    if existing.auto_route.is_none() {
        existing.auto_route = Some(opts.auto_route);
    }
    if existing.auto_detect_interface.is_none() {
        existing.auto_detect_interface = Some(opts.auto_detect_interface);
    }
    if existing.strict_route.is_none() {
        existing.strict_route = Some(opts.strict_route);
    }
    if existing.mtu.is_none() {
        existing.mtu = Some(opts.mtu);
    }
    if existing.dns_hijack.is_none() && !opts.dns_hijack.is_empty() {
        existing.dns_hijack = Some(opts.dns_hijack.clone());
    }
    existing
}

/// Event surfaced when mihomo exits without being asked to.
#[derive(Clone, serde::Serialize)]
struct MihomoCrashEvent {
    /// Process exit code, if available.
    exit_code: Option<i32>,
    /// What mode mihomo was in. UI uses this to decide whether to offer
    /// "Restart in System Proxy" vs "Restart in TUN" etc.
    mode: TunnelMode,
}

/// Background watcher: polls the child every 500ms. On exit, distinguishes
/// expected vs unexpected and emits `mihomo_exited` (clean) or
/// `mihomo_crashed` (unclean) so the UI / Mode Coordinator can react.
async fn watch_for_exit(
    process_arc: Arc<Mutex<Option<Child>>>,
    expected_arc: Arc<StdMutex<bool>>,
    app: AppHandle,
    mode: TunnelMode,
) {
    loop {
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        let mut guard = process_arc.lock().await;
        let Some(child) = guard.as_mut() else {
            // stop() already took the child; nothing more to watch.
            return;
        };
        match child.try_wait() {
            Ok(Some(status)) => {
                let exit_code = status.code();
                *guard = None;
                drop(guard);

                let was_expected = *expected_arc.lock().unwrap();
                if was_expected {
                    log::info!("mihomo exited cleanly with code {:?}", exit_code);
                    let _ = app.emit(
                        "mihomo_exited",
                        MihomoCrashEvent {
                            exit_code,
                            mode,
                        },
                    );
                } else {
                    log::error!("mihomo crashed (exit code {:?})", exit_code);
                    let _ = app.emit(
                        "mihomo_crashed",
                        MihomoCrashEvent {
                            exit_code,
                            mode,
                        },
                    );

                    // If we were in TUN mode and the user opted into the kill
                    // switch, arm it now to stop traffic from silently leaking
                    // out of the (now-undefended) OS interfaces.
                    if mode == TunnelMode::Tun {
                        let state = crate::core::kill_switch::KillSwitchState::load();
                        if state.enabled && !state.armed {
                            if let Err(e) = crate::core::kill_switch::arm() {
                                log::error!("Kill switch arm failed: {}", e);
                            } else {
                                let _ = app.emit("kill_switch_armed", ());
                            }
                        }
                    }
                }
                return;
            }
            Ok(None) => continue,
            Err(e) => {
                log::warn!("mihomo watcher try_wait failed: {}", e);
                return;
            }
        }
    }
}

/// Check if mihomo binary exists
pub fn check_mihomo_binary(app_handle: &AppHandle) -> bool {
    crate::utils::dirs::get_mihomo_binary_path(app_handle)
        .map(|p| p.exists())
        .unwrap_or(false)
}
