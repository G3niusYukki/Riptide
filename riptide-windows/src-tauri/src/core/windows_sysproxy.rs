//! Windows-specific system proxy configuration using WinHTTP API
//!
//! This module provides Windows-native system proxy control using the WinHTTP API,
//! offering an alternative to the sysproxy crate for advanced use cases.
//! Reference: Clash Verge Rev implementation approach

use std::ffi::CString;
use std::ptr;

/// Errors that can occur when managing Windows system proxy
#[derive(Debug, thiserror::Error)]
pub enum SysproxyError {
    #[error("WinAPI error: {0}")]
    WinApiError(String),
    
    #[error("Invalid proxy host: {0}")]
    InvalidHost(String),
    
    #[error("Invalid proxy configuration")]
    InvalidConfiguration,
    
    #[error("Failed to set system proxy: {0}")]
    SetProxyFailed(String),
    
    #[error("Failed to get system proxy: {0}")]
    GetProxyFailed(String),
}

/// Represents system proxy configuration
#[derive(Debug, Clone, PartialEq)]
pub struct WindowsProxyConfig {
    pub enable: bool,
    pub proxy_server: String,
    pub bypass_list: String,
    pub auto_config_url: Option<String>,
}

impl Default for WindowsProxyConfig {
    fn default() -> Self {
        Self {
            enable: false,
            proxy_server: String::new(),
            bypass_list: String::new(),
            auto_config_url: None,
        }
    }
}

impl WindowsProxyConfig {
    /// Create a new proxy configuration with HTTP proxy
    pub fn http_proxy(host: &str, port: u16) -> Self {
        Self {
            enable: true,
            proxy_server: format!("http={}:{};https={}:{}", host, port, host, port),
            bypass_list: "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>".to_string(),
            auto_config_url: None,
        }
    }

    /// Create a new proxy configuration with SOCKS5 proxy
    pub fn socks_proxy(host: &str, port: u16) -> Self {
        Self {
            enable: true,
            proxy_server: format!("socks={}:{}", host, port),
            bypass_list: "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>".to_string(),
            auto_config_url: None,
        }
    }

    /// Create a combined HTTP + SOCKS proxy configuration
    pub fn combined_proxy(http_host: &str, http_port: u16, socks_port: u16) -> Self {
        Self {
            enable: true,
            proxy_server: format!(
                "http={}:{};https={}:{};socks={}:{}",
                http_host, http_port, http_host, http_port, http_host, socks_port
            ),
            bypass_list: "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>".to_string(),
            auto_config_url: None,
        }
    }

    /// Create a disabled proxy configuration
    pub fn disabled() -> Self {
        Self::default()
    }
}

/// Windows system proxy controller using WinHTTP API
pub struct WindowsSysProxyController;

impl WindowsSysProxyController {
    /// Create a new Windows system proxy controller
    pub fn new() -> Self {
        Self
    }

    /// Enable system proxy with the given configuration
    pub fn enable(&self, config: &WindowsProxyConfig) -> Result<(), SysproxyError> {
        if !config.enable {
            return Err(SysproxyError::InvalidConfiguration);
        }
        set_system_proxy_internal(config)
    }

    /// Disable system proxy
    pub fn disable(&self) -> Result<(), SysproxyError> {
        let config = WindowsProxyConfig::disabled();
        set_system_proxy_internal(&config)
    }

    /// Get current system proxy configuration
    pub fn get_current(&self) -> Result<WindowsProxyConfig, SysproxyError> {
        get_system_proxy_internal()
    }

    /// Quick enable HTTP proxy
    pub fn enable_http_proxy(&self, host: &str, port: u16) -> Result<(), SysproxyError> {
        let config = WindowsProxyConfig::http_proxy(host, port);
        self.enable(&config)
    }

    /// Quick enable SOCKS proxy  
    pub fn enable_socks_proxy(&self, host: &str, port: u16) -> Result<(), SysproxyError> {
        let config = WindowsProxyConfig::socks_proxy(host, port);
        self.enable(&config)
    }

    /// Quick enable both HTTP and SOCKS proxy
    pub fn enable_both_proxies(&self, host: &str, http_port: u16, socks_port: u16) -> Result<(), SysproxyError> {
        let config = WindowsProxyConfig::combined_proxy(host, http_port, socks_port);
        self.enable(&config)
    }
}

impl Default for WindowsSysProxyController {
    fn default() -> Self {
        Self::new()
    }
}

/// Internal function to set system proxy using Windows API
fn set_system_proxy_internal(config: &WindowsProxyConfig) -> Result<(), SysproxyError> {
    #[cfg(target_os = "windows")]
    {
        use winapi::um::wininet::{InternetSetOptionA, INTERNET_OPTION_PROXY, INTERNET_OPTION_PROXY_SETTINGS_CHANGED, INTERNET_OPTION_REFRESH};
        use winapi::shared::minwindef::{DWORD, LPVOID, BOOL, TRUE};
        use winapi::um::wininet::INTERNET_PROXY_INFO;
        use std::mem;

        unsafe {
            // Build proxy server string — keep alive on stack through InternetSetOptionA
            let proxy_server = CString::new(config.proxy_server.clone())
                .map_err(|_| SysproxyError::InvalidHost("Invalid proxy server string".to_string()))?;

            // Build bypass list string — keep alive on stack through InternetSetOptionA
            let bypass_cstring = if config.bypass_list.is_empty() {
                None
            } else {
                Some(CString::new(config.bypass_list.clone())
                    .map_err(|_| SysproxyError::InvalidHost("Invalid bypass list string".to_string()))?)
            };

            // Configure proxy info structure
            let mut proxy_info: INTERNET_PROXY_INFO = mem::zeroed();

            if config.enable {
                proxy_info.dwAccessType = 3; // INTERNET_OPEN_TYPE_PROXY
                proxy_info.lpszProxy = proxy_server.as_ptr() as *mut i8;
                if let Some(ref bypass) = bypass_cstring {
                    proxy_info.lpszProxyBypass = bypass.as_ptr() as *mut i8;
                }
            } else {
                proxy_info.dwAccessType = 1; // INTERNET_OPEN_TYPE_DIRECT
                proxy_info.lpszProxy = ptr::null_mut();
                proxy_info.lpszProxyBypass = ptr::null_mut();
            }

            // Set the proxy configuration
            let result = InternetSetOptionA(
                ptr::null_mut(),
                INTERNET_OPTION_PROXY,
                &proxy_info as *const _ as LPVOID,
                mem::size_of::<INTERNET_PROXY_INFO>() as DWORD,
            );

            if result != TRUE {
                return Err(SysproxyError::SetProxyFailed(
                    format!("InternetSetOptionA failed with result: {}", result)
                ));
            }

            // Notify system of proxy settings change
            InternetSetOptionA(
                ptr::null_mut(),
                INTERNET_OPTION_PROXY_SETTINGS_CHANGED,
                ptr::null_mut(),
                0,
            );

            // Refresh proxy settings
            InternetSetOptionA(
                ptr::null_mut(),
                INTERNET_OPTION_REFRESH,
                ptr::null_mut(),
                0,
            );
        }

        log::info!("Windows system proxy set: enabled={}", config.enable);
        if config.enable {
            log::info!("  Server: {}", config.proxy_server);
            log::info!("  Bypass: {}", config.bypass_list);
        }

        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    {
        // On non-Windows platforms, just log that this is a no-op
        log::debug!("Windows system proxy settings are only available on Windows");
        Ok(())
    }
}

/// Internal function to get current system proxy configuration
fn get_system_proxy_internal() -> Result<WindowsProxyConfig, SysproxyError> {
    #[cfg(target_os = "windows")]
    {
        use winapi::um::wininet::{InternetQueryOptionA, INTERNET_OPTION_PROXY};
        use winapi::shared::minwindef::{DWORD, LPVOID};
        use winapi::um::wininet::INTERNET_PROXY_INFO;
        use std::mem;
        use std::ffi::CStr;

        unsafe {
            let mut proxy_info: INTERNET_PROXY_INFO = mem::zeroed();
            let mut buffer_size: DWORD = mem::size_of::<INTERNET_PROXY_INFO>() as DWORD;

            let result = InternetQueryOptionA(
                ptr::null_mut(),
                INTERNET_OPTION_PROXY,
                &mut proxy_info as *mut _ as LPVOID,
                &mut buffer_size,
            );

            if result == 0 {
                return Err(SysproxyError::GetProxyFailed(
                    "InternetQueryOptionA failed".to_string()
                ));
            }

            let enable = proxy_info.dwAccessType == 3; // INTERNET_OPEN_TYPE_PROXY
            
            let proxy_server = if !proxy_info.lpszProxy.is_null() {
                CStr::from_ptr(proxy_info.lpszProxy)
                    .to_string_lossy()
                    .to_string()
            } else {
                String::new()
            };

            let bypass_list = if !proxy_info.lpszProxyBypass.is_null() {
                CStr::from_ptr(proxy_info.lpszProxyBypass)
                    .to_string_lossy()
                    .to_string()
            } else {
                String::new()
            };

            Ok(WindowsProxyConfig {
                enable,
                proxy_server,
                bypass_list,
                auto_config_url: None,
            })
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        // Return disabled config on non-Windows
        Ok(WindowsProxyConfig::disabled())
    }
}

/// High-level convenience function to set system proxy
pub fn set_system_proxy(enable: bool, host: &str, port: u16) -> Result<(), SysproxyError> {
    let controller = WindowsSysProxyController::new();
    
    if enable {
        let config = WindowsProxyConfig::http_proxy(host, port);
        controller.enable(&config)
    } else {
        controller.disable()
    }
}

/// High-level convenience function to clear system proxy
pub fn clear_system_proxy() -> Result<(), SysproxyError> {
    let controller = WindowsSysProxyController::new();
    controller.disable()
}

/// Check if system proxy is enabled
pub fn is_system_proxy_enabled() -> Result<bool, SysproxyError> {
    let controller = WindowsSysProxyController::new();
    let config = controller.get_current()?;
    Ok(config.enable)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proxy_config_creation() {
        let http_config = WindowsProxyConfig::http_proxy("127.0.0.1", 7890);
        assert!(http_config.enable);
        assert!(http_config.proxy_server.contains("7890"));
        assert!(http_config.proxy_server.contains("http="));
        
        let socks_config = WindowsProxyConfig::socks_proxy("127.0.0.1", 7891);
        assert!(socks_config.enable);
        assert!(socks_config.proxy_server.contains("socks="));
        
        let combined = WindowsProxyConfig::combined_proxy("127.0.0.1", 7890, 7891);
        assert!(combined.enable);
        assert!(combined.proxy_server.contains("http="));
        assert!(combined.proxy_server.contains("socks="));
    }

    #[test]
    fn test_disabled_config() {
        let config = WindowsProxyConfig::disabled();
        assert!(!config.enable);
        assert!(config.proxy_server.is_empty());
    }

    #[test]
    fn test_controller_default() {
        let controller = WindowsSysProxyController::default();
        let _ = controller.get_current(); // May fail on non-Windows, but shouldn't panic
    }

    #[test]
    fn test_sysproxy_error_display() {
        let err = SysproxyError::InvalidHost("test".to_string());
        assert!(err.to_string().contains("Invalid proxy host"));
        
        let err = SysproxyError::InvalidConfiguration;
        assert_eq!(err.to_string(), "Invalid proxy configuration");
    }
}
