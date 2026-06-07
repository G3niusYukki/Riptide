// useTheme — 3-mode theme controller (system / light / dark).
//
// Mirrors the macOS `ThemeManager` (Sources/RiptideApp/App/ThemeManager.swift)
// at the MVP level: 3 mutually exclusive modes, system mode tracks the
// OS prefers-color-scheme and applies either dark or light, and the
// user-chosen mode persists across sessions via the riptide Zustand
// store (which already persists `theme` to localStorage under
// `riptide-storage`).
//
// The "active" theme is exposed as the `data-theme` attribute on
// `<html>`, which is the selector used by `src/styles/tokens.css` to
// switch the CSS custom property palette. This is the wiring that the
// previous version of this hook (and the App.tsx class-toggle path)
// got wrong: toggling `dark`/`light` classes on `<html>` had no
// effect because tokens.css keys off `[data-theme="..."]`, not
// `.dark` / `.light`. The 2026-06-07 C10.1 pass unifies both ends.

import { useCallback, useEffect, useState } from 'react';
import { useRiptideStore } from '../stores/riptide';

export type ThemeMode = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';

export interface UseThemeResult {
  /** User's chosen mode (one of system | light | dark). */
  theme: ThemeMode;
  /** The theme actually applied after resolving `system` against the OS preference. */
  resolvedTheme: ResolvedTheme;
  setTheme: (next: ThemeMode) => void;
}

const VALID_MODES: readonly ThemeMode[] = ['system', 'light', 'dark'];

function isValidMode(value: unknown): value is ThemeMode {
  return typeof value === 'string' && (VALID_MODES as readonly string[]).includes(value);
}

/** Read the system color-scheme preference. Guarded for non-browser test envs. */
function readSystemPrefersDark(): boolean {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
    return false;
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches;
}

function applyThemeAttribute(resolved: ResolvedTheme): void {
  if (typeof document === 'undefined') return;
  document.documentElement.setAttribute('data-theme', resolved);
}

/**
 * Hook used by App.tsx and the Settings → Appearance tab.
 *
 * - `theme` is the user preference ('system' | 'light' | 'dark').
 * - `resolvedTheme` is the value that is currently painted on
 *   `data-theme` (i.e. for 'system' mode, the OS preference resolved
 *   to 'light' or 'dark').
 * - `setTheme` updates the persisted store; the effect below keeps
 *   `data-theme` in sync.
 */
export function useTheme(): UseThemeResult {
  const storeTheme = useRiptideStore((s) => s.theme);
  const setStoreTheme = useRiptideStore((s) => s.setTheme);

  // Defensive: if the persisted value is not one of the 3 supported
  // modes (older version of the app stored 'nord' / 'dracula' / etc.),
  // coerce to 'system' so the UI never crashes on stale data.
  const theme: ThemeMode = isValidMode(storeTheme) ? storeTheme : 'system';

  const [systemPrefersDark, setSystemPrefersDark] = useState<boolean>(() => readSystemPrefersDark());

  // Subscribe to OS-level color scheme changes. Only relevant when the
  // user has chosen 'system', but we attach the listener once at
  // mount and let the resolvedTheme effect below decide what to do
  // with the value.
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') {
      return;
    }
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = (e: MediaQueryListEvent) => setSystemPrefersDark(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);

  const resolvedTheme: ResolvedTheme =
    theme === 'system' ? (systemPrefersDark ? 'dark' : 'light') : theme;

  // Apply the resolved theme to <html data-theme="...">. This is the
  // single source of truth for what users actually see.
  useEffect(() => {
    applyThemeAttribute(resolvedTheme);
  }, [resolvedTheme]);

  const setTheme = useCallback(
    (next: ThemeMode) => {
      setStoreTheme(next);
    },
    [setStoreTheme],
  );

  return { theme, resolvedTheme, setTheme };
}
