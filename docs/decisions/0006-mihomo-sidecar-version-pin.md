# ADR-0006: mihomo sidecar version pin policy

> **Status:** Accepted · **Date:** 2026-06-04 · **Deciders:** maintainers

## Context

`Scripts/download-mihomo.sh` historically fetched the latest GitHub
release of MetaCubeX/mihomo at user-install time. This means
different Riptide users on the same version may run different mihomo
versions, complicating bug reports and CVE propagation.

## Decision

- Pin the mihomo version at `Scripts/download-mihomo.sh` level to the
  latest stable as of each Riptide minor release. The version string
  is `MIHOMO_VERSION="v1.18.5"` as of v2.4.1.
- `riptide doctor` (Phase 3) reports the running mihomo version and
  warns if it differs from the pinned version.
- The pin is bumped on each Riptide minor (v2.4.0 → v2.5.0) and on
  each Riptide patch if a CVE-grade mihomo fix lands.

## Consequences

- Reproducible bug reports across the user base.
- CVE fixes in mihomo require an explicit Riptide release; this is a
  conscious trade-off, not a leak.
