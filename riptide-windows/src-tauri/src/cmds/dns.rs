//! DNS policy commands — UI reads/writes the user-managed DNS overrides.

use crate::config::dns_policy::DnsPolicy;

#[tauri::command]
pub fn get_dns_policy() -> DnsPolicy {
    DnsPolicy::load()
}

#[tauri::command]
pub fn set_dns_policy(policy: DnsPolicy) -> Result<(), String> {
    policy.save()
}
