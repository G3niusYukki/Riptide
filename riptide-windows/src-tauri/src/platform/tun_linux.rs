//! Linux TUN interface via `/dev/net/tun`.
//!
//! WireGuard and other Layer 3 tunnels on Linux use a TUN device
//! created through the kernel's universal TUN/TAP driver.
//!
//! # Usage
//! ```ignore
//! let tun = LinuxTun::create("riptide0", "10.0.0.1/24", 1420)?;
//! let packet = tun.read().await?;
//! tun.write(&response).await?;
//! ```

use anyhow::{Context, Result};
use std::net::Ipv4Addr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// A Linux TUN device backed by `/dev/net/tun`.
pub struct LinuxTun {
    device: tokio_tun::Tun,
    name: String,
}

impl LinuxTun {
    /// Create a new TUN device with the given name, address/CIDR, and MTU.
    pub async fn create(name: &str, address: &str, mtu: u16) -> Result<Self> {
        let addr_parts: Vec<&str> = address.split('/').collect();
        let ip: Ipv4Addr = addr_parts[0].parse().context("invalid TUN address")?;
        let prefix_len: u8 = addr_parts.get(1).unwrap_or(&"24").parse().context("invalid CIDR")?;

        let config = tokio_tun::TunBuilder::new()
            .name(name)
            .mtu(mtu as i32)
            .address(ip)
            .netmask(netmask_from_prefix(prefix_len))
            .up()
            .try_build()
            .context("failed to create TUN device")?;

        Ok(Self { device: config, name: name.to_string() })
    }

    /// Read a single IP packet from the TUN device.
    pub async fn read(&mut self) -> Result<Vec<u8>> {
        let mut buf = vec![0u8; 65535];
        let n = self.device.read(&mut buf).await.context("TUN read failed")?;
        buf.truncate(n);
        Ok(buf)
    }

    /// Write an IP packet to the TUN device.
    pub async fn write(&mut self, packet: &[u8]) -> Result<()> {
        self.device.write_all(packet).await.context("TUN write failed")?;
        Ok(())
    }

    pub fn name(&self) -> &str { &self.name }
    pub fn mtu(&self) -> i32 { self.device.mtu().unwrap_or(1420) }
}

impl Drop for LinuxTun {
    fn drop(&mut self) {
        log::info!("TUN device {} closed", self.name);
    }
}

fn netmask_from_prefix(prefix: u8) -> Ipv4Addr {
    if prefix == 0 { return Ipv4Addr::new(0, 0, 0, 0); }
    let mask: u32 = !0u32 << (32 - prefix);
    Ipv4Addr::from(mask.to_be_bytes())
}
