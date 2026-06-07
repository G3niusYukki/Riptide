// Tests for src/hooks/useTheme.ts
//
// Phase C10.1 — the 3-mode (system / light / dark) theme controller.
// Four tests cover the public surface of the hook:
//
//   1. Default state: "system" mode resolves against the OS
//      prefers-color-scheme: dark → resolvedTheme = "dark" and the
//      data-theme attribute is painted on <html>.
//   2. setTheme("light"): overrides the OS preference; the
//      data-theme attribute flips to "light".
//   3. setTheme("dark"): overrides the OS preference; the
//      data-theme attribute flips to "dark" (this also covers the
//      case where system prefers light).
//   4. "system" mode stays subscribed to matchMedia: a simulated OS
//      change (dark → light) updates resolvedTheme without the user
//      having to touch the UI.
//
// All four tests assert on the *real* side effect (the data-theme
// attribute on document.documentElement), which is the bug the
// C10.1 pass is fixing — the previous version of App.tsx toggled
// `light` / `dark` classes instead, which tokens.css never matched.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, renderHook } from '@testing-library/react';
import { useTheme } from '../useTheme';
import { useRiptideStore } from '../../stores/riptide';

// Per-test matchMedia mock. We keep the listener array so the test
// can simulate an OS-level change without poking at jsdom internals.
type MediaHandler = (e: MediaQueryListEvent) => void;

interface MockedMediaQuery {
  matches: boolean;
  media: string;
  onchange: null;
  addEventListener: (_: 'change', cb: MediaHandler) => void;
  removeEventListener: (_: 'change', cb: MediaHandler) => void;
  addListener: (cb: MediaHandler) => void;
  removeListener: (cb: MediaHandler) => void;
  dispatchEvent: () => boolean;
}

let mediaListeners: MediaHandler[] = [];
let mediaMatches = false;

function installMatchMediaMock() {
  mediaListeners = [];
  const mq: MockedMediaQuery = {
    get matches() {
      return mediaMatches;
    },
    media: '(prefers-color-scheme: dark)',
    onchange: null,
    addEventListener: (_event, cb) => {
      mediaListeners.push(cb);
    },
    removeEventListener: (_event, cb) => {
      mediaListeners = mediaListeners.filter((l) => l !== cb);
    },
    addListener: (cb) => {
      mediaListeners.push(cb);
    },
    removeListener: (cb) => {
      mediaListeners = mediaListeners.filter((l) => l !== cb);
    },
    dispatchEvent: () => true,
  };
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    configurable: true,
    value: vi.fn().mockReturnValue(mq),
  });
}

beforeEach(() => {
  installMatchMediaMock();
  mediaMatches = false;
  // Reset the riptide store to a known starting state and clear any
  // data-theme left over by a previous test.
  useRiptideStore.setState({ theme: 'system' });
  document.documentElement.removeAttribute('data-theme');
  localStorage.removeItem('riptide-storage');
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('useTheme — 3-mode controller', () => {
  it('1. "system" mode resolves against the OS prefers-color-scheme: dark', () => {
    mediaMatches = true; // OS prefers dark
    const { result } = renderHook(() => useTheme());

    expect(result.current.theme).toBe('system');
    expect(result.current.resolvedTheme).toBe('dark');
    expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
  });

  it('2. setTheme("light") applies data-theme="light" regardless of the OS pref', () => {
    mediaMatches = true; // OS prefers dark — the user is overriding it
    const { result } = renderHook(() => useTheme());

    act(() => {
      result.current.setTheme('light');
    });

    expect(result.current.theme).toBe('light');
    expect(result.current.resolvedTheme).toBe('light');
    expect(document.documentElement.getAttribute('data-theme')).toBe('light');
  });

  it('3. setTheme("dark") applies data-theme="dark" when the OS prefers light', () => {
    mediaMatches = false; // OS prefers light — the user is overriding it
    const { result } = renderHook(() => useTheme());

    act(() => {
      result.current.setTheme('dark');
    });

    expect(result.current.theme).toBe('dark');
    expect(result.current.resolvedTheme).toBe('dark');
    expect(document.documentElement.getAttribute('data-theme')).toBe('dark');
  });

  it('4. "system" mode follows matchMedia changes (OS dark → light flip)', () => {
    mediaMatches = true; // start with OS = dark
    const { result } = renderHook(() => useTheme());
    act(() => {
      result.current.setTheme('system');
    });

    // Sanity: the hook reflects the OS dark pref.
    expect(result.current.resolvedTheme).toBe('dark');

    // Simulate the OS flipping to light. The matchMedia mock calls
    // every registered listener synchronously, so `act` is enough.
    mediaMatches = false;
    act(() => {
      mediaListeners.forEach((cb) =>
        cb({ matches: false, media: '(prefers-color-scheme: dark)' } as MediaQueryListEvent),
      );
    });

    expect(result.current.theme).toBe('system');
    expect(result.current.resolvedTheme).toBe('light');
    expect(document.documentElement.getAttribute('data-theme')).toBe('light');
  });
});
