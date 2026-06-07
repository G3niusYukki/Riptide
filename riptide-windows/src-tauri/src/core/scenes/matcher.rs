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
/// Supports both IPv4 (`10.0.0.0/8`, `1.2.3.4`) and IPv6
/// (`fd00::/8`, `2001:db8::1`). Mixed-family comparisons (an IPv4
/// CIDR probed with an IPv6 address, or vice versa) always return
/// `false` so callers can fall back to a sensible default instead
/// of mis-routing.
pub fn match_ipset(cidr: &str, ip: &str) -> bool {
    if let (Some((net, bits)), Some(target)) = (parse_v4_cidr(cidr), parse_v4(ip)) {
        if bits == 0 {
            return true;
        }
        let mask = if bits >= 32 {
            u32::MAX
        } else {
            u32::MAX << (32 - bits)
        };
        return (target & mask) == (net & mask);
    }
    if let (Some((net, bits)), Some(target)) = (parse_v6_cidr(cidr), parse_v6(ip)) {
        return v6_match(&net, &target, bits);
    }
    false
}

/// Compare two IPv6 addresses under a /bits prefix. `bits` may be
/// 0 (match anything) or up to 128 (exact match). The address is
/// stored as 8 u16 groups, big-endian.
fn v6_match(net: &[u16; 8], target: &[u16; 8], bits: u32) -> bool {
    if bits == 0 {
        return true;
    }
    let bits = bits.min(128);
    let full_groups = (bits / 16) as usize;
    let partial_bits = bits % 16;
    for i in 0..full_groups {
        if net[i] != target[i] {
            return false;
        }
    }
    if partial_bits > 0 && full_groups < 8 {
        let mask = 0xFFFF_u16 << (16 - partial_bits);
        if (net[full_groups] & mask) != (target[full_groups] & mask) {
            return false;
        }
    }
    true
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

/// Parse an IPv6 address into 8 big-endian u16 groups. Accepts
/// the canonical 8-group form, the `::` zero-run shorthand, and
/// the dual IPv4-mapped tail (e.g. `::ffff:1.2.3.4`).
fn parse_v6(s: &str) -> Option<[u16; 8]> {
    let s = s.split('%').next()?;
    let (s, v4_tail) = if let Some((head, last)) = s.rsplit_once(':') {
        if last.contains('.') {
            let v4 = parse_v4(last)?;
            let hi = ((v4 >> 16) & 0xFFFF) as u16;
            let lo = (v4 & 0xFFFF) as u16;
            (head, Some([hi, lo]))
        } else {
            (s, None)
        }
    } else {
        (s, None)
    };
    if let Some(tail) = v4_tail {
        let mut groups = parse_v6_groups(s)?;
        if groups[6] != 0 || groups[7] != 0 {
            return None;
        }
        groups[6] = tail[0];
        groups[7] = tail[1];
        return Some(groups);
    }
    parse_v6_groups(s)
}

/// Parse 8 u16 groups separated by `:`, with optional `::` shorthand.
fn parse_v6_groups(s: &str) -> Option<[u16; 8]> {
    if s.is_empty() {
        return None;
    }
    if s == "::" {
        return Some([0; 8]);
    }
    if let Some((left, right)) = s.split_once("::") {
        let left_groups: Vec<u16> = if left.is_empty() {
            Vec::new()
        } else {
            left.split(':').map(hex_u16).collect::<Option<_>>()?
        };
        let right_groups: Vec<u16> = if right.is_empty() {
            Vec::new()
        } else {
            right.split(':').map(hex_u16).collect::<Option<_>>()?
        };
        if left_groups.len() + right_groups.len() >= 8 {
            return None;
        }
        let mut out = [0u16; 8];
        for (i, g) in left_groups.iter().enumerate() {
            out[i] = *g;
        }
        for (i, g) in right_groups.iter().rev().enumerate() {
            out[7 - i] = *g;
        }
        return Some(out);
    }
    let groups: Vec<u16> = s.split(':').map(hex_u16).collect::<Option<_>>()?;
    if groups.len() != 8 {
        return None;
    }
    Some([
        groups[0], groups[1], groups[2], groups[3], groups[4], groups[5], groups[6], groups[7],
    ])
}

fn hex_u16(s: &str) -> Option<u16> {
    if s.is_empty() {
        return None;
    }
    u16::from_str_radix(s, 16).ok()
}

fn parse_v6_cidr(s: &str) -> Option<([u16; 8], u32)> {
    let (ip, bits) = match s.split_once('/') {
        Some((a, b)) => (a, b.parse::<u32>().ok()?),
        None => (s, 128u32),
    };
    if bits > 128 {
        return None;
    }
    Some((parse_v6(ip)?, bits))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::scenes::types::{Matcher, ModeOverride, Scene};

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
        assert!(match_process_pattern(
            "chrome.exe",
            "C:\\Program Files\\Chrome\\chrome.exe"
        ));
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
    fn ipset_matches_ipv6_cidr() {
        // /8 hits the first group only
        assert!(match_ipset("fd00::/8", "fd12:3456:789a::1"));
        assert!(match_ipset(
            "fd00::/8",
            "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
        ));
        assert!(!match_ipset("fd00::/8", "fe00::1"));
        // /16 hits the first two groups
        assert!(match_ipset("2001:db8::/32", "2001:db8::1"));
        assert!(!match_ipset("2001:db8::/32", "2001:db9::1"));
        // /128 = exact
        assert!(match_ipset("::1/128", "::1"));
        assert!(!match_ipset("::1/128", "::2"));
        // `::` shorthand (all zeros)
        assert!(match_ipset("::/0", "::1"));
        assert!(match_ipset("::/0", "fd00::1"));
        // No prefix = /128
        assert!(match_ipset("2001:db8::1", "2001:db8::1"));
        assert!(!match_ipset("2001:db8::1", "2001:db8::2"));
    }

    #[test]
    fn ipset_mixed_family_returns_false() {
        // An IPv4 CIDR probed with an IPv6 address must NOT match.
        assert!(!match_ipset("10.0.0.0/8", "fd00::1"));
        // An IPv6 CIDR probed with an IPv4 address must NOT match.
        assert!(!match_ipset("fd00::/8", "10.0.0.1"));
    }

    #[test]
    fn scene_applies_uses_logical_or() {
        // Any matcher firing is enough.
        let s = scene(vec![
            Matcher::Process {
                pattern: "x.exe".into(),
            },
            Matcher::Domain {
                pattern: "example.com".into(),
            },
        ]);
        assert!(scene_applies(&s, "x.exe", "", ""));
        assert!(scene_applies(&s, "", "api.example.com", ""));
        assert!(!scene_applies(&s, "", "other.com", ""));
    }

    #[test]
    fn disabled_scene_never_applies() {
        let mut s = scene(vec![Matcher::Process {
            pattern: "*".into(),
        }]);
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
            Matcher::Process {
                pattern: "x.exe".into(),
            },
            Matcher::Domain {
                pattern: "example.com".into(),
            },
            Matcher::IpSet {
                value: "10.0.0.0/8".into(),
            },
        ]);
        assert!(scene_applies(&s, "x.exe", "any", "9.9.9.9"));
        assert!(scene_applies(&s, "y.exe", "example.com", "9.9.9.9"));
        assert!(scene_applies(&s, "y.exe", "other.com", "10.0.0.5"));
        assert!(!scene_applies(&s, "y.exe", "other.com", "9.9.9.9"));
    }
}
