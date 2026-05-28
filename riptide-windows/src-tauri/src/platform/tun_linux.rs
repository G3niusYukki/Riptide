//! Linux TUN interface via `/dev/net/tun` (stub — WIP).
//! Real implementation will use `tokio-tun` crate.

use anyhow::Result;

pub struct LinuxTun {
    name: String,
}

impl LinuxTun {
    pub async fn create(name: &str, _address: &str, _mtu: u16) -> Result<Self> {
        log::info!("LinuxTun::create({}) — stub", name);
        Ok(Self { name: name.to_string() })
    }

    pub async fn read(&mut self) -> Result<Vec<u8>> {
        todo!("LinuxTun::read")
    }

    pub async fn write(&mut self, _packet: &[u8]) -> Result<()> {
        todo!("LinuxTun::write")
    }

    pub fn name(&self) -> &str { &self.name }
    pub fn mtu(&self) -> i32 { 1420 }
}
