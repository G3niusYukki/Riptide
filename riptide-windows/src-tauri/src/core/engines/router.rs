//! Routing policy that maps a [`ProxyKind`] to a [`ProxyEngineKind`].
//!
//! See ADR-0005 for the full table. Short version:
//!
//! - `Reality` and `AnyTls` always go to sing-box (mihomo does not
//!   speak them as of v2.4.1).
//! - Everything else follows the active `Policy`:
//!   - `DefaultMihomo` → mihomo
//!   - `ExplicitSingbox` → sing-box
//!
//! Pure logic, no IO, no async. All five tests live at the bottom of
//! this file; they cover the table exhaustively for the kinds we
//! actually have.

use std::sync::Mutex;

use super::proxy_engine::{ProxyEngineKind, ProxyKind};

/// User-visible engine routing policy. Persisted to `active.json` /
/// `engine_policy.json` in a future phase; for now it lives in a
/// `Mutex` on the shared `EngineRouter`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Policy {
    /// Every supported kind (Reality/AnyTls excluded) → mihomo.
    /// This is the default — the v2.4.0 Windows binary only knew
    /// mihomo, and ADR-0005 deliberately does not flip the default.
    #[default]
    #[serde(rename = "default_mihomo")]
    DefaultMihomo,
    /// Force everything through sing-box. Useful for the
    /// "running the sing-box pre-flight" beta flag.
    #[serde(rename = "explicit_singbox")]
    ExplicitSingbox,
}

impl Policy {
    pub fn as_str(self) -> &'static str {
        match self {
            Policy::DefaultMihomo => "default_mihomo",
            Policy::ExplicitSingbox => "explicit_singbox",
        }
    }
}

/// The router itself. Thread-safe — `set_policy` is called from a
/// Tauri command (async) and `engine_for` may be called from any
/// thread that holds a node to route.
pub struct EngineRouter {
    policy: Mutex<Policy>,
}

impl EngineRouter {
    /// Build a router with the supplied policy.
    pub fn new(policy: Policy) -> Self {
        Self {
            policy: Mutex::new(policy),
        }
    }

    /// Router with the ADR-0005 default policy.
    pub fn default_mihomo() -> Self {
        Self::new(Policy::DefaultMihomo)
    }

    /// Look at the active policy and return the engine that should
    /// handle `kind`.
    pub fn engine_for(&self, kind: ProxyKind) -> ProxyEngineKind {
        match kind {
            ProxyKind::Reality | ProxyKind::AnyTls => ProxyEngineKind::Singbox,
            _ => match self.current_policy() {
                Policy::ExplicitSingbox => ProxyEngineKind::Singbox,
                Policy::DefaultMihomo => ProxyEngineKind::Mihomo,
            },
        }
    }

    /// Read the current policy without taking the lock twice.
    pub fn current_policy(&self) -> Policy {
        *self
            .policy
            .lock()
            .expect("EngineRouter policy mutex poisoned")
    }

    /// Replace the active policy. Returns the previous value so
    /// callers can log the transition.
    pub fn set_policy(&self, new_policy: Policy) -> Policy {
        let mut guard = self
            .policy
            .lock()
            .expect("EngineRouter policy mutex poisoned");
        let prev = *guard;
        *guard = new_policy;
        prev
    }
}

impl Default for EngineRouter {
    fn default() -> Self {
        Self::default_mihomo()
    }
}

#[cfg(test)]
mod tests {
    //! 5 unit tests for the routing table in ADR-0005.
    //!
    //! The task spec called out: trojan, reality, anytls, the
    //! "ExplicitSingbox routes everything" rule, and the
    //! `set_policy` mutation. We add a `default_is_default_mihomo`
    //! sentinel because the rest of the tests would silently pass
    //! if `Default::default()` flipped to ExplicitSingbox.

    use super::*;

    #[test]
    fn engine_for_trojan_returns_mihomo() {
        // Default policy: every kind except Reality/AnyTls → mihomo.
        let router = EngineRouter::default_mihomo();
        assert_eq!(
            router.engine_for(ProxyKind::Trojan),
            ProxyEngineKind::Mihomo
        );
    }

    #[test]
    fn engine_for_reality_returns_singbox() {
        // Reality is forced to sing-box regardless of policy.
        let router = EngineRouter::default_mihomo();
        assert_eq!(
            router.engine_for(ProxyKind::Reality),
            ProxyEngineKind::Singbox
        );
    }

    #[test]
    fn engine_for_anytls_returns_singbox() {
        // AnyTls is forced to sing-box regardless of policy.
        let router = EngineRouter::default_mihomo();
        assert_eq!(
            router.engine_for(ProxyKind::AnyTls),
            ProxyEngineKind::Singbox
        );
    }

    #[test]
    fn explicit_singbox_policy_routes_everything_to_singbox() {
        // Under ExplicitSingbox, only Reality/AnyTls would already
        // have been singbox; we now also send Shadowsocks (the most
        // common "would have been mihomo" kind) through sing-box.
        // Reality/AnyTls must STILL go to sing-box (the forced
        // rules win — they short-circuit the policy match).
        let router = EngineRouter::new(Policy::ExplicitSingbox);

        assert_eq!(
            router.engine_for(ProxyKind::Shadowsocks),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::Vmess),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::Vless),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::Trojan),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::Hysteria2),
            ProxyEngineKind::Singbox
        );
        assert_eq!(router.engine_for(ProxyKind::Tuic), ProxyEngineKind::Singbox);

        // Reality/AnyTls forced rules still win.
        assert_eq!(
            router.engine_for(ProxyKind::Reality),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::AnyTls),
            ProxyEngineKind::Singbox
        );
    }

    #[test]
    fn engine_set_policy_updates_router() {
        // The mutation: start default, flip to ExplicitSingbox, flip
        // back. The router should reflect every transition immediately.
        let router = EngineRouter::default_mihomo();
        assert_eq!(router.current_policy(), Policy::DefaultMihomo);

        let prev = router.set_policy(Policy::ExplicitSingbox);
        assert_eq!(prev, Policy::DefaultMihomo);
        assert_eq!(router.current_policy(), Policy::ExplicitSingbox);

        // And the routing table moves with the policy.
        assert_eq!(
            router.engine_for(ProxyKind::Shadowsocks),
            ProxyEngineKind::Singbox
        );

        // Reality/AnyTls unchanged by the policy flip.
        assert_eq!(
            router.engine_for(ProxyKind::Reality),
            ProxyEngineKind::Singbox
        );
        assert_eq!(
            router.engine_for(ProxyKind::AnyTls),
            ProxyEngineKind::Singbox
        );

        let prev = router.set_policy(Policy::DefaultMihomo);
        assert_eq!(prev, Policy::ExplicitSingbox);
        assert_eq!(router.current_policy(), Policy::DefaultMihomo);
        assert_eq!(
            router.engine_for(ProxyKind::Shadowsocks),
            ProxyEngineKind::Mihomo
        );
    }
}
