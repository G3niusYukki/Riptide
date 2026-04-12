//! System proxy control using sysproxy crate

use sysproxy::Sysproxy;
use std::sync::Mutex;

pub struct SystemProxyController {
    http_proxy: Mutex<Option<Sysproxy>>,
    socks_proxy: Mutex<Option<Sysproxy>>,
}

impl SystemProxyController {
    pub fn new() -> Self {
        Self {
            http_proxy: Mutex::new(None),
            socks_proxy: Mutex::new(None),
        }
    }

    /// Enable system proxy
    pub async fn enable(&self, http_port: u16, socks_port: Option<u16>) -> anyhow::Result<()> {
        // Enable HTTP proxy
        let http = Sysproxy {
            enable: true,
            host: "127.0.0.1".to_string(),
            port: http_port,
            bypass: "".to_string(),
        };
        http.set_system_proxy()?;
        *self.http_proxy.lock().unwrap() = Some(http);

        // Enable SOCKS proxy if specified
        if let Some(port) = socks_port {
            let socks = Sysproxy {
                enable: true,
                host: "127.0.0.1".to_string(),
                port,
                bypass: "".to_string(),
            };
            socks.set_system_proxy()?;
            *self.socks_proxy.lock().unwrap() = Some(socks);
        }

        log::info!("System proxy enabled: HTTP={}, SOCKS={:?}", http_port, socks_port);
        Ok(())
    }

    /// Disable system proxy
    pub async fn disable(&self) -> anyhow::Result<()> {
        // Disable HTTP proxy
        if let Some(ref proxy) = *self.http_proxy.lock().unwrap() {
            let disabled = Sysproxy {
                enable: false,
                host: proxy.host.clone(),
                port: proxy.port,
                bypass: proxy.bypass.clone(),
            };
            disabled.set_system_proxy()?;
        }
        *self.http_proxy.lock().unwrap() = None;

        // Disable SOCKS proxy
        if let Some(ref proxy) = *self.socks_proxy.lock().unwrap() {
            let disabled = Sysproxy {
                enable: false,
                host: proxy.host.clone(),
                port: proxy.port,
                bypass: proxy.bypass.clone(),
            };
            disabled.set_system_proxy()?;
        }
        *self.socks_proxy.lock().unwrap() = None;

        log::info!("System proxy disabled");
        Ok(())
    }

    /// Check if system proxy is enabled
    pub async fn is_enabled(&self) -> bool {
        self.http_proxy.lock().unwrap().is_some()
    }

    /// Get current proxy settings
    pub fn get_current_proxy() -> anyhow::Result<Sysproxy> {
        Sysproxy::get_system_proxy()
            .map_err(|e| anyhow::anyhow!("Failed to get system proxy: {:?}", e))
    }
}
