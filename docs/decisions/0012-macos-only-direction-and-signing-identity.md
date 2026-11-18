# ADR-0012: macOS-only direction and project-owned signing identity

> **Status:** Accepted (direction) · **Date:** 2026-11-18 · **Deciders:** 用户 / maintainers
> **Implementation:** landed in 2.10.0 for the TUN owner, CI/release cut, and dashboard design system. Developer ID notarisation is still outstanding.

## Context

A 2026-11-18 REA static comparison of Surge 6.12.0 and Clash Verge 2.4.7
showed both reference apps are macOS-native in their TUN ownership, and that
Riptide already ships a Clash Verge-style privileged mihomo service
(`riptide-mihomo-service`, CHANGELOG [2.9.0]). The user decided multi-platform
maintenance (Windows Tauri port + Linux CI) is no longer worth the cost, and
asked to focus on macOS.

The helper trust model (ADR-0004) shipped with a `YOUR_TEAM_ID` placeholder
in `RiptideHelper/Resources/audit-policy.plist` and a matching placeholder in
`SMAuthorizedClients`. The user confirmed the project-owned signing identity
and authorised wiring it in, with the explicit constraint that **no certificate
is uploaded to GitHub**.

The comparison that led here was Surge and Clash Verge on macOS. The written spec was removed when the docs were cut down to this ADR.

## Decision

1. **macOS 14+ is the only target.** `riptide-windows/` has been deleted.
   CI and release publish the macOS DMG and ZIP only.
2. **TUN backend** converges on mihomo Service Mode (launchd daemon + UDS),
   consistent with ADR D3 Option A. The NetworkExtension target remains a
   reference/experimental implementation, not a second live TUN owner.
3. **Signing identity is project-owned.** Only public metadata is committed:
   - helper `allowedTeamID`: `39Q4M52XNQ` (real `TeamIdentifier`, verified by
     `codesign -dvvv` on a locally signed probe);
   - `SMAuthorizedClients`: `cert leaf[subject.OU] = "39Q4M52XNQ"` plus
     `identifier com.riptide.app` and `anchor apple generic`;
   - `allowedBundleID` aligned from `com.riptide.client` to the actual
     shipped app bundle ID `com.riptide.app`.
   - `subject.OU` is used instead of the certificate CN so no personal name
     is committed, and so the same requirement works for both Apple
     Development and future Developer ID Application certificates.
4. **No secret material in git.** `.gitignore` now ignores `*.p12`, `*.pfx`,
   `*.cer`, `*.mobileprovision`. Certificate files, private keys, p12/PEM
   bundles and CI secrets are never committed. The identity is an Apple
   Development certificate; a separate **Developer ID Application**
   certificate plus notarisation secrets are still required for public
   distribution (`docs/signing-setup.md`, `.github/workflows/release.yml`).

## Consequences

- Helper caller validation becomes effective instead of a no-op Team ID
  comparison; the bundle-ID mismatch that would otherwise reject the real
  app is resolved.
- `Scripts/setup-signing.sh` will still warn that no Developer ID
  Application identity is installed locally; that is expected and is not a
  regression.
- Signing does **not** remove macOS TUN restrictions: root is obtained via
  the one-time LaunchDaemon install, and Network Extension entitlements /
  user approval are still required if Option C is ever taken (ADR D3).
- The Windows tree and its docs are gone. README and AGENTS.md describe macOS only.
- A regression test (`Tests/RiptideTests/HelperTrustConfigurationTests.swift`)
  pins the shipped helper policy values and fails if a placeholder returns.

## Related

- ADR-0004: Helper trust model — `docs/decisions/0004-helper-trust-model.md`
- ADR D3: Service Mode route — `docs/decisions/2026-06-02-d3-service-mode.md`
- Signing setup — `docs/signing-setup.md`
