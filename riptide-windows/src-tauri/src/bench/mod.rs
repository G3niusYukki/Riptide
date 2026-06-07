//! Engine benchmark subsystem — cross-platform mihomo perf baseline.
//!
//! MVP scope (C6): implement only the two simplest dimensions —
//! `http_connect_p50` and `startup` — against mihomo as the primary
//! engine. Other engines (singbox, swift) are reported as
//! "not implemented". The harness shape and JSON contract are
//! the deliverable; running against a real mihomo binary is a
//! follow-up (Phase C, late) — see ADR-0005 for engine routing.
//!
//! The module is split into:
//!
//! - [`engine`] — the `EngineKind` enum and the binary resolver.
//! - [`report`] — the JSON-serializable [`report::BenchmarkReport`]
//!   tree returned to the JS layer and the CI artifact.
//! - [`harness`] — the orchestrator. Walks the requested dimensions,
//!   probes the engine binary, and emits a `BenchmarkReport` with
//!   one [`report::DimensionResult`] per dimension.
//!
//! The harness is **synchronous** internally (no `tokio::spawn`,
//! no `tauri::async_runtime::spawn`). The Tauri command wrapper
//! is `async` for forward-compat with future I/O-bound dimensions
//! (throughput, idle-memory) but the MVP path is pure CPU + a
//! single blocking TCP dial. This keeps the unit tests free of
//! runtime-availability concerns (see the c6 team memory:
//! "tauri::async_runtime::spawn in test code is a no-op").

pub mod engine;
pub mod harness;
pub mod report;

pub use engine::EngineKind;
pub use harness::run_benchmark;
pub use report::{
    BenchmarkReport, DimensionResult, DimensionStatus, MetricSample, MetricSummary,
    SkippedDimension,
};
