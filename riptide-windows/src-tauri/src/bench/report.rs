//! Serializable report types. Every field is `pub` + `Serialize` +
//! `Deserialize` so the same struct round-trips through
//! `serde_json::to_value` in the JS boundary and the GitHub
//! Actions artifact uploader.
//!
//! The shape mirrors the macOS `EngineBenchmarkTests` Swift report
//! (C6 is the cross-platform parity deliverable). The five
//! dimension kinds (http_connect_p50, throughput, idle_memory, cpu,
//! startup) are listed in [`DimensionId`]; only the first and last
//! are implemented in the MVP. The other three are surfaced as
//! [`SkippedDimension`] entries with reason "not implemented in
//! MVP" — that is the contract the macOS Swift side will match.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::engine::EngineKind;

/// All five engine-benchmark dimension kinds. The MVP implements
/// `HttpConnectP50` and `Startup`; the rest are surfaced as
/// skipped so callers see a stable JSON shape across the full
/// five-dimension matrix.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DimensionId {
    /// Time from CONNECT request to first response byte, p50 / p99.
    HttpConnectP50,
    /// Sustained proxy throughput, bytes/sec.
    Throughput,
    /// Resident memory after the engine idles for N seconds.
    IdleMemory,
    /// Steady-state CPU%, sampled over a 5 s window.
    Cpu,
    /// Time from binary spawn to the controller REST API being ready.
    Startup,
}

impl DimensionId {
    /// Wire string used in `bench_run(dimensions = ["http_connect_p50", ...])`.
    pub const fn as_str(self) -> &'static str {
        match self {
            DimensionId::HttpConnectP50 => "http_connect_p50",
            DimensionId::Throughput => "throughput",
            DimensionId::IdleMemory => "idle_memory",
            DimensionId::Cpu => "cpu",
            DimensionId::Startup => "startup",
        }
    }

    /// All five dimensions — used when the caller passes `None` /
    /// empty `dimensions` to `bench_run`.
    pub const ALL: [DimensionId; 5] = [
        DimensionId::HttpConnectP50,
        DimensionId::Throughput,
        DimensionId::IdleMemory,
        DimensionId::Cpu,
        DimensionId::Startup,
    ];

    /// True for the two dimensions the MVP actually measures.
    /// Used by the harness to decide `Completed` vs `Skipped`.
    pub const fn is_mvp_implemented(self) -> bool {
        matches!(self, DimensionId::HttpConnectP50 | DimensionId::Startup)
    }
}

impl std::str::FromStr for DimensionId {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "http_connect_p50" => Ok(DimensionId::HttpConnectP50),
            "throughput" => Ok(DimensionId::Throughput),
            "idle_memory" => Ok(DimensionId::IdleMemory),
            "cpu" => Ok(DimensionId::Cpu),
            "startup" => Ok(DimensionId::Startup),
            other => Err(format!("unknown dimension: {other}")),
        }
    }
}

/// Run outcome for one dimension.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DimensionStatus {
    /// Measurement ran, samples populated.
    Completed,
    /// Engine binary missing or dimension not in MVP scope.
    Skipped,
    /// Measurement ran but the harness returned an error
    /// (e.g. timeout, controller not ready).
    Failed,
}

/// Per-iteration sample. `duration_ms` is wall-clock time for
/// the iteration; `success` is false if the iteration failed
/// (e.g. CONNECT timed out).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MetricSample {
    pub iteration: u32,
    pub duration_ms: f64,
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Aggregated stats over the iteration samples.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MetricSummary {
    /// 50th-percentile duration in ms. `None` when no samples succeeded.
    pub p50_ms: Option<f64>,
    /// 99th-percentile duration in ms. `None` when fewer than ~100 samples.
    pub p99_ms: Option<f64>,
    /// Arithmetic mean of `duration_ms` across all iterations.
    pub mean_ms: f64,
    pub min_ms: f64,
    pub max_ms: f64,
    /// Population standard deviation. 0.0 when n < 2.
    pub stddev_ms: f64,
    /// Count of iterations that completed without error.
    pub successful: u32,
    /// Total iterations attempted.
    pub total: u32,
}

/// One row in `BenchmarkReport.dimensions`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DimensionResult {
    pub name: String,
    pub status: DimensionStatus,
    pub iterations: u32,
    pub samples: Vec<MetricSample>,
    pub summary: MetricSummary,
    /// Free-text reason for `Skipped` / `Failed` (e.g. "mihomo.exe not found at ...").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// A dimension the harness declined to attempt. Mirrors
/// `DimensionResult { status: Skipped }` but is its own struct
/// so callers can quickly enumerate "what was missing" without
/// scanning the full `dimensions` array.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SkippedDimension {
    pub name: String,
    pub reason: String,
}

/// Top-level report. One per `bench_run` call.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BenchmarkReport {
    /// ISO 8601 timestamp at harness start.
    pub started_at: DateTime<Utc>,
    /// ISO 8601 timestamp at harness finish.
    pub finished_at: DateTime<Utc>,
    /// `"windows"` / `"macos"` / `"linux"`. Sourced from
    /// `std::env::consts::OS`.
    pub platform: String,
    /// Engine under test. See [`super::engine::EngineKind`].
    pub engine: EngineKind,
    /// Resolution result for the engine. Always populated even
    /// when all dimensions are skipped — the JS layer can render
    /// "no mihomo binary found at …" without a follow-up command.
    pub engine_binary: Option<String>,
    /// Per-dimension results, in the same order as the request.
    pub dimensions: Vec<DimensionResult>,
}

impl BenchmarkReport {
    /// Build a new report with the current timestamp and platform.
    pub fn new_started(engine: EngineKind, engine_binary: Option<String>) -> Self {
        Self {
            started_at: Utc::now(),
            finished_at: Utc::now(),
            platform: std::env::consts::OS.to_string(),
            engine,
            engine_binary,
            dimensions: Vec::new(),
        }
    }

    /// Stamp `finished_at = now()` and consume self.
    pub fn finish(mut self) -> Self {
        self.finished_at = Utc::now();
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bench::engine::EngineKind;

    /// Wire shape: serializing a report with two dimensions produces
    /// stable JSON keys the CI artifact + JS layer depend on. This
    /// pins the contract — break it and both consumers break.
    #[test]
    fn report_shape_roundtrip() {
        let mut report = BenchmarkReport::new_started(EngineKind::Mihomo, None);
        report.dimensions.push(DimensionResult {
            name: "http_connect_p50".into(),
            status: DimensionStatus::Completed,
            iterations: 3,
            samples: vec![
                MetricSample { iteration: 1, duration_ms: 1.0, success: true, error: None },
                MetricSample { iteration: 2, duration_ms: 2.0, success: true, error: None },
                MetricSample { iteration: 3, duration_ms: 3.0, success: true, error: None },
            ],
            summary: MetricSummary {
                p50_ms: Some(2.0),
                p99_ms: Some(3.0),
                mean_ms: 2.0,
                min_ms: 1.0,
                max_ms: 3.0,
                stddev_ms: 0.816_496_580_927_726,
                successful: 3,
                total: 3,
            },
            reason: None,
        });
        report.dimensions.push(DimensionResult {
            name: "startup".into(),
            status: DimensionStatus::Skipped,
            iterations: 0,
            samples: vec![],
            summary: MetricSummary {
                p50_ms: None,
                p99_ms: None,
                mean_ms: 0.0,
                min_ms: 0.0,
                max_ms: 0.0,
                stddev_ms: 0.0,
                successful: 0,
                total: 0,
            },
            reason: Some("not implemented in MVP".into()),
        });
        let json: serde_json::Value = serde_json::to_value(&report).unwrap();
        // Top-level keys
        for k in ["started_at", "finished_at", "platform", "engine", "engine_binary", "dimensions"] {
            assert!(json.get(k).is_some(), "missing top-level key: {k}");
        }
        assert_eq!(json["engine"], "mihomo");
        assert_eq!(json["engine_binary"], serde_json::Value::Null);
        let dims = json["dimensions"].as_array().unwrap();
        assert_eq!(dims.len(), 2);
        // First dimension — completed
        assert_eq!(dims[0]["name"], "http_connect_p50");
        assert_eq!(dims[0]["status"], "completed");
        assert_eq!(dims[0]["iterations"], 3);
        let samples = dims[0]["samples"].as_array().unwrap();
        assert_eq!(samples.len(), 3);
        assert_eq!(samples[0]["iteration"], 1);
        assert_eq!(samples[0]["duration_ms"], 1.0);
        assert_eq!(samples[0]["success"], true);
        // p50 / p99 / stddev all present and non-null
        assert!(dims[0]["summary"]["p50_ms"].is_number());
        assert!(dims[0]["summary"]["p99_ms"].is_number());
        assert!(dims[0]["summary"]["stddev_ms"].is_number());
        // Second dimension — skipped with reason
        assert_eq!(dims[1]["name"], "startup");
        assert_eq!(dims[1]["status"], "skipped");
        assert_eq!(dims[1]["reason"], "not implemented in MVP");
        // Round-trip back into a struct
        let decoded: BenchmarkReport = serde_json::from_value(json).unwrap();
        assert_eq!(decoded, report);
        // Status enum round-trips (snake_case wire string)
        assert_eq!(decoded.dimensions[0].status, DimensionStatus::Completed);
        assert_eq!(decoded.dimensions[1].status, DimensionStatus::Skipped);
    }

    /// DimensionId wires as its snake_case string and parses back.
    /// Pins the contract for the `dimensions: Vec<String>` arg of
    /// `bench_run`.
    #[test]
    fn dimension_id_wire_string_roundtrip() {
        for d in DimensionId::ALL {
            let s = d.as_str();
            let parsed: DimensionId = s.parse().unwrap();
            assert_eq!(parsed, d);
            let json = serde_json::to_string(&d).unwrap();
            assert_eq!(json, format!("\"{s}\""));
        }
        // Unknown names fail loudly so the harness can surface a
        // clear "unknown dimension: foo" error to the JS layer
        // rather than silently ignoring typos.
        assert!("foo".parse::<DimensionId>().is_err());
    }
}
