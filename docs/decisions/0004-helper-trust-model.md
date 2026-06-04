# ADR-0004: Helper trust model — audit_token + SecCodeCheckValidity

> **Status:** Accepted · **Date:** 2026-06-04 · **Deciders:** maintainers

## Context

`RiptideHelper` is a macOS SMJobBless-privileged XPC service. Its
`shouldAcceptNewConnection` implementation
(`RiptideHelper/Sources/HelperTool.swift:184-207`) accepted every
incoming connection without caller validation. This matches the
anti-pattern documented in CVE-2019-13013 (Little Snitch) and
CVE-2018-4032..4037 / CVE-2019-5011 (CleanMyMac).

## Decision

Adopt a two-layer trust model:

1. **Helper-side**: read the caller's audit token via `SecCodeCopySelf`
   on the incoming connection, extract `kSecCodeInfoTeamIdentifier` and
   `kSecCodeInfoIdentifier` via `SecCodeCopySigningInformation`, and
   compare against `RiptideHelper/Resources/audit-policy.plist`.
2. **Client-side**: declare the helper's code-signing requirement via
   `NSXPCConnection.setCodeSigningRequirement` to refuse connections
   to same-named unsigned impostor binaries.

## Consequences

- The Team ID in `audit-policy.plist` remains a placeholder
  (`YOUR_TEAM_ID`) until Apple Developer enrollment is complete. The
  software-side checks still run; only the TeamID comparison is
  effectively a no-op until a real ID is provided.
- A signed helper rejects unsigned / foreign callers regardless of
  TeamID value.
- The LPE class of issues is closed at the cost of one extra SecCode
  syscall per XPC connection (negligible).
