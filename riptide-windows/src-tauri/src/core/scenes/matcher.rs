//! Pure matching logic for [`Matcher`] clauses and [`Scene`]s.
//!
//! No IO, no async. Used by [`SceneStore::apply`] and by unit tests.
//! The matching surface intentionally stays narrow in this MVP:
//! process patterns are exact (case-insensitive) basenames; domains
//! are suffix matches; IP sets are exact CIDR membership.

use super::types::{Matcher, Scene};

/// Test whether `process_name` matches a `process:` matcher pattern.
/// The match is case-insensitive on Windows (process names are not).
/// `pattern == "*"` matches anything; otherwise it must equal the
/// basename of the executable (the part after the last `\`).
pub fn match_process_pattern(pattern: &str, process_name: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    let basename = process_name
        .rsplit(['\\', '/'])
        .next()
        .unwrap_or(process_name);
    basename.eq_ignore_ascii_case(pattern.trim())
}

/// Test whether `domain` matches a `domain:` matcher pattern. The
/// pattern is treated as a suffix: a leading `*.` is stripped and the
/// match is then `domain == pattern || domain.ends_with("." + pattern)`.
/// A bare `*` matches anything.
pub fn match_domain_pattern(pattern: &str, domain: &str) -> bool {
    if pattern == "*" || domain == pattern {
        return true;
    }
    let pat = pattern.trim().trim_start_matches("*.");
    if pat.is_empty() {
        return true;
    }
    let d = domain.trim().to_ascii_lowercase();
    let p = pat.to_ascii_lowercase();
    d == p || d.ends_with(&format!(".{p}"))
}

/// Test whether `ip` is a member of the CIDR described by `cidr`.
/// IPv4 only in this MVP — IPv6 inputs always return `false` so
/// callers can fall back to a sensible default instead of mis-routing.
pub fn match_ipset(cidr: &str, ip: &str) -> bool {
    let (network, bits) = match parse_v4_cidr(cidr) {
        Some(t) => t,
        None => return false,
    };
    let target = match parse_v4(ip) {
        Some(v) => v,
        None => return false,
    };
    if bits == 0 {
        return true;
    }
    let mask = if bits >= 32 { u32::MAX } else { u32::MAX << (32 - bits) };
    (target & mask) == (network & mask)
}

/// Apply a single scene to a probe tuple `(process, domain, ip)`.
/// Returns `true` iff at least one matcher fires. Used by
/// `SceneStore::apply` to decide which scene to surface.
pub fn scene_applies(scene: &Scene, process: &str, domain: &str, ip: &str) -> bool {
    if !scene.enabled {
        return false;
    }
    scene.matchers.iter().any(|m| match m {
        Matcher::Process { pattern } => match_process_pattern(pattern, process),
        Matcher::Domain { pattern } => match_domain_pattern(pattern, domain),
        Matcher::IpSet { value } => match_ipset(value, ip),
    })
}

// ── internal: tiny IPv4 parser (no std::net — keeps `matcher` pure) ──

fn parse_v4(s: &str) -> Option<u32> {
    let parts: Vec<&str> = s.split('.').collect();
    if parts.len() != 4 {
        return None;
    }
    let mut out: u32 = 0;
    for p in parts {
        let n: u32 = p.parse().ok()?;
        if n > 255 {
            return None;
        }
        out = (out << 8) | n;
    }
    Some(out)
}

fn parse_v4_cidr(s: &str) -> Option<(u32, u32)> {
    let (ip, bits) = match s.split_once('/') {
        Some((a, b)) => (a, b.parse::<u32>().ok()?),
        None => (s, 32u32),
    };
    if bits > 32 {
        return None;
    }
    Some((parse_v4(ip)?, bits))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::scenes::types::{ModeOverride, Matcher, Scene};

    fn scene(matchers: Vec<Matcher>) -> Scene {
        Scene {
            id: "x".into(),
            name: "x".into(),
            mode: ModeOverride::Tun,
            enabled: true,
            matchers,
            created_at: String::new(),
            updated_at: String::new(),
        }
    }

    #[test]
    fn process_pattern_matches_basename_case_insensitive() {
        assert!(match_process_pattern("chrome.exe", "C:\\Program Files\\Chrome\\chrome.exe"));
        assert!(match_process_pattern("CHROME.EXE", "chrome.exe"));
        assert!(!match_process_pattern("chrome.exe", "firefox.exe"));
    }

    #[test]
    fn process_wildcard_matches_anything() {
        assert!(match_process_pattern("*", "anything"));
        assert!(!match_process_pattern("", "anything"));
    }

    #[test]
    fn domain_pattern_is_suffix() {
        assert!(match_domain_pattern("example.com", "example.com"));
        assert!(match_domain_pattern("example.com", "api.example.com"));
        assert!(match_domain_pattern("*.example.com", "api.example.com"));
        assert!(!match_domain_pattern("example.com", "notexample.com"));
    }

    #[test]
    fn ipset_matches_cidr() {
        assert!(match_ipset("10.0.0.0/8", "10.1.2.3"));
        assert!(match_ipset("10.0.0.0/8", "10.255.255.255"));
        assert!(!match_ipset("10.0.0.0/8", "11.0.0.1"));
        // /32 = exact match
        assert!(match_ipset("1.2.3.4/32", "1.2.3.4"));
        assert!(!match_ipset("1.2.3.4/32", "1.2.3.5"));
        // No prefix = /32
        assert!(match_ipset("1.2.3.4", "1.2.3.4"));
        assert!(!match_ipset("1.2.3.4", "1.2.3.5"));
    }

    #[test]
    fn scene_applies_uses_logical_or() {
        // Any matcher firing is enough.
        let s = scene(vec![
            Matcher::Process { pattern: "x.exe".into() },
            Matcher::Domain { pattern: "example.com".into() },
        ]);
        assert!(scene_applies(&s, "x.exe", "", ""));
        assert!(scene_applies(&s, "", "api.example.com", ""));
        assert!(!scene_applies(&s, "", "other.com", ""));
    }

    #[test]
    fn disabled_scene_never_applies() {
        let mut s = scene(vec![Matcher::Process { pattern: "*".into() }]);
        s.enabled = false;
        assert!(!scene_applies(&s, "anything", "anything", "1.2.3.4"));
    }

    #[test]
    fn scene_covers_all_three_matcher_kinds() {
        // Smoke: a scene with one of each kind applies via any of
        // the three match paths. This is the C8.3 "renders 3 matcher
        // kinds" gate on the frontend side; on the Rust side we just
        // confirm the union works end-to-end.
        let s = scene(vec![
            Matcher::Process { pattern: "x.exe".into() },
            Matcher::Domain { pattern: "example.com".into() },
            Matcher::IpSet { value: "10.0.0.0/8".into() },
        ]);
        assert!(scene_applies(&s, "x.exe", "any", "9.9.9.9"));
        assert!(scene_applies(&s, "y.exe", "example.com", "9.9.9.9"));
        assert!(scene_applies(&s, "y.exe", "other.com", "10.0.0.5"));
        assert!(!scene_applies(&s, "y.exe", "other.com", "9.9.9.9"));
    }
}
