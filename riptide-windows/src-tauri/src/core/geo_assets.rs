//! GeoIP / GeoSite asset management.
//!
//! mihomo uses two binary databases for IP/site-based routing: `geoip.metadb`
//! (Mihomo Party's compact format) and `geosite.dat` (V2Fly's format). They
//! live in mihomo's working directory (`%APPDATA%\Riptide\` here) and mihomo
//! reads them on launch.
//!
//! This module:
//!   1. Knows where the files should live (relative to mihomo's working dir).
//!   2. Downloads them from upstream releases.
//!   3. Reports presence + last-modified time to the UI.
//!
//! No SHA pinning (yet) — these databases update daily and pinning hashes
//! would force a Riptide release every time a new geo dataset ships.

use std::fs;
use std::path::PathBuf;
use std::time::SystemTime;

use anyhow::Context;
use chrono::{DateTime, Utc};
use futures::StreamExt;
use serde::Serialize;
use tauri::{AppHandle, Emitter};

const GEOIP_URL: &str =
    "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb";
const GEOSITE_URL: &str =
    "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat";

const GEOIP_FILENAME: &str = "geoip.metadb";
const GEOSITE_FILENAME: &str = "geosite.dat";

#[derive(Clone, Serialize)]
pub struct GeoAsset {
    pub name: String,
    pub installed: bool,
    pub size_bytes: Option<u64>,
    pub last_modified: Option<DateTime<Utc>>,
}

#[derive(Clone, Serialize)]
pub struct GeoAssetProgress {
    pub asset: &'static str, // "geoip" | "geosite"
    pub downloaded_bytes: u64,
    pub total_bytes: Option<u64>,
    pub done: bool,
}

fn geoip_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    Ok(crate::utils::dirs::get_app_data_dir(app_handle)?.join(GEOIP_FILENAME))
}

fn geosite_path(app_handle: &AppHandle) -> anyhow::Result<PathBuf> {
    Ok(crate::utils::dirs::get_app_data_dir(app_handle)?.join(GEOSITE_FILENAME))
}

fn describe(path: &PathBuf, name: &str) -> GeoAsset {
    let meta = fs::metadata(path).ok();
    let size_bytes = meta.as_ref().map(|m| m.len());
    let last_modified = meta
        .and_then(|m| m.modified().ok())
        .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .and_then(|d| DateTime::from_timestamp(d.as_secs() as i64, 0));
    GeoAsset {
        name: name.to_string(),
        installed: path.exists(),
        size_bytes,
        last_modified,
    }
}

#[tauri::command]
pub async fn get_geo_assets(app_handle: AppHandle) -> Result<Vec<GeoAsset>, String> {
    let geoip = geoip_path(&app_handle).map_err(|e| e.to_string())?;
    let geosite = geosite_path(&app_handle).map_err(|e| e.to_string())?;
    Ok(vec![
        describe(&geoip, "geoip"),
        describe(&geosite, "geosite"),
    ])
}

/// Download (or re-download) both databases. Each is downloaded to a `.tmp`
/// sibling first, then atomically renamed — so a mid-flight failure doesn't
/// corrupt an existing copy.
#[tauri::command]
pub async fn download_geo_assets(app_handle: AppHandle) -> Result<(), String> {
    let geoip = geoip_path(&app_handle).map_err(|e| e.to_string())?;
    let geosite = geosite_path(&app_handle).map_err(|e| e.to_string())?;

    download_one(&app_handle, "geoip", GEOIP_URL, &geoip)
        .await
        .map_err(|e| format!("Failed to download GeoIP: {}", e))?;
    download_one(&app_handle, "geosite", GEOSITE_URL, &geosite)
        .await
        .map_err(|e| format!("Failed to download GeoSite: {}", e))?;

    log::info!("GeoIP/GeoSite assets refreshed");
    Ok(())
}

async fn download_one(
    app_handle: &AppHandle,
    asset_name: &'static str,
    url: &str,
    target: &PathBuf,
) -> anyhow::Result<()> {
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }

    let response = reqwest::Client::builder()
        .user_agent(concat!("riptide-windows/", env!("CARGO_PKG_VERSION")))
        .build()?
        .get(url)
        .send()
        .await
        .with_context(|| format!("GET {}", url))?
        .error_for_status()?;

    let total = response.content_length();
    let tmp = target.with_extension(format!(
        "{}.download",
        target.extension().and_then(|s| s.to_str()).unwrap_or("bin")
    ));
    let mut file = fs::File::create(&tmp)?;
    let mut downloaded: u64 = 0;
    let mut stream = response.bytes_stream();
    let mut last_emit = std::time::Instant::now();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        use std::io::Write;
        file.write_all(&chunk)?;
        downloaded += chunk.len() as u64;
        if last_emit.elapsed() > std::time::Duration::from_millis(150) {
            let _ = app_handle.emit(
                "geo_asset_progress",
                GeoAssetProgress {
                    asset: asset_name,
                    downloaded_bytes: downloaded,
                    total_bytes: total,
                    done: false,
                },
            );
            last_emit = std::time::Instant::now();
        }
    }
    drop(file);
    fs::rename(&tmp, target)?;

    let _ = app_handle.emit(
        "geo_asset_progress",
        GeoAssetProgress {
            asset: asset_name,
            downloaded_bytes: downloaded,
            total_bytes: total,
            done: true,
        },
    );
    Ok(())
}

/// If neither asset is installed, kick off a background download. Called at
/// startup so a fresh install picks them up without a manual button press.
pub fn ensure_present_async(app_handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let assets = match get_geo_assets(app_handle.clone()).await {
            Ok(a) => a,
            Err(e) => {
                log::warn!("Failed to inspect geo assets: {}", e);
                return;
            }
        };
        if assets.iter().all(|a| a.installed) {
            return;
        }
        log::info!("Geo assets missing — starting background download");
        if let Err(e) = download_geo_assets(app_handle).await {
            log::warn!("Background geo asset download failed: {}", e);
        }
    });
}
