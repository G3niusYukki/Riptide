//! Gateway / Internet Connection Sharing (ICS) for Windows.
//!
//! Uses the Windows `netsh` command-line tool to configure ICS (Internet
//! Connection Sharing), which provides NAT + DHCP for LAN devices.
//! All operations require administrator privileges.

use std::process::Command;

/// Enable Internet Connection Sharing on a specified network interface.
/// `outbound_interface` is the interface with internet access (e.g. "Ethernet"),
/// `subnet` is the subnet for ICS clients (e.g. "192.168.137.0/24").
pub fn enable_ics(outbound_interface: &str, _subnet: &str) -> Result<(), String> {
    // Windows ICS is configured via the registry + netsh.
    // The simplest approach: use netsh to set the sharing interface.

    let output = Command::new("netsh")
        .args([
            "routing", "ip", "nat", "install",
        ])
        .output()
        .map_err(|e| format!("Failed to install NAT: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "netsh NAT install failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    // Add the public interface (outbound)
    let output = Command::new("netsh")
        .args([
            "routing", "ip", "nat",
            "add", "interface",
            outbound_interface,
        ])
        .output()
        .map_err(|e| format!("Failed to add NAT interface: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "netsh add interface failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    // Enable Windows Firewall rule for ICS
    let _ = Command::new("netsh")
        .args(["firewall", "set", "service", "type=ICS", "mode=ENABLE"])
        .output();

    Ok(())
}

/// Disable Internet Connection Sharing.
pub fn disable_ics() -> Result<(), String> {
    let output = Command::new("netsh")
        .args(["routing", "ip", "nat", "delete"])
        .output()
        .map_err(|e| format!("Failed to delete NAT config: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "netsh NAT delete failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    Ok(())
}

/// Check if ICS / NAT routing is currently enabled.
pub fn is_ics_enabled() -> bool {
    let output = Command::new("netsh")
        .args(["routing", "ip", "nat", "show", "interface"])
        .output()
        .ok();

    match output {
        Some(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            stdout.contains("Enabled") || stdout.contains("connected")
        }
        None => false,
    }
}

/// Get a list of connected devices from the ARP cache.
pub fn connected_devices() -> Vec<ConnectedDevice> {
    let output = match Command::new("arp").arg("-a").output() {
        Ok(o) => o,
        Err(_) => return vec![],
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut devices = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 3 {
            let ip = parts[0].to_string();
            let mac = parts[1].to_string();
            let iface = if parts.len() >= 4 { parts[3].to_string() } else { String::new() };

            // Filter: only include dynamic entries (not multicast/broadcast)
            if mac != "ff-ff-ff-ff-ff-ff" && mac != "00-00-00-00-00-00" && mac.contains('-') {
                devices.push(ConnectedDevice {
                    ip,
                    mac,
                    interface: iface,
                });
            }
        }
    }

    devices
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConnectedDevice {
    pub ip: String,
    pub mac: String,
    pub interface: String,
}
