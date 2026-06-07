//! `ProxyEngine` trait + supporting types.
//!
//! See [`crate::core::engines`] for the module overview and ADR-0005
//! for the design rationale.

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use thiserror::Error;

/// Which proxy engine to use for a given node kind. The router
/// returns one of these; the caller then looks up an impl of
/// [`ProxyEngine`] for that kind.
///
/// `Swift` is the pure-Swift in-process engine that exists on macOS.
/// It is not implemented on Windows (see ADR-0007) but is kept in the
/// enum so cross-platform parity tools and docs can refer to it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProxyEngineKind {
    /// mihomo sidecar (the default on Windows; the same one macOS
    /// uses as a sidecar). Speaks Clash YAML.
    Mihomo,
    /// sing-box sidecar. Used for Reality, AnyTLS, and any future
    /// protocol mihomo does not support.
    Singbox,
    /// Pure-Swift in-process engine (macOS only).
    Swift,
}

impl ProxyEngineKind {
    /// Stable wire string used in the engine_get_policy / engine_set_policy
    /// Tauri commands. The frontend matches on these.
    pub fn as_str(self) -> &'static str {
        match self {
            ProxyEngineKind::Mihomo => "mihomo",
            ProxyEngineKind::Singbox => "singbox",
            ProxyEngineKind::Swift => "swift",
        }
    }
}

/// Proxy protocol kind. Used by the router to decide which engine
/// gets a given node.
///
/// Coverage mirrors the macOS `ProxyKind` plus the 5 Clash-native
/// kinds that mihomo speaks. `Reality` and `AnyTls` are not yet
/// emitted by the Windows share-URI parser (see
/// `config::uri_serializer`) but are part of the public enum so the
/// router policy in [`crate::core::engines::router`] can declare
/// "reality/anytls always go to sing-box" up front.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProxyKind {
    /// Shadowsocks
    Shadowsocks,
    /// VMess
    Vmess,
    /// VLESS (non-Reality; Reality has its own variant).
    Vless,
    /// Trojan
    Trojan,
    /// Hysteria2
    Hysteria2,
    /// Snell
    Snell,
    /// TUIC
    Tuic,
    /// SOCKS5
    Socks5,
    /// HTTP CONNECT
    Http,
    /// VLESS + Reality (XTLS). Forced to sing-box.
    Reality,
    /// AnyTLS. Forced to sing-box.
    AnyTls,
}

impl ProxyKind {
    /// Stable wire string. Matches the `type:` field in Clash YAML
    /// for the kinds that have one. `Reality` / `AnyTls` are sub-flavors
    /// of vless / a hypothetical anytls kind respectively and use
    /// descriptive names.
    pub fn as_str(self) -> &'static str {
        match self {
            ProxyKind::Shadowsocks => "ss",
            ProxyKind::Vmess => "vmess",
            ProxyKind::Vless => "vless",
            ProxyKind::Trojan => "trojan",
            ProxyKind::Hysteria2 => "hysteria2",
            ProxyKind::Snell => "snell",
            ProxyKind::Tuic => "tuic",
            ProxyKind::Socks5 => "socks5",
            ProxyKind::Http => "http",
            ProxyKind::Reality => "reality",
            ProxyKind::AnyTls => "anytls",
        }
    }

    /// Parse from a Clash `type:` field. Returns `None` for unknown
    /// kinds (caller should fall back to mihomo, per ADR-0005).
    pub fn from_clash_type(s: &str) -> Option<Self> {
        match s {
            "ss" | "shadowsocks" => Some(ProxyKind::Shadowsocks),
            "vmess" => Some(ProxyKind::Vmess),
            "vless" => Some(ProxyKind::Vless),
            "trojan" => Some(ProxyKind::Trojan),
            "hysteria2" | "hy2" => Some(ProxyKind::Hysteria2),
            "snell" => Some(ProxyKind::Snell),
            "tuic" => Some(ProxyKind::Tuic),
            "socks5" => Some(ProxyKind::Socks5),
            "http" => Some(ProxyKind::Http),
            "reality" => Some(ProxyKind::Reality),
            "anytls" => Some(ProxyKind::AnyTls),
            _ => None,
        }
    }
}

/// Minimal proxy node representation passed to an engine's
/// `generate_config`. Intentionally engine-agnostic: the engine
/// translates to its own dialect (Clash YAML for mihomo, sing-box
/// JSON for singbox).
///
/// The fields below cover everything mihomo and sing-box both
/// understand. Protocol-specific options (flow, fingerprint, pbk,
/// sid, …) are kept in `extra` as a flat `serde_json::Value` blob
/// so the engine can pull out what it needs without us re-modeling
/// every protocol here.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyNode {
    /// User-visible name. Required.
    pub name: String,
    /// Protocol kind. Required.
    pub kind: ProxyKind,
    /// Server address (hostname or IP). Required.
    pub server: String,
    /// Server port. Required.
    pub port: u16,
    /// Optional credentials / identifier. The exact meaning depends
    /// on `kind` (e.g. SS cipher/method, VMess UUID, Trojan password).
    pub secret: Option<String>,
    /// Optional secondary secret (e.g. SS password when `secret` is
    /// the method). Sing-box and mihomo both have a notion of
    /// "method + password" so we keep them split.
    pub secret2: Option<String>,
    /// Free-form bag for protocol-specific knobs (flow, fingerprint,
    /// pbk, sid, sni, alpn, ws-path, …). Engines pull what they
    /// need; unknown keys are ignored.
    #[serde(default)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// Engine-emitted configuration. Today mihomo produces Clash YAML
/// (a `String`); sing-box produces JSON (also a `String`). We keep
/// the on-disk form opaque and just hand it to the engine's process
/// launcher. `format` lets the launcher pick the right parser if it
/// needs to (e.g. to extract listen ports).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Wire format. `clash_yaml` for mihomo, `singbox_json` for
    /// sing-box.
    pub format: String,
    /// The serialized config body (UTF-8).
    pub body: String,
}

impl Config {
    /// Construct a Clash YAML config.
    pub fn clash_yaml(body: impl Into<String>) -> Self {
        Self {
            format: "clash_yaml".into(),
            body: body.into(),
        }
    }
    /// Construct a sing-box JSON config.
    pub fn singbox_json(body: impl Into<String>) -> Self {
        Self {
            format: "singbox_json".into(),
            body: body.into(),
        }
    }
}

/// Errors raised by an engine's [`ProxyEngine::generate_config`].
/// Each variant is intentionally coarse — engines surface their own
/// detailed errors via `source()`.
#[derive(Debug, Error)]
pub enum EngineError {
    /// The user gave us a node whose `kind` this engine does not
    /// support.
    #[error("engine {engine} does not support proxy kind {kind:?}")]
    UnsupportedKind {
        engine: &'static str,
        kind: ProxyKind,
    },
    /// Serialization / deserialization failure inside the engine.
    #[error("engine {engine} config serialization failed: {message}")]
    Serialization {
        engine: &'static str,
        message: String,
        #[source]
        source: Option<Box<dyn std::error::Error + Send + Sync>>,
    },
    /// Anything else. The router / caller should map this to a
    /// user-visible string.
    #[error("engine {engine} failed: {source}")]
    Other {
        engine: &'static str,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
}

impl EngineError {
    pub fn unsupported(engine: &'static str, kind: ProxyKind) -> Self {
        EngineError::UnsupportedKind { engine, kind }
    }
    pub fn serialization(engine: &'static str, message: impl Into<String>) -> Self {
        EngineError::Serialization {
            engine,
            message: message.into(),
            source: None,
        }
    }
    pub fn other<E>(engine: &'static str, e: E) -> Self
    where
        E: std::error::Error + Send + Sync + 'static,
    {
        EngineError::Other {
            engine,
            source: Box::new(e),
        }
    }
}

/// A proxy engine. Implementations are stateless and `Send + Sync`
/// so the router can hand them out across threads.
pub trait ProxyEngine: Send + Sync {
    /// Stable display name. Matches the corresponding binary on disk
    /// (e.g. `"mihomo"`) — used in logs and the Tauri command output.
    fn name(&self) -> &'static str;

    /// Which engine this is. Used by the router to confirm the
    /// policy decision round-tripped.
    fn kind(&self) -> ProxyEngineKind;

    /// Set of [`ProxyKind`]s this engine can handle. The router uses
    /// this to warn if a profile contains a kind the routed engine
    /// does not support.
    fn supported_proxy_kinds(&self) -> HashSet<ProxyKind>;

    /// Build an engine-specific config from the supplied nodes.
    /// Implementations should reject unsupported kinds with
    /// [`EngineError::UnsupportedKind`].
    fn generate_config(&self, nodes: &[ProxyNode]) -> Result<Config, EngineError>;
}
