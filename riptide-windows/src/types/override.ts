// Override type definitions for the Windows frontend.
//
// Mirrors `Sources/Riptide/Override/Override.swift` on macOS: an Override
// is a partial YAML that overlays on top of an active profile. The Rust
// backend (Phase C2 follow-up task) will own the file-backed store; the
// shape here is the wire contract between the React UI and the Tauri
// command handlers (`list_overrides`, `create_override`,
// `update_override`, `delete_override`, `apply_override`,
// `preview_override`).

/** Stable identifier — UUID v4, generated on the Rust side. */
export type OverrideId = string;

/** A persisted user override: partial YAML + metadata. */
export interface Override {
  id: OverrideId;
  name: string;
  /** Raw YAML; preserved verbatim (comments + key order) for git-friendliness. */
  rawYAML: string;
  /** ISO 8601 timestamp. */
  createdAt: string;
  /** ISO 8601 timestamp. */
  updatedAt: string;
}

/** Outcome of `previewOverride` / `applyOverride`. */
export interface ApplyResult {
  /** The merged YAML after applying the override. */
  mergedYAML: string;
  /**
   * Sections the override actually touched, e.g. `["proxies", "proxy-groups"]`.
   * Empty array means the override was a no-op (trimmed empty or pure meta).
   */
  touched: string[];
  /**
   * Names removed via the `removed:` directive, surfaced back to the UI
   * for confirmation. Empty when no removals were requested.
   */
  removed: string[];
}

/**
 * Marker for the override section that controls merge behavior.
 * Mirrors the macOS OverrideMerger `meta.replace` semantics.
 */
export interface OverrideMeta {
  /** When true, list-sections merge by `name` (replace) instead of append. */
  replace?: boolean;
}

/**
 * Convenience type for the editor's parse output. The YAML is always
 * stored as a string; `meta` is exposed as a separate field for the
 * summary header so the editor doesn't have to re-parse.
 */
export interface OverrideDraft {
  name: string;
  rawYAML: string;
  meta: OverrideMeta;
}
