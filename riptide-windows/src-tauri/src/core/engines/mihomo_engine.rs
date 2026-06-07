//! mihomo engine impl — wraps the existing `core::mihomo` lifecycle
//! and config generation behind the [`ProxyEngine`] trait.
//!
//! On Windows today, mihomo is the workhorse. It speaks Clash YAML
//! and handles every protocol the existing share-URI parser emits
//! (ss/vmess/vless/trojan/hysteria2/tuic), so it advertises those
//! six kinds. Reality and AnyTls are not yet in
//! [`super::proxy_engine::ProxyKind::from_clash_type`]'s mihomo path;
//! the router sends them to sing-box (ADR-0005), so listing them as
//! "not supported" here is correct.

use std::collections::HashSet;

use super::proxy_engine::{
    Config, EngineError, ProxyEngine, ProxyEngineKind, ProxyKind, ProxyNode,
};

/// The mihomo engine. Zero-sized — there is no per-instance state;
/// process lifecycle is owned by `core::mihomo::MihomoManager` and
/// the router just hands a handle to callers.
#[derive(Debug, Default, Clone, Copy)]
pub struct MihomoEngine;

impl MihomoEngine {
    pub const fn new() -> Self {
        Self
    }
}

impl ProxyEngine for MihomoEngine {
    fn name(&self) -> &'static str {
        "mihomo"
    }

    fn kind(&self) -> ProxyEngineKind {
        ProxyEngineKind::Mihomo
    }

    fn supported_proxy_kinds(&self) -> HashSet<ProxyKind> {
        // The six kinds the share-URI serializer knows how to emit,
        // plus the two orthogonal transports that mihomo also speaks
        // natively even though the Windows UI does not round-trip
        // them through share URIs.
        let mut set = HashSet::with_capacity(8);
        set.insert(ProxyKind::Shadowsocks);
        set.insert(ProxyKind::Vmess);
        set.insert(ProxyKind::Vless);
        set.insert(ProxyKind::Trojan);
        set.insert(ProxyKind::Hysteria2);
        set.insert(ProxyKind::Tuic);
        set.insert(ProxyKind::Socks5);
        set.insert(ProxyKind::Http);
        set
    }

    fn generate_config(&self, nodes: &[ProxyNode]) -> Result<Config, EngineError> {
        // Reject up front: mihomo cannot speak Reality or AnyTls.
        for node in nodes {
            if matches!(node.kind, ProxyKind::Reality | ProxyKind::AnyTls) {
                return Err(EngineError::unsupported(self.name(), node.kind));
            }
        }

        // Translate our engine-agnostic `ProxyNode` to a
        // `ClashRawProxy` and serialize to YAML. The translation is
        // a small switch — only the most common fields are mapped;
        // anything in `node.extra` is merged through so protocol
        // knobs (flow / fp / pbk / sid / …) survive.
        let mut doc = serde_yaml::Mapping::new();
        let proxies_yaml: Vec<serde_yaml::Value> =
            nodes.iter().map(proxy_node_to_clash_yaml).collect();
        doc.insert(
            serde_yaml::Value::String("proxies".into()),
            serde_yaml::Value::Sequence(proxies_yaml),
        );

        let body = serde_yaml::to_string(&doc)
            .map_err(|e| EngineError::serialization(self.name(), e.to_string()))?;
        Ok(Config::clash_yaml(body))
    }
}

/// Render a [`ProxyNode`] as a Clash YAML mapping. Unknown / protocol
/// specific keys from `node.extra` are merged in verbatim.
fn proxy_node_to_clash_yaml(node: &ProxyNode) -> serde_yaml::Value {
    use serde_yaml::{Mapping, Value};

    let mut m = Mapping::new();
    m.insert(
        Value::String("name".into()),
        Value::String(node.name.clone()),
    );
    m.insert(
        Value::String("type".into()),
        Value::String(node.kind.as_str().into()),
    );
    m.insert(
        Value::String("server".into()),
        Value::String(node.server.clone()),
    );
    m.insert(
        Value::String("port".into()),
        Value::Number(node.port.into()),
    );

    if let Some(s) = &node.secret {
        // mihomo uses different field names per protocol (cipher vs
        // uuid vs password). The router is protocol-agnostic, so we
        // emit `secret` and let the existing mihomo config merging
        // step in `core::mihomo::MihomoManager::generate_config` map
        // it onto the right field per kind. Today the only caller is
        // a future "import via engine" path; for the immediate
        // C5.1/C5.3 surface this stub is enough.
        m.insert(Value::String("password".into()), Value::String(s.clone()));
    }
    if let Some(s) = &node.secret2 {
        m.insert(Value::String("cipher".into()), Value::String(s.clone()));
    }
    for (k, v) in &node.extra {
        let yaml_val = serde_yaml::to_value(v).unwrap_or(Value::Null);
        m.insert(Value::String(k.clone()), yaml_val);
    }
    Value::Mapping(m)
}
