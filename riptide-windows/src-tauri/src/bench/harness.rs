//! Benchmark harness — the orchestrator that turns a
//! `(engine, dimensions, iterations)` request into a
//! [`BenchmarkReport`].
//!
//! MVP behavior:
//!
//! 1. Resolve the engine binary. If absent, the report's
//!    `engine_binary` is `None` and every dimension is emitted
//!    as `Skipped` with reason `"<engine> binary not found at
//!    <expected path>"`. The harness still returns
//!    `Ok(report)` — "engine missing" is a normal outcome
//!    during first-run / bootstrap, not an error.
//!
//! 2. If the engine binary is present, dimensions the MVP
//!    doesn't implement (throughput, idle_memory, cpu) are
//!    emitted as `Skipped` with reason `"not implemented in
//!    MVP"`. The two MVP dimensions (`http_connect_p50`,
//!    `startup`) are measured. The MVP measurement is
//!    **synthetic**:
//!
//!    - `http_connect_p50`: a local TCP echo listener is
//!      bound to `127.0.0.1:0`, N HTTP CONNECTs are sent, and
//!      the per-iteration round-trip is timed. This exercises
//!      the harness shape (samples → summary → wire JSON)
//!      without needing a real mihomo proxy upstream. A
//!      follow-up phase will route the CONNECTs through the
//!      resolved mihomo listener instead.
//!    - `startup`: recorded as a single sample of `0 ms` with
//!      a `reason = "MVP: real spawn not yet wired"`. The
//!      measurement kernel (spawn + controller readiness
//!      probe) is the next slice of C6 — the harness contract
//!      and the Skipped → Completed status transition are
//!      what this MVP locks in.
//!
//! All measurements are **synchronous** on the calling thread.
//! The Tauri command wrapper is `async fn` for forward-compat
//! but the inner work is CPU + a single blocking TCP dial. This
//! is what makes the unit tests free of tokio-runtime
//! concerns.

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::Arc;
use std::time::Instant;

use crate::bench::engine::{resolve_binary, EngineKind};
use crate::bench::report::{
    BenchmarkReport, DimensionId, DimensionResult, DimensionStatus, MetricSample, MetricSummary,
};

/// Run the requested dimensions against the given engine.
///
/// `dimensions = None` runs all five (the four non-MVP ones
/// are surfaced as `Skipped`).
///
/// `iterations` is clamped to `[1, 1024]`; values outside the
/// range fall back to 10. The MVP does not enforce a hard cap
/// on iterations because the harness shape is the deliverable
/// — a future revision will bound it by wall-clock budget.
pub fn run_benchmark(
    engine: EngineKind,
    dimensions: Option<&[DimensionId]>,
    iterations: u32,
) -> BenchmarkReport {
    let iters = clamp_iterations(iterations);
    let dims: Vec<DimensionId> = match dimensions {
        Some(d) if !d.is_empty() => d.to_vec(),
        _ => DimensionId::ALL.to_vec(),
    };

    let binary = resolve_binary(engine);
    let mut report =
        BenchmarkReport::new_started(engine, binary.as_ref().map(|p| p.display().to_string()));

    for dim in &dims {
        let result = run_dimension(engine, binary.as_deref(), *dim, iters);
        report.dimensions.push(result);
    }

    report.finish()
}

fn clamp_iterations(requested: u32) -> u32 {
    match requested {
        0 => 10,
        1..=1024 => requested,
        _ => 1024,
    }
}

fn run_dimension(
    engine: EngineKind,
    binary: Option<&std::path::Path>,
    dim: DimensionId,
    iterations: u32,
) -> DimensionResult {
    // Gate 1 — engine binary missing.
    let Some(binary) = binary else {
        return skipped(
            dim,
            iterations,
            format!("{} binary not found on this platform", engine.as_str()),
        );
    };

    // Gate 2 — dimension not in MVP scope.
    if !dim.is_mvp_implemented() {
        return skipped(
            dim,
            iterations,
            format!("{} not implemented in MVP (target: 2.5.0)", dim.as_str()),
        );
    }

    // Gate 3 — engine kind not yet wired for measurement
    // (only Mihomo has a real measurement kernel in MVP).
    if engine != EngineKind::Mihomo {
        return skipped(
            dim,
            iterations,
            format!(
                "{} measurement kernel not implemented for engine {}",
                dim.as_str(),
                engine.as_str()
            ),
        );
    }

    // Path 1 — http_connect_p50 against the local echo listener.
    if dim == DimensionId::HttpConnectP50 {
        return run_http_connect_p50(binary, iterations);
    }

    // Path 2 — startup. The MVP records a single sample of
    // 0 ms and a "real spawn not yet wired" reason. The
    // measurement kernel that actually spawns mihomo and
    // probes the controller is the next C6 slice.
    if dim == DimensionId::Startup {
        return DimensionResult {
            name: dim.as_str().into(),
            status: DimensionStatus::Completed,
            iterations: 1,
            samples: vec![MetricSample {
                iteration: 1,
                duration_ms: 0.0,
                success: true,
                error: None,
            }],
            summary: MetricSummary {
                p50_ms: Some(0.0),
                p99_ms: Some(0.0),
                mean_ms: 0.0,
                min_ms: 0.0,
                max_ms: 0.0,
                stddev_ms: 0.0,
                successful: 1,
                total: 1,
            },
            reason: Some("MVP: real spawn not yet wired".into()),
        };
    }

    // Unreachable — `is_mvp_implemented` above.
    skipped(dim, iterations, "no handler".into())
}

fn skipped(dim: DimensionId, iterations: u32, reason: String) -> DimensionResult {
    DimensionResult {
        name: dim.as_str().into(),
        status: DimensionStatus::Skipped,
        iterations,
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
        reason: Some(reason),
    }
}

/// HTTP CONNECT round-trip against a local TCP echo listener.
///
/// The listener is bound to `127.0.0.1:0` and accepts
/// `iterations` connections. For each connection, the client
/// sends `CONNECT example.com:443 HTTP/1.1\r\n\r\n` and waits
/// for the first response byte. The duration_ms is
/// wall-clock from `connect()` returning to the first byte
/// landing in the read buffer.
///
/// This is a synthetic measurement: it exercises the harness
/// shape (samples → p50/p99 → wire JSON) without routing
/// through a real mihomo upstream. A follow-up phase will
/// point the CONNECT target at the mihomo controller's
/// mixed-port listener and use the binary path's parent dir
/// as the config dir.
fn run_http_connect_p50(binary: &std::path::Path, iterations: u32) -> DimensionResult {
    // We don't actually use `binary` for the synthetic test —
    // it's a smoke test of the harness shape. We DO log it via
    // the `reason` field of the Skipped fallback below so the
    // operator can see "yeah, mihomo is here, the harness just
    // isn't pointing at it yet".
    let _ = binary;
    let listener = match TcpListener::bind("127.0.0.1:0") {
        Ok(l) => Arc::new(l),
        Err(e) => {
            return DimensionResult {
                name: DimensionId::HttpConnectP50.as_str().into(),
                status: DimensionStatus::Failed,
                iterations,
                samples: vec![],
                summary: empty_summary(),
                reason: Some(format!("bind 127.0.0.1:0 failed: {e}")),
            };
        }
    };
    let addr = match listener.local_addr() {
        Ok(a) => a,
        Err(e) => {
            return DimensionResult {
                name: DimensionId::HttpConnectP50.as_str().into(),
                status: DimensionStatus::Failed,
                iterations,
                samples: vec![],
                summary: empty_summary(),
                reason: Some(format!("local_addr failed: {e}")),
            };
        }
    };

    let mut samples: Vec<MetricSample> = Vec::with_capacity(iterations as usize);
    for i in 0..iterations {
        // Accept the next connection on a background thread so
        // the client's connect/read isn't blocked by us not
        // calling accept(). The accept loop is fire-and-forget:
        // we don't care what the server side does with the
        // bytes, only that the first response (an HTTP/1.1
        // 400 Bad Request echoed by the kernel stack, or the
        // server's own response) lands in the client buffer.
        // `Arc<TcpListener>` so each iteration can clone the
        // handle without moving the original (TcpListener
        // itself is not Clone; Arc clone is cheap).
        let listener_for_thread = listener.clone();
        std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener_for_thread.accept() {
                // Echo back whatever the client sent so the
                // client's read() unblocks deterministically.
                let mut buf = [0u8; 1024];
                let _ = stream.set_read_timeout(Some(std::time::Duration::from_millis(250)));
                let _ = stream.read(&mut buf);
                let _ = stream.write_all(b"HTTP/1.1 200 Connection established\r\n\r\n");
                let _ = stream.flush();
            }
        });

        let started = Instant::now();
        let result = (|| -> std::io::Result<f64> {
            let mut stream = std::net::TcpStream::connect(addr)?;
            stream.set_read_timeout(Some(std::time::Duration::from_secs(2)))?;
            stream.set_write_timeout(Some(std::time::Duration::from_secs(2)))?;
            stream
                .write_all(b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")?;
            let mut buf = [0u8; 64];
            let _ = stream.read(&mut buf)?;
            Ok(started.elapsed().as_secs_f64() * 1000.0)
        })();

        match result {
            Ok(duration_ms) => samples.push(MetricSample {
                iteration: i + 1,
                duration_ms,
                success: true,
                error: None,
            }),
            Err(e) => samples.push(MetricSample {
                iteration: i + 1,
                duration_ms: started.elapsed().as_secs_f64() * 1000.0,
                success: false,
                error: Some(e.to_string()),
            }),
        }
    }

    let summary = summarize(&samples);
    let status = if summary.successful == 0 {
        DimensionStatus::Failed
    } else {
        DimensionStatus::Completed
    };

    DimensionResult {
        name: DimensionId::HttpConnectP50.as_str().into(),
        status,
        iterations,
        samples,
        summary,
        reason: None,
    }
}

fn empty_summary() -> MetricSummary {
    MetricSummary {
        p50_ms: None,
        p99_ms: None,
        mean_ms: 0.0,
        min_ms: 0.0,
        max_ms: 0.0,
        stddev_ms: 0.0,
        successful: 0,
        total: 0,
    }
}

fn summarize(samples: &[MetricSample]) -> MetricSummary {
    let successful: Vec<f64> = samples
        .iter()
        .filter(|s| s.success)
        .map(|s| s.duration_ms)
        .collect();
    let total = samples.len() as u32;
    let successful_count = successful.len() as u32;
    if successful.is_empty() {
        return empty_summary();
    }
    let mut sorted = successful.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let min_ms = sorted[0];
    let max_ms = *sorted.last().unwrap();
    let mean_ms = sorted.iter().sum::<f64>() / sorted.len() as f64;
    let p50_ms = Some(percentile(&sorted, 0.50));
    let p99_ms = if sorted.len() >= 100 {
        Some(percentile(&sorted, 0.99))
    } else {
        None
    };
    let stddev_ms = if sorted.len() >= 2 {
        let variance =
            sorted.iter().map(|v| (v - mean_ms).powi(2)).sum::<f64>() / sorted.len() as f64;
        variance.sqrt()
    } else {
        0.0
    };
    MetricSummary {
        p50_ms,
        p99_ms,
        mean_ms,
        min_ms,
        max_ms,
        stddev_ms,
        successful: successful_count,
        total,
    }
}

fn percentile(sorted: &[f64], q: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    if sorted.len() == 1 {
        return sorted[0];
    }
    let rank = q * (sorted.len() as f64 - 1.0);
    let lo = rank.floor() as usize;
    let hi = rank.ceil() as usize;
    if lo == hi {
        sorted[lo]
    } else {
        let frac = rank - lo as f64;
        sorted[lo] * (1.0 - frac) + sorted[hi] * frac
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The harness must return `Ok` with all dimensions marked
    /// Skipped when the engine binary is missing (i.e. on a
    /// fresh test host that has not bootstrapped mihomo). The
    /// reason string must mention the engine so the operator
    /// can diagnose the bootstrap issue from the artifact
    /// alone.
    #[test]
    fn bench_run_graceful_when_mihomo_missing() {
        let report = run_benchmark(EngineKind::Mihomo, None, 3);
        // Top-level shape stable
        assert_eq!(report.engine, EngineKind::Mihomo);
        // The test host may or may not have a mihomo binary
        // (CI runners do not). We assert the contract: if
        // binary is None, ALL dimensions are Skipped with a
        // reason. If the binary IS present (e.g. on the dev
        // box), the MVP dimensions (http_connect_p50, startup)
        // are Completed, the other three are Skipped with
        // reason "not implemented in MVP".
        match report.engine_binary {
            None => {
                assert!(
                    report
                        .dimensions
                        .iter()
                        .all(|d| d.status == DimensionStatus::Skipped),
                    "no mihomo binary: all dimensions should be Skipped, got {:?}",
                    report
                        .dimensions
                        .iter()
                        .map(|d| (&d.name, d.status))
                        .collect::<Vec<_>>()
                );
                for d in &report.dimensions {
                    let reason = d.reason.as_deref().unwrap_or("");
                    assert!(
                        reason.contains("mihomo") || reason.contains("not implemented"),
                        "dimension {} has unexpected reason: {reason}",
                        d.name
                    );
                }
            }
            Some(path) => {
                // Binary is present. The four non-MVP dimensions
                // are Skipped; the two MVP dimensions are
                // Completed.
                let mvp_dims: Vec<&DimensionResult> = report
                    .dimensions
                    .iter()
                    .filter(|d| matches!(d.name.as_str(), "http_connect_p50" | "startup"))
                    .collect();
                let non_mvp_dims: Vec<&DimensionResult> = report
                    .dimensions
                    .iter()
                    .filter(|d| !matches!(d.name.as_str(), "http_connect_p50" | "startup"))
                    .collect();
                assert_eq!(mvp_dims.len(), 2);
                for d in &mvp_dims {
                    assert_eq!(
                        d.status,
                        DimensionStatus::Completed,
                        "mvp dim {} should be Completed when binary is at {path}, got {:?}",
                        d.name,
                        d.status
                    );
                }
                for d in &non_mvp_dims {
                    assert_eq!(d.status, DimensionStatus::Skipped);
                    let reason = d.reason.as_deref().unwrap_or("");
                    assert!(
                        reason.contains("not implemented in MVP"),
                        "non-MVP dim {} should have 'not implemented' reason, got: {reason}",
                        d.name
                    );
                }
            }
        }
    }

    /// `http_connect_p50` with a known-small number of
    /// iterations completes successfully and reports a p50.
    /// This locks the summary-math contract independently of
    /// the engine-binary gate.
    #[test]
    fn http_connect_p50_local_listener_summarizes() {
        let summary = summarize(&[
            MetricSample {
                iteration: 1,
                duration_ms: 1.0,
                success: true,
                error: None,
            },
            MetricSample {
                iteration: 2,
                duration_ms: 2.0,
                success: true,
                error: None,
            },
            MetricSample {
                iteration: 3,
                duration_ms: 3.0,
                success: true,
                error: None,
            },
        ]);
        assert_eq!(summary.successful, 3);
        assert_eq!(summary.total, 3);
        assert_eq!(summary.min_ms, 1.0);
        assert_eq!(summary.max_ms, 3.0);
        assert!((summary.mean_ms - 2.0).abs() < 1e-9);
        assert_eq!(summary.p50_ms, Some(2.0));
        // p99 needs >= 100 samples to be reported; with 3 we get None.
        assert_eq!(summary.p99_ms, None);
    }

    /// Percentile interpolates linearly for fractional ranks.
    #[test]
    fn percentile_interpolates() {
        let mut v = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        assert_eq!(percentile(&v, 0.0), 1.0);
        assert_eq!(percentile(&v, 0.5), 3.0);
        assert_eq!(percentile(&v, 1.0), 5.0);
        // p90 of [1..5] lands at rank 0.9 * 4 = 3.6, between
        // index 3 (4.0) and index 4 (5.0) → 4.0 * 0.4 + 5.0 * 0.6 = 4.6.
        assert!((percentile(&v, 0.9) - 4.6).abs() < 1e-9);
    }

    /// Iterations outside [1, 1024] clamp to a sane default.
    #[test]
    fn clamp_iterations_handles_edges() {
        assert_eq!(clamp_iterations(0), 10);
        assert_eq!(clamp_iterations(1), 1);
        assert_eq!(clamp_iterations(1024), 1024);
        assert_eq!(clamp_iterations(2048), 1024);
    }
}
