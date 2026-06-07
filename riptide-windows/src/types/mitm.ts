// MITM (HTTPS interception) type definitions.
//
// Wire format mirrors the future Rust `mitm` module scheduled for
// Phase D (v2.5.0). The shapes here are stable; the field names follow
// the snake_case convention used by `services/tauri.ts` for IPC
// payloads. None of the 5 invoke wrappers in `services/tauri.ts` are
// implemented on the backend yet — calling them rejects with
// `not_implemented` (mocked at the Tauri boundary until the Rust
// side ships).

/** Global MITM configuration — toggle + host lists.
 *  Mirrors the macOS `MITMConfig` value type in
 *  `Sources/Riptide/MITM/MITMConfig.swift`. */
export interface MITMConfig {
  /** Master switch — when false, interception is bypassed entirely. */
  enabled: boolean;
  /** Host patterns to intercept. Supports `*.example.com` wildcards. */
  hosts: string[];
  /** Hosts to explicitly exclude even when matched by `hosts`. */
  exclude_hosts: string[];
}

/** CA root certificate state. The CA is generated on first enable and
 *  must be installed in the system trust store before interception
 *  can succeed (and even then, browsers display a warning). */
export interface CAState {
  /** Whether the CA cert is currently installed in the trust store. */
  installed: boolean;
  /** SHA-256 fingerprint of the CA cert, hex-encoded, lowercase,
   *  colon-separated groups (e.g. "ab:cd:..."). Empty when not yet
   *  generated. */
  fingerprint: string;
  /** ISO 8601 expiry timestamp. The cert is self-signed and typically
   *  valid for 10 years. */
  expires_at?: string | null;
  /** Absolute path to the `.crt` file on disk, if generated. */
  cert_path?: string | null;
}

/** Per-host rule with its own enable flag. The flat list on
 *  `MITMConfig.hosts` is the legacy representation; the table UI in
 *  `MITMTab` uses this richer shape so individual rows can be
 *  toggled without rewriting the whole config. */
export interface HostRule {
  /** Stable identifier (UUID v4 string). */
  id: string;
  /** Host pattern, e.g. `api.example.com` or `*.example.com`. */
  pattern: string;
  /** Whether this rule is currently active. */
  enabled: boolean;
  /** ISO 8601 created-at timestamp. */
  created_at: string;
  /** Optional human-readable note (e.g. "production API"). */
  note?: string;
}
