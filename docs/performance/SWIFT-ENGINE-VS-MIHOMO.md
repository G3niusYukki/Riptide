# Swift Engine vs mihomo sidecar — Performance Baseline

> **Status:** scaffolding. First real numbers land when
> `.github/workflows/bench.yml` runs in CI. This file is the canonical
> pointer for the "Why Riptide?" performance story.

## Why this matters

Two engines ship in Riptide macOS:

1. **Pure-Swift engine** (`Sources/Riptide/{Protocols,Transport,DNS,Rules,...}`) — runs in-process, no external binary.
2. **mihomo sidecar** (`Sources/Riptide/Mihomo/`) — gVisor TUN stack, broader protocol coverage.

This document records the trade-off so users can pick the right engine for their workload.

## What we measure

| Dimension | What it captures |
|-----------|------------------|
| HTTP CONNECT p50 / p99 | Single-connection latency under loopback load |
| Throughput | Concurrent connection saturation point |
| Idle memory | Steady-state RSS after handshake |
| CPU | Average user+system CPU during load |
| Startup | Cold launch to ready-to-accept-connections |

## How to reproduce

```bash
swift test --filter EngineBenchmarkTests
swift run riptide bench --iterations 1000 --concurrency 16
```

The bench CLI lives in `Sources/RiptideCLI/`. Add `--target mihomo` or `--target swift-engine` to switch.

## Results

> Populated by CI. See the latest `bench` workflow run for raw JSON.

| Engine | p50 (µs) | p99 (µs) | Throughput (req/s) | Idle (KiB) | CPU (%) | Startup (ms) |
|--------|---------:|---------:|-------------------:|-----------:|--------:|-------------:|
| Swift Engine (placeholder) | — | — | — | — | — | — |
| mihomo sidecar (placeholder) | — | — | — | — | — | — |
