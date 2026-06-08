# Helper LPE-class Issue Pattern — Disclosure (Placeholder)

> **Status:** DRAFT — not yet published. Tracking document for the
> caller-validation hardening landed in v2.4.1. The public disclosure
> write-up will be released alongside the fix once a coordinated
> timeline is agreed.

## Summary

`RiptideHelper` (SMJobBless-privileged XPC service) accepted XPC
connections from any local process before v2.4.1. The listener did
not validate the caller's audit token or code-signing identifier, and
the client side did not declare a code-signing requirement. A local
attacker with a session on the machine could connect to the helper
and invoke privileged operations (binary download paths, config
writes under `~/Library/Application Support/Riptide/mihomo/`,
service-management routines) as root.

## Resolution (v2.4.1)

Three layers of caller verification, mirroring the
CVE-2019-13013 (Little Snitch) /
CVE-2018-4032..4037 + CVE-2019-5011 (CleanMyMac) pattern:

1. **Listener-side audit-token check** — `HelperCallerValidator`
   inspects the connection's `audit_token_t` and rejects unsigned
   or foreign callers via an explicit allowlist.
2. **`SMAuthorizedClients` allowlist** —
   `RiptideHelper/Resources/audit-policy.plist` declares the
   caller allowlist; the real Apple Developer Team ID replaces the
   `YOUR_TEAM_ID` placeholder before shipping.
3. **Client-side `setCodeSigningRequirement`** — the host app
   declares its signing requirement on the outgoing
   `NSXPCConnection`, closing the reverse-direction gap.

## CI guard

`HelperEndpointTestHarness` reproduces the LPE-style access path
under a simulated-fixture audit token. Any future regression in
the validator lands as a test failure before merge.

## Scope & limits

- The fix closes the **issue pattern** (missing audit-token
  validation + missing client requirement). It does **not**
  audit the helper's per-method authorization model; that
  remains a follow-up.
- The `extractCallerAuditToken` path is currently populated by
  `SecCodeCopySelf` as a placeholder; the production path uses
  `SecCodeCopyGuestWithAttributes(... kSecGuestAttributeAudit ...)`
  to read the host's real `audit_token_t` from the incoming
  connection. Tracked in a follow-up task.

## Related

- ADR-0004: Helper trust model — [docs/decisions/0004-helper-trust-model.md](../decisions/0004-helper-trust-model.md)
- HelperCallerValidator: `Sources/Riptide/XPC/HelperCallerValidator.swift`
- audit-policy.plist: `RiptideHelper/Resources/audit-policy.plist`
- HelperEndpointTestHarness: `Tests/RiptideTests/HelperEndpointTestHarnessTests.swift`
