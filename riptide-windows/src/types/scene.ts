// Scene editor type definitions for the Windows frontend.
//
// Mirrors `riptide-windows/src-tauri/src/core/scenes/types.rs` on
// the Rust side: snake_case fields, a discriminated `Matcher` union
// keyed on `kind`, and a `ModeOverride` enum that is wire-string
// identical to the Rust enum's serde representation.

/** Stable identifier — UUID v4 minted by the Rust backend. */
export type SceneId = string;

/**
 * Which proxy mode a connection should use when a scene's matchers
 * fire. Wire string is the snake_case form so the JS layer can
 * compare it directly against the option labels.
 */
export type ModeOverride = 'off' | 'system_proxy' | 'tun' | 'direct';

/** Human-readable label for the `ModeOverride` enum (zh-CN). */
export const MODE_OVERRIDE_LABEL: Record<ModeOverride, string> = {
  off: '关闭',
  system_proxy: '系统代理',
  tun: 'TUN 模式',
  direct: '直连',
};

/**
 * One match clause. A scene holds a list of these; any match firing
 * (logical OR) is enough to apply the scene's mode override.
 */
export type Matcher =
  | { kind: 'process'; pattern: string }
  | { kind: 'domain'; pattern: string }
  | { kind: 'ipset'; value: string };

/** Short, stable kind tag — useful for the list view's badges. */
export type MatcherKind = 'process' | 'domain' | 'ipset';

export const MATCHER_KIND_LABEL: Record<MatcherKind, string> = {
  process: '进程',
  domain: '域名',
  ipset: 'IP 集',
};

export function matcherKind(m: Matcher): MatcherKind {
  return m.kind;
}

/** A persisted user scene. */
export interface Scene {
  id: SceneId;
  name: string;
  mode: ModeOverride;
  enabled: boolean;
  matchers: Matcher[];
  /** ISO 8601 timestamp. Backend mints on create; updated on update. */
  created_at: string;
  /** ISO 8601 timestamp. */
  updated_at: string;
}

/**
 * Trimmed view of a scene returned by `scene_list` (the list view's
 * data source). The full `Scene` is only fetched by the editor.
 */
export interface SceneSummary {
  id: SceneId;
  name: string;
  mode: ModeOverride;
  enabled: boolean;
  matcher_count: number;
  /** "process + domain" / "ipset" / "process" / etc. */
  matcher_kinds: string;
}

/** Outcome of `sceneApply`. Mirrors the Rust `SceneApplyResult`. */
export interface SceneApplyResult {
  matched: SceneId | null;
  mode: ModeOverride | null;
  scene_name: string | null;
}
