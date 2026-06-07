//! WebDAV backup + restore.
//!
//! Backup is a single zip uploaded to `<endpoint>/<remote_path>`. Restore
//! downloads and extracts back over the local app data (profiles, active.json,
//! dns_policy.json). DPAPI encrypts the password on disk; we never log it.
//!
//! Auth: HTTP Basic over HTTPS only. We refuse plain-HTTP endpoints because
//! Basic auth without TLS is a credential leak.

use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context};
use base64::{engine::general_purpose, Engine as _};
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION};
use serde::{Deserialize, Serialize};

use crate::utils::windows_dirs::WindowsDirs;

const WEBDAV_CONFIG_FILENAME: &str = "webdav_config.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebDAVConfig {
    pub endpoint: String, // e.g. https://dav.example.com/Riptide/
    pub username: String,
    /// Hex-encoded DPAPI ciphertext of the password. Stored as a string for
    /// JSON friendliness; decoded just-in-time when we make a request.
    #[serde(default)]
    pub password_cipher_hex: String,
    /// Remote path of the backup blob relative to `endpoint`.
    #[serde(default = "default_remote_path")]
    pub remote_path: String,
    #[serde(default)]
    pub enabled: bool,
}

fn default_remote_path() -> String {
    "riptide-backup.zip".to_string()
}

impl Default for WebDAVConfig {
    fn default() -> Self {
        Self {
            endpoint: String::new(),
            username: String::new(),
            password_cipher_hex: String::new(),
            remote_path: default_remote_path(),
            enabled: false,
        }
    }
}

fn config_path() -> PathBuf {
    WindowsDirs::config_dir().join(WEBDAV_CONFIG_FILENAME)
}

pub fn load_config() -> WebDAVConfig {
    let path = config_path();
    let Ok(contents) = std::fs::read_to_string(&path) else {
        return WebDAVConfig::default();
    };
    serde_json::from_str(&contents).unwrap_or_else(|e| {
        log::warn!("Ignoring corrupt webdav_config.json: {}", e);
        WebDAVConfig::default()
    })
}

pub fn save_config(cfg: &WebDAVConfig) -> Result<(), String> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(cfg).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, json).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
    Ok(())
}

/// Encrypt the user-supplied password and update the config struct in-place.
/// Returns Ok with an empty ciphertext if `password` is empty (signals "no change").
pub fn set_password(cfg: &mut WebDAVConfig, password: &str) -> Result<(), String> {
    if password.is_empty() {
        return Ok(());
    }
    let ct = crate::core::secrets::encrypt(password.as_bytes()).map_err(|e| e.to_string())?;
    cfg.password_cipher_hex = hex_encode(&ct);
    Ok(())
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

fn hex_decode(s: &str) -> anyhow::Result<Vec<u8>> {
    if s.len() % 2 != 0 {
        return Err(anyhow!("hex string has odd length"));
    }
    (0..s.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&s[i..i + 2], 16).map_err(|e| anyhow!("invalid hex byte: {}", e))
        })
        .collect()
}

fn build_auth(cfg: &WebDAVConfig) -> anyhow::Result<HeaderValue> {
    let pw_bytes = if cfg.password_cipher_hex.is_empty() {
        Vec::new()
    } else {
        let ct = hex_decode(&cfg.password_cipher_hex)?;
        crate::core::secrets::decrypt(&ct).context("DPAPI decrypt")?
    };
    let pw = std::str::from_utf8(&pw_bytes).context("password is not valid UTF-8")?;
    let token = general_purpose::STANDARD.encode(format!("{}:{}", cfg.username, pw));
    Ok(HeaderValue::from_str(&format!("Basic {}", token))?)
}

fn build_client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(concat!("riptide-windows/", env!("CARGO_PKG_VERSION")))
        .build()
        .expect("reqwest client build")
}

fn endpoint_url(cfg: &WebDAVConfig) -> anyhow::Result<reqwest::Url> {
    let trimmed = cfg.endpoint.trim_end_matches('/');
    let combined = format!("{}/{}", trimmed, cfg.remote_path.trim_start_matches('/'));
    let url = reqwest::Url::parse(&combined).context("parse endpoint URL")?;
    if url.scheme() != "https" {
        return Err(anyhow!(
            "WebDAV endpoint must use https:// (got {})",
            url.scheme()
        ));
    }
    Ok(url)
}

pub async fn test_connection(cfg: &WebDAVConfig) -> anyhow::Result<()> {
    let mut url = endpoint_url(cfg)?;
    // PROPFIND on the parent directory — that's the standard "are you a WebDAV
    // server with these credentials" probe.
    let parent_path = {
        let path = url.path().to_string();
        path.rsplit_once('/')
            .map(|(p, _)| p.to_string())
            .unwrap_or_else(|| "/".to_string())
    };
    url.set_path(&parent_path);
    let mut headers = HeaderMap::new();
    headers.insert(AUTHORIZATION, build_auth(cfg)?);
    headers.insert("Depth", HeaderValue::from_static("0"));

    let response = build_client()
        .request(reqwest::Method::from_bytes(b"PROPFIND")?, url)
        .headers(headers)
        .body("<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:allprop/></d:propfind>")
        .send()
        .await?;

    // 207 Multi-Status is the success case; 200/201 are also acceptable.
    let status = response.status();
    if status.is_success() || status.as_u16() == 207 {
        Ok(())
    } else {
        Err(anyhow!("WebDAV PROPFIND failed: HTTP {}", status))
    }
}

pub async fn upload_backup(cfg: &WebDAVConfig, zip_bytes: Vec<u8>) -> anyhow::Result<()> {
    let url = endpoint_url(cfg)?;
    let mut headers = HeaderMap::new();
    headers.insert(AUTHORIZATION, build_auth(cfg)?);

    let response = build_client()
        .put(url)
        .headers(headers)
        .body(zip_bytes)
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(anyhow!("WebDAV PUT failed: HTTP {}", response.status()));
    }
    Ok(())
}

pub async fn download_backup(cfg: &WebDAVConfig) -> anyhow::Result<Vec<u8>> {
    let url = endpoint_url(cfg)?;
    let mut headers = HeaderMap::new();
    headers.insert(AUTHORIZATION, build_auth(cfg)?);

    let response = build_client().get(url).headers(headers).send().await?;
    if !response.status().is_success() {
        return Err(anyhow!("WebDAV GET failed: HTTP {}", response.status()));
    }
    Ok(response.bytes().await?.to_vec())
}

/// Build the backup zip in memory. Includes every YAML/meta in the profiles
/// dir, `active.json`, and `dns_policy.json`.
pub fn build_backup_zip() -> anyhow::Result<Vec<u8>> {
    let mut cursor = std::io::Cursor::new(Vec::new());
    let mut zip = zip::ZipWriter::new(&mut cursor);
    let options: zip::write::FileOptions<'_, ()> =
        zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    let config_dir = WindowsDirs::config_dir();
    let profiles_dir = WindowsDirs::profiles_dir();

    if profiles_dir.exists() {
        for entry in std::fs::read_dir(&profiles_dir)? {
            let entry = entry?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            add_file_to_zip(
                &mut zip,
                &path,
                &format!("profiles/{}", entry.file_name().to_string_lossy()),
                options,
            )?;
        }
    }

    for sidecar in ["active.json", "dns_policy.json"] {
        let p = config_dir.join(sidecar);
        if p.exists() {
            add_file_to_zip(&mut zip, &p, sidecar, options)?;
        }
    }

    zip.finish()?;
    Ok(cursor.into_inner())
}

fn add_file_to_zip<W: Write + Seek>(
    zip: &mut zip::ZipWriter<W>,
    path: &Path,
    archive_path: &str,
    options: zip::write::FileOptions<'_, ()>,
) -> anyhow::Result<()> {
    zip.start_file(archive_path, options)?;
    let mut file = std::fs::File::open(path)?;
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        zip.write_all(&buffer[..n])?;
    }
    Ok(())
}

/// Extract a backup zip over the local app data directories. Existing files
/// are overwritten — this is intentional: WebDAV restore is "make my state
/// look like the cloud's." Caller should warn the user before invoking.
pub fn extract_backup_zip(zip_bytes: &[u8]) -> anyhow::Result<()> {
    let mut cursor = std::io::Cursor::new(zip_bytes);
    cursor.seek(SeekFrom::Start(0))?;
    let mut archive = zip::ZipArchive::new(cursor)?;

    let config_dir = WindowsDirs::config_dir();
    WindowsDirs::ensure_dirs()?;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let name = entry.name().to_string();
        if name.contains("..") {
            // Zip-slip defense — refuse traversal.
            log::warn!("Skipping suspicious zip entry: {}", name);
            continue;
        }
        let target = config_dir.join(&name);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut out = std::fs::File::create(&target)?;
        std::io::copy(&mut entry, &mut out)?;
    }
    Ok(())
}
