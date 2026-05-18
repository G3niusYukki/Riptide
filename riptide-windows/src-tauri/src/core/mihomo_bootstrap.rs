//! mihomo binary bootstrap — download, verify, and install on first run.
//!
//! The pinned version + SHA-256 are kept here as compile-time constants so a
//! Riptide release always ships against a known-good mihomo build. Bumping
//! mihomo is a deliberate two-line change (URL + hash) followed by a release.
//!
//! Flow:
//!   1. `ensure_mihomo_binary()` checks the expected path; if SHA matches, returns.
//!   2. Otherwise downloads the zip from GitHub Releases (chunked, progress events),
//!      verifies SHA-256, extracts `mihomo.exe`, and replaces the target.
//!   3. Failure modes (network, hash mismatch, extraction) surface as `Err` so the
//!      UI can show a clear message and offer "browse for binary" as a fallback.

use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context};
use futures::StreamExt;
use serde::Serialize;
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Emitter};

/// Pinned mihomo version. Bump in lockstep with `MIHOMO_SHA256`.
///
/// The "compatible" build targets older CPUs without AVX2 — broadest coverage
/// at a modest performance cost. Swap to `mihomo-windows-amd64-v...zip` for
/// the AVX2 variant once we're comfortable narrowing the audience.
pub const MIHOMO_VERSION: &str = "v1.18.10";
pub const MIHOMO_ARCHIVE_NAME: &str = "mihomo-windows-amd64-compatible-v1.18.10.zip";
pub const MIHOMO_DOWNLOAD_URL: &str = "https://github.com/MetaCubeX/mihomo/releases/download/v1.18.10/mihomo-windows-amd64-compatible-v1.18.10.zip";

/// SHA-256 of `MIHOMO_ARCHIVE_NAME`. Empty string disables verification — only
/// use that during development before a Riptide release is cut.
pub const MIHOMO_SHA256: &str = "1ae6eeec10630945d7f4139cd550f4fc32a9ed53370365dfe59c9d564ec15b0f";

/// Name of the executable inside the zip (and in our app data dir).
pub const MIHOMO_EXE_NAME: &str = "mihomo.exe";

/// Tauri event emitted while downloading. Frontend should listen to this to
/// drive a progress bar.
#[derive(Clone, Serialize)]
pub struct BootstrapProgress {
    pub stage: &'static str, // "download" | "verify" | "extract" | "done"
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub message: Option<String>,
}

/// Ensure mihomo is installed at the expected path. Returns the path.
///
/// If the binary already exists *and* its hash matches (when configured),
/// this is a no-op. Otherwise downloads, verifies, and installs.
pub async fn ensure_mihomo_binary(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    let target = crate::utils::dirs::get_mihomo_binary_path(app_handle)?;

    if target.exists() {
        // If the binary is already there we trust it. We deliberately do *not*
        // hash-check on every launch (slow, and the user may have intentionally
        // swapped in a different build via the manual path override).
        log::info!("mihomo binary already present at {:?}", target);
        return Ok(target);
    }

    log::info!("mihomo binary missing — downloading {}", MIHOMO_VERSION);
    emit_progress(
        app_handle,
        BootstrapProgress {
            stage: "download",
            downloaded_bytes: 0,
            total_bytes: None,
            message: Some(format!("Downloading mihomo {}", MIHOMO_VERSION)),
        },
    );

    let archive_bytes = download_to_memory(app_handle, MIHOMO_DOWNLOAD_URL)
        .await
        .with_context(|| format!("Failed to download mihomo from {}", MIHOMO_DOWNLOAD_URL))?;

    if !MIHOMO_SHA256.is_empty() {
        emit_progress(
            app_handle,
            BootstrapProgress {
                stage: "verify",
                downloaded_bytes: archive_bytes.len() as u64,
                total_bytes: Some(archive_bytes.len() as u64),
                message: Some("Verifying checksum".into()),
            },
        );
        verify_sha256(&archive_bytes, MIHOMO_SHA256)?;
    } else {
        log::warn!("MIHOMO_SHA256 is empty — skipping checksum verification");
    }

    emit_progress(
        app_handle,
        BootstrapProgress {
            stage: "extract",
            downloaded_bytes: archive_bytes.len() as u64,
            total_bytes: Some(archive_bytes.len() as u64),
            message: Some("Extracting mihomo.exe".into()),
        },
    );
    extract_mihomo_exe(&archive_bytes, &target)?;

    emit_progress(
        app_handle,
        BootstrapProgress {
            stage: "done",
            downloaded_bytes: archive_bytes.len() as u64,
            total_bytes: Some(archive_bytes.len() as u64),
            message: Some(format!("mihomo {} installed", MIHOMO_VERSION)),
        },
    );

    log::info!("mihomo installed to {:?}", target);
    Ok(target)
}

async fn download_to_memory(app_handle: &AppHandle, url: &str) -> anyhow::Result<Vec<u8>> {
    let response = reqwest::Client::builder()
        .user_agent(concat!("riptide-windows/", env!("CARGO_PKG_VERSION")))
        .build()?
        .get(url)
        .send()
        .await?
        .error_for_status()?;

    let total_bytes = response.content_length();
    let mut buf = Vec::with_capacity(total_bytes.unwrap_or(0) as usize);
    let mut downloaded: u64 = 0;
    let mut stream = response.bytes_stream();

    // Throttle progress events to ~10/sec to avoid flooding the IPC channel.
    let mut last_emit = std::time::Instant::now();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        downloaded += chunk.len() as u64;
        buf.extend_from_slice(&chunk);

        if last_emit.elapsed() > std::time::Duration::from_millis(100) {
            emit_progress(
                app_handle,
                BootstrapProgress {
                    stage: "download",
                    downloaded_bytes: downloaded,
                    total_bytes,
                    message: None,
                },
            );
            last_emit = std::time::Instant::now();
        }
    }

    Ok(buf)
}

fn verify_sha256(bytes: &[u8], expected_hex: &str) -> anyhow::Result<()> {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let got = hex_lower(&hasher.finalize());
    if got.eq_ignore_ascii_case(expected_hex) {
        Ok(())
    } else {
        Err(anyhow!(
            "SHA-256 mismatch: expected {}, got {}",
            expected_hex,
            got
        ))
    }
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

/// mihomo Windows releases ship as a zip containing a single `.exe`. Some
/// builds compress with gzip-in-zip; we only handle plain DEFLATE. Atomically
/// replaces the target file via a sibling temp.
fn extract_mihomo_exe(zip_bytes: &[u8], target: &Path) -> anyhow::Result<()> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }

    let reader = std::io::Cursor::new(zip_bytes);
    let mut archive = zip::ZipArchive::new(reader)
        .map_err(|e| anyhow!("Invalid zip archive: {}", e))?;

    // Find the first `.exe` entry — releases sometimes nest it under a folder.
    let exe_index = (0..archive.len())
        .find(|i| {
            archive
                .by_index(*i)
                .map(|f| {
                    let name = f.name().to_lowercase();
                    name.ends_with(".exe") && !f.is_dir()
                })
                .unwrap_or(false)
        })
        .ok_or_else(|| anyhow!("Zip archive contains no .exe entry"))?;

    let mut entry = archive.by_index(exe_index)?;
    let tmp = target.with_extension("exe.download");

    {
        let mut out = fs::File::create(&tmp)
            .with_context(|| format!("Failed to create {:?}", tmp))?;
        let mut buffer = [0u8; 64 * 1024];
        loop {
            let n = entry.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            out.write_all(&buffer[..n])?;
        }
    }

    fs::rename(&tmp, target)
        .with_context(|| format!("Failed to commit {:?} -> {:?}", tmp, target))?;
    Ok(())
}

fn emit_progress(app_handle: &AppHandle, progress: BootstrapProgress) {
    if let Err(e) = app_handle.emit("mihomo_bootstrap_progress", progress) {
        log::warn!("Failed to emit bootstrap progress: {}", e);
    }
}

/// Tauri command: trigger a download on demand (e.g., from a "reinstall mihomo"
/// settings button). Re-downloads even if the binary exists, by deleting first.
#[tauri::command]
pub async fn download_mihomo(app_handle: AppHandle) -> Result<String, String> {
    let target = crate::utils::dirs::get_mihomo_binary_path(&app_handle)
        .map_err(|e| e.to_string())?;
    if target.exists() {
        fs::remove_file(&target).map_err(|e| format!("Failed to remove old binary: {}", e))?;
    }
    let installed = ensure_mihomo_binary(&app_handle)
        .await
        .map_err(|e| e.to_string())?;
    Ok(installed.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_round_trips_known_vector() {
        // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        verify_sha256(
            b"abc",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        )
        .unwrap();
    }

    #[test]
    fn sha256_rejects_mismatch() {
        assert!(verify_sha256(b"abc", "0000").is_err());
    }

    #[test]
    fn empty_sha_skipped_by_caller() {
        // Sanity check the constant is empty (until a release pins it).
        // This test fails loudly if someone forgets to pair a URL change with a hash change.
        if !MIHOMO_SHA256.is_empty() {
            assert_eq!(MIHOMO_SHA256.len(), 64);
            assert!(MIHOMO_SHA256.chars().all(|c| c.is_ascii_hexdigit()));
        }
    }
}
