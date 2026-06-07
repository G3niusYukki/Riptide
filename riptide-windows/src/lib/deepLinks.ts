// riptide:// deep link parser + dispatcher.
//
// The Windows app registers a custom URL scheme (`riptide://`) via the
// Tauri deep-link plugin. The plugin hands us the raw URL — this
// module converts it into a structured command, then performs the
// side effects (navigate / Tauri IPC / mode switch).
//
// Recognised shapes (v2.4.1, C4.1-3):
//   riptide://import?url=<subscription_url>
//   riptide://import?uri=<share_uri>
//   riptide://switch-group?group=<name>
//   riptide://select-node?group=<name>&node=<name>
//   riptide://mode?value=<off|system_proxy|tun>
//   riptide://diagnostics
//   riptide://open-config
//
// Anything else is reported as `{type: 'noop', reason: ...}` — the
// dispatcher does nothing in that case. This module never throws; the
// call sites in App.tsx treat the noop branch as a logged warning.

/** Mode values accepted by `riptide://mode?value=...`. */
export const VALID_MODES = ['off', 'system_proxy', 'tun'] as const;
export type ValidMode = (typeof VALID_MODES)[number];

/** Discriminated union over the 6 deep-link actions + the noop fallback. */
export type ParsedDeepLink =
  | { type: 'noop'; reason: string }
  | { type: 'import-profile-from-url'; url: string }
  | { type: 'import-share-uri'; uri: string }
  | { type: 'switch-group'; group: string }
  | { type: 'select-node'; group: string; node: string }
  | { type: 'mode'; value: ValidMode }
  | { type: 'diagnostics' }
  | { type: 'open-config' };

/**
 * Dependencies required to execute a parsed deep link. All fields are
 * injected so the dispatcher is fully unit-testable — the production
 * wiring in App.tsx pulls them from `react-router-dom` and
 * `services/tauri`, while the test suite passes mocks.
 */
export interface DeepLinkDispatchDeps {
  /** React Router's `navigate` function. The dispatcher only ever
   *  forwards string paths so any compatible router works. */
  navigate: (path: string) => void;
  /** Import a subscription profile by URL. Mirrors `tauri.importProfileFromUrl`. */
  importProfileFromUrl: (url: string) => Promise<unknown>;
  /** Import a single share URI. Mirrors `tauri.importShareUri`. */
  importShareUri: (uri: string) => Promise<unknown>;
  /** Switch mode coordinator to OFF. */
  modeSwitchOff: () => Promise<void>;
  /** Switch mode coordinator to system-proxy. */
  modeSwitchToSystemProxy: (httpPort?: number, socksPort?: number) => Promise<void>;
  /** Switch mode coordinator to TUN. */
  modeSwitchToTun: () => Promise<void>;
  /** Default alert impl. Override in tests to silence output. */
  alert?: (message: string) => void;
}

/**
 * Parse a `riptide://...` URL into a structured command. Returns
 * `{type: 'noop', reason: '...'}` for malformed input, wrong protocol,
 * unknown actions, missing required params, or invalid mode values.
 * Never throws.
 */
export function parseDeepLink(rawUrl: string): ParsedDeepLink {
  if (typeof rawUrl !== 'string' || rawUrl.length === 0) {
    return { type: 'noop', reason: 'empty or non-string url' };
  }

  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return { type: 'noop', reason: 'malformed url' };
  }

  if (url.protocol !== 'riptide:') {
    return { type: 'noop', reason: `wrong protocol: ${url.protocol}` };
  }

  // riptide://<action>?...  -> action in `host`
  // riptide:<action>?...     -> action in `pathname` (no `//`)
  const action = (url.host || url.pathname.replace(/^\/*/, '') || '').trim();
  if (!action) {
    return { type: 'noop', reason: 'missing action' };
  }

  switch (action) {
    case 'import': {
      const subUrl = url.searchParams.get('url');
      const shareUri = url.searchParams.get('uri');
      if (subUrl) return { type: 'import-profile-from-url', url: subUrl };
      if (shareUri) return { type: 'import-share-uri', uri: shareUri };
      return { type: 'noop', reason: 'import: missing url= or uri=' };
    }
    case 'switch-group': {
      const group = url.searchParams.get('group');
      if (!group) return { type: 'noop', reason: 'switch-group: missing group=' };
      return { type: 'switch-group', group };
    }
    case 'select-node': {
      const group = url.searchParams.get('group');
      const node = url.searchParams.get('node');
      if (!group || !node) {
        return { type: 'noop', reason: 'select-node: missing group= or node=' };
      }
      return { type: 'select-node', group, node };
    }
    case 'mode': {
      const value = url.searchParams.get('value');
      if (value && (VALID_MODES as readonly string[]).includes(value)) {
        return { type: 'mode', value: value as ValidMode };
      }
      return { type: 'noop', reason: `mode: invalid value=${value ?? ''}` };
    }
    case 'diagnostics':
      return { type: 'diagnostics' };
    case 'open-config':
      return { type: 'open-config' };
    default:
      return { type: 'noop', reason: `unknown action: ${action}` };
  }
}

/**
 * Execute the side effects of a parsed deep link. Returns `true` if the
 * command was actioned, `false` if it was a no-op. Never throws — import
 * and mode failures are surfaced through `deps.alert` and
 * `console.warn` so that one malformed link can never take the app
 * down.
 */
export async function dispatchDeepLink(
  cmd: ParsedDeepLink,
  deps: DeepLinkDispatchDeps,
): Promise<boolean> {
  if (typeof window !== 'undefined') {
    // Keep the test environment quiet when no alert is supplied.
  }
  const alert = deps.alert ?? ((m: string) => window.alert(m));

  switch (cmd.type) {
    case 'noop':
      return false;

    case 'import-profile-from-url':
      try {
        const profile = (await deps.importProfileFromUrl(cmd.url)) as
          | { name?: string }
          | null
          | undefined;
        alert(`已通过 deep link 导入订阅：${profile?.name ?? cmd.url}`);
      } catch (e) {
        alert(`Deep link 导入失败：${e}`);
      }
      return true;

    case 'import-share-uri':
      try {
        const profile = (await deps.importShareUri(cmd.uri)) as
          | { name?: string }
          | null
          | undefined;
        alert(`已通过 deep link 导入节点：${profile?.name ?? cmd.uri}`);
      } catch (e) {
        alert(`Deep link 导入失败：${e}`);
      }
      return true;

    case 'switch-group':
      deps.navigate(`/proxies?group=${encodeURIComponent(cmd.group)}`);
      return true;

    case 'select-node':
      deps.navigate(
        `/proxies?group=${encodeURIComponent(cmd.group)}&node=${encodeURIComponent(cmd.node)}`,
      );
      return true;

    case 'mode':
      try {
        if (cmd.value === 'off') {
          await deps.modeSwitchOff();
        } else if (cmd.value === 'system_proxy') {
          await deps.modeSwitchToSystemProxy(7890, 7891);
        } else {
          await deps.modeSwitchToTun();
        }
      } catch (e) {
        console.warn(`Deep link mode switch failed (${cmd.value}):`, e);
      }
      return true;

    case 'diagnostics':
      deps.navigate('/logbook');
      return true;

    case 'open-config':
      deps.navigate('/profiles?import=1');
      return true;
  }
}

/**
 * Convenience: parse + dispatch in one call. Equivalent to
 * `dispatchDeepLink(parseDeepLink(rawUrl), deps)`. Returns whether the
 * link was actioned.
 */
export async function handleDeepLink(
  rawUrl: string,
  deps: DeepLinkDispatchDeps,
): Promise<boolean> {
  return dispatchDeepLink(parseDeepLink(rawUrl), deps);
}
