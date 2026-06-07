//! On-disk shape for a single [`Scene`].
//!
//! The wire format mirrors what the React frontend (`types/scene.ts`)
//! speaks — snake_case keys, flat enums serialized as snake_case
//! strings. All fields are required except those explicitly marked
//! `#[serde(default)]` (notably `id`, which the backend mints on
//! `scene_create` if the client does not provide one).

use serde::{Deserialize, Serialize};

/// Stable identifier — UUID v4, generated on the Rust side when the
/// client posts a `scene_create` without an `id`. Serialized as a
/// string so the JS layer can read it as a plain `string`.
pub type SceneId = String;

/// Which proxy mode a connection should use when a scene's matchers
/// fire. Mirrors `AppMode` in `services/tauri.ts` but lives in the
/// scene editor namespace; renaming one implies renaming the other.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModeOverride {
    /// `off` — kill proxy for matched traffic.
    Off,
    /// `system_proxy` — route via the system proxy entrypoint.
    SystemProxy,
    /// `tun` — route via the TUN interface.
    Tun,
    /// `direct` — bypass all proxies (see-through).
    Direct,
}

impl ModeOverride {
    /// Stable wire string used for comparisons on the JS side.
    pub fn as_str(self) -> &'static str {
        match self {
            ModeOverride::Off => "off",
            ModeOverride::SystemProxy => "system_proxy",
            ModeOverride::Tun => "tun",
            ModeOverride::Direct => "direct",
        }
    }

    /// Parse the JS-side snake_case wire string. Returns `None` for
    /// unknown values so callers can fall back to a default.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "off" => Some(ModeOverride::Off),
            "system_proxy" => Some(ModeOverride::SystemProxy),
            "tun" => Some(ModeOverride::Tun),
            "direct" => Some(ModeOverride::Direct),
            _ => None,
        }
    }
}

/// One match clause. A scene holds a list of these; **any** match
/// firing (logical OR) is enough to apply the scene's mode override.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Matcher {
    /// Match a process name (exact) or basename pattern. The pattern
    /// is matched case-insensitively on Windows; the matcher itself
    /// does not do glob expansion in this MVP — we only accept
    /// `*` as a "match anything" sentinel.
    #[serde(rename = "process")]
    Process {
        /// Pattern; `*` matches any process.
        pattern: String,
    },
    /// Match a domain or domain suffix. Subdomains of `example.com`
    /// match `example.com` (suffix match, not equality).
    #[serde(rename = "domain")]
    Domain {
        /// Domain or suffix (e.g. `example.com`, `*.internal`).
        pattern: String,
    },
    /// Match an IP / CIDR. The wire `value` may be a single IPv4
    /// ("10.0.0.1"), a CIDR ("10.0.0.0/24"), or an IPv6 CIDR.
    #[serde(rename = "ipset")]
    IpSet {
        /// IP or CIDR.
        value: String,
    },
}

impl Matcher {
    /// Cheap stringification used by the frontend for badges.
    pub fn kind_str(&self) -> &'static str {
        match self {
            Matcher::Process { .. } => "process",
            Matcher::Domain { .. } => "domain",
            Matcher::IpSet { .. } => "ipset",
        }
    }
}

/// A single scene: a name, a list of matchers, and the mode to
/// switch to when any matcher fires.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Scene {
    /// Stable identifier. The frontend may omit this on
    /// `scene_create`; the backend mints a UUID v4.
    #[serde(default)]
    pub id: SceneId,
    /// Human-readable label, surfaced in the list view.
    pub name: String,
    /// What the scene does when one of its matchers fires.
    pub mode: ModeOverride,
    /// When `false`, the scene is preserved on disk but is skipped
    /// by `scene_apply`. UI shows it greyed out.
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    /// Match clauses (logical OR).
    pub matchers: Vec<Matcher>,
    /// ISO 8601 timestamp the scene was created (RFC 3339 / UTC).
    /// Surfaced for the list-view "created" column.
    #[serde(default)]
    pub created_at: String,
    /// ISO 8601 timestamp of the most recent update.
    #[serde(default)]
    pub updated_at: String,
}

fn default_enabled() -> bool {
    true
}

/// A trimmed view of a [`Scene`] returned by the "list" command and
/// `scene_apply`. Full matchers / timestamps are not surfaced — the
/// frontend only needs a name, id, and a few summary fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SceneSummary {
    pub id: SceneId,
    pub name: String,
    pub mode: ModeOverride,
    pub enabled: bool,
    /// Number of matchers the scene holds. The list view renders
    /// this as "3 rules" without enumerating them.
    pub matcher_count: usize,
    /// Free-form extra fields (the comma-separated matcher kind
    /// string: "process + domain + ipset"). Used by the editor list
    /// to show "Process + Domain" at a glance.
    pub matcher_kinds: String,
}

impl SceneSummary {
    /// Build a summary from a full scene. `matcher_kinds` is the
    /// unique-sorted list of matcher kinds, joined by `" + "`.
    pub fn from_scene(scene: &Scene) -> Self {
        let mut kinds: Vec<&'static str> = scene.matchers.iter().map(|m| m.kind_str()).collect();
        kinds.sort_unstable();
        kinds.dedup();
        Self {
            id: scene.id.clone(),
            name: scene.name.clone(),
            mode: scene.mode,
            enabled: scene.enabled,
            matcher_count: scene.matchers.len(),
            matcher_kinds: kinds.join(" + "),
        }
    }
}

#[cfg(test)]
mod tests {
    //! Smoke tests for the wire types. The CRUD + match logic lives
    //! in `store` and `matcher`; this module only asserts the JSON
    //! shape that the JS side reads.

    use super::*;

    #[test]
    fn mode_override_round_trip() {
        for m in [
            ModeOverride::Off,
            ModeOverride::SystemProxy,
            ModeOverride::Tun,
            ModeOverride::Direct,
        ] {
            let s = serde_json::to_string(&m).unwrap();
            let back: ModeOverride = serde_json::from_str(&s).unwrap();
            assert_eq!(back, m);
            // JS reads the snake_case wire string directly; assert it.
            assert_eq!(m.as_str(), s.trim_matches('"'));
        }
    }

    #[test]
    fn matcher_serializes_with_kind_tag() {
        let m = Matcher::Process {
            pattern: "chrome.exe".into(),
        };
        let v: serde_json::Value = serde_json::to_value(&m).unwrap();
        assert_eq!(v["kind"], "process");
        assert_eq!(v["pattern"], "chrome.exe");
    }

    #[test]
    fn matcher_kinds_are_stable_strings() {
        let mp = Matcher::Process {
            pattern: "*".into(),
        };
        let md = Matcher::Domain {
            pattern: "example.com".into(),
        };
        let mi = Matcher::IpSet {
            value: "10.0.0.0/8".into(),
        };
        assert_eq!(mp.kind_str(), "process");
        assert_eq!(md.kind_str(), "domain");
        assert_eq!(mi.kind_str(), "ipset");
    }

    #[test]
    fn scene_summary_dedupes_and_sorts_matcher_kinds() {
        // Three matchers with kinds [ipset, process, process] → "process + ipset"
        let scene = Scene {
            id: "abc".into(),
            name: "demo".into(),
            mode: ModeOverride::Tun,
            enabled: true,
            matchers: vec![
                Matcher::IpSet {
                    value: "10.0.0.0/8".into(),
                },
                Matcher::Process {
                    pattern: "a.exe".into(),
                },
                Matcher::Process {
                    pattern: "b.exe".into(),
                },
            ],
            created_at: "2026-06-07T00:00:00Z".into(),
            updated_at: "2026-06-07T00:00:00Z".into(),
        };
        let summary = SceneSummary::from_scene(&scene);
        assert_eq!(summary.matcher_count, 3);
        // Sorted alphabetically: "ipset" < "process".
        assert_eq!(summary.matcher_kinds, "ipset + process");
    }
}
