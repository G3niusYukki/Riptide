# Riptide macOS 1.0 Release Checklist

## Alpha Verification Gates

### Automated Verification

- [x] `swift build` passes cleanly (0 errors)
- [x] `swift test` — all 126 tests pass

### Manual Alpha Cycle Checks

- [ ] 20 clean System Proxy start/stop cycles
- [ ] 10 clean reload cycles
- [ ] Daily-use traffic matrix (System Proxy mode):
  - [ ] Safari/Chrome HTTPS browsing
  - [ ] `curl https://` requests
  - [ ] `git` over HTTPS
  - [ ] `swift build` dependency/network path
  - [ ] One long-lived chat/streaming session
- [ ] Non-CLI import → start → browse → inspect logs → stop flow

### Quality Gates

- [ ] Zero known P0 crashes
- [ ] Zero unresolved state-desync bugs that block restart
- [ ] Menu bar status indicator updates correctly
- [ ] Mode picker switches between system proxy and TUN
- [ ] Profile import from YAML succeeds
- [ ] Subscription profile addition succeeds (with placeholder URL)

---

## Beta Verification Gates

### Automated Verification

- [ ] `swift build` passes cleanly
- [ ] `swift test` — all tests pass
- [ ] 20 consecutive TUN start/stop cycles (primary setup)
- [ ] Daily-use traffic matrix in both modes:
  - [ ] System Proxy mode: see Alpha checks
  - [ ] TUN mode: same traffic matrix

### Feature Completeness

- [ ] TUN mode starts and stops cleanly
- [ ] Visible fallback recommendation when TUN start fails
- [ ] Proxy groups (Select, URL-Test, Fallback) route correctly
- [ ] DNS policy respected in both modes
- [ ] Subscription refresh updates active profile
- [ ] App group shared state visible to extension

### Quality Gates

- [ ] Zero known P0 defects
- [ ] At most 5 open P1 defects
- [ ] No mode state desync after 10 reload cycles

---

## RC / Release Verification Gates

### Automated Verification

- [ ] `swift build` passes cleanly
- [ ] `swift test` — all tests pass
- [ ] 50 clean start/stop cycles across both modes
- [ ] 25 clean reload cycles
- [ ] 24-hour soak on primary test machine

### Defect Count

- [ ] Zero known P0 or P1 defects
- [ ] At most 3 open P2 defects

### Documentation

- [ ] Release notes written
- [ ] Troubleshooting docs updated
- [ ] README.md reflects supported 1.0 capabilities
- [ ] Compatibility matrix up to date
