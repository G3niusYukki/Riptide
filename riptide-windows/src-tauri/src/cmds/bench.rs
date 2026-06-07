//! Tauri commands for the Engine benchmark subsystem.
//!
//! Exposes a single command — `bench_run` — that the JS layer
//! invokes with a list of dimension names and an iteration
//! count. The command returns a fully-populated
//! [`crate::bench::BenchmarkReport`] as JSON; the JS layer is
//! expected to render the dimensions array as-is.
//!
//! MVP scope: see [`crate::bench`] for what the harness does
//! and what it returns. The C6 catchup plan documents the
//! full 5-dimension matrix; this command is the cross-platform
//! entry point that both the in-app "Run benchmark" button
//! and the CI workflow's `bench_run` invoke call.
//!
//! No state is held across calls — every invocation builds a
//! fresh harness run. Historical comparison / regression
//! detection is explicitly out of MVP scope (the catchup plan
//! defers that to a later phase).

use std::str::FromStr;

use crate::bench::{
    engine::EngineKind, harness::run_benchmark, report::BenchmarkReport, report::DimensionId,
};

/// `bench_run(engine?, dimensions?, iterations?) -> BenchmarkReport`
///
/// Arguments are all optional:
///
/// - `engine`: snake_case wire string (`"mihomo"` / `"singbox"` /
///   `"swift"`). Defaults to `"mihomo"`. The harness's first job
///   is to resolve the binary; an unknown engine name surfaces
///   as a `String` error to the JS layer.
/// - `dimensions`: list of snake_case dimension ids. Defaults
///   to all five (the three non-MVP ones are surfaced as
///   `Skipped` in the report). Unknown ids are rejected
///   up-front with `"unknown dimension: <name>"`.
/// - `iterations`: number of measurement iterations per
///   dimension. Clamped to `[1, 1024]`; `0` falls back to 10.
///
/// The command always returns `Result<BenchmarkReport, String>`.
/// "Engine binary missing" is a **normal** outcome, not an
/// error: the report's `engine_binary` is `None` and every
/// dimension is `Skipped` with a reason the UI / CI log can
/// surface verbatim.
#[tauri::command]
pub async fn bench_run(
    engine: Option<String>,
    dimensions: Option<Vec<String>>,
    iterations: Option<u32>,
) -> Result<BenchmarkReport, String> {
    let engine = parse_engine(engine)?;
    let dims = parse_dimensions(dimensions)?;
    // The harness is synchronous; we `spawn_blocking` so the
    // Tauri command does not block the runtime's worker pool
    // for the duration of the (small, MVP-scope) measurement.
    // Note: `tauri::async_runtime::spawn_blocking` is safe in
    // the production runtime; in `cargo test` the no-op spawn
    // (per the c6 team memory) means we'd fall back to a
    // direct call. The unit tests therefore exercise
    // `crate::bench::run_benchmark` directly, not this
    // command.
    let report = tauri::async_runtime::spawn_blocking(move || {
        run_benchmark(engine, dims.as_deref(), iterations.unwrap_or(10))
    })
    .await
    .map_err(|e| format!("bench runtime join error: {e}"))?;
    Ok(report)
}

fn parse_engine(s: Option<String>) -> Result<EngineKind, String> {
    match s {
        None => Ok(EngineKind::Mihomo),
        Some(s) if s.is_empty() => Ok(EngineKind::Mihomo),
        Some(s) => EngineKind::from_str(&s),
    }
}

fn parse_dimensions(
    s: Option<Vec<String>>,
) -> Result<Option<Vec<DimensionId>>, String> {
    let Some(list) = s else {
        return Ok(None);
    };
    if list.is_empty() {
        return Ok(None);
    }
    let mut out = Vec::with_capacity(list.len());
    for name in list {
        out.push(DimensionId::from_str(&name)?);
    }
    Ok(Some(out))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The Tauri-boundary parsers should treat `None` and
    /// empty strings as "use the default". The harness itself
    /// is exercised by `bench::harness::tests`; we only pin
    /// the parsing contract here.
    #[test]
    fn parse_engine_defaults_to_mihomo() {
        assert_eq!(parse_engine(None).unwrap(), EngineKind::Mihomo);
        assert_eq!(parse_engine(Some(String::new())).unwrap(), EngineKind::Mihomo);
        assert_eq!(parse_engine(Some("mihomo".into())).unwrap(), EngineKind::Mihomo);
        assert_eq!(parse_engine(Some("singbox".into())).unwrap(), EngineKind::Singbox);
        assert!(parse_engine(Some("nope".into())).is_err());
    }

    /// Dimensions parser: `None` / `Some(vec![])` → `Ok(None)`
    /// (caller runs all 5). `Some(vec!["..."])` →
    /// `Ok(Some(vec!))`. Unknown names fail loudly.
    #[test]
    fn parse_dimensions_handles_all_shapes() {
        assert!(parse_dimensions(None).unwrap().is_none());
        assert!(parse_dimensions(Some(vec![])).unwrap().is_none());
        let parsed = parse_dimensions(Some(vec![
            "http_connect_p50".into(),
            "startup".into(),
        ]))
        .unwrap()
        .unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0], DimensionId::HttpConnectP50);
        assert_eq!(parsed[1], DimensionId::Startup);
        // Unknown dimension is rejected with a useful error
        // so the JS layer can show a clear message.
        let err = parse_dimensions(Some(vec!["bogus".into()])).unwrap_err();
        assert!(err.contains("unknown dimension"), "got: {err}");
    }
}
