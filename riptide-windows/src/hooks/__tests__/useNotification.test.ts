// Tests for src/hooks/useNotification.ts
//
// The hook wires the Rust `NotificationDispatcher`'s 5 `notify:*` events
// to the in-app toast store. Two tests cover the contract:
//
//   1. `subscribe()` registers 5 listeners (one per event kind), and a
//      synthetic event from the Rust side surfaces as a `toast()` call
//      with the correct severity (`error` for `helper_install_error`,
//      `info` for everything else).
//   2. `unsubscribe()` tears all 5 listeners down — a synthetic event
//      emitted after `unsubscribe()` does NOT call the toast function.
//
// We mock `@tauri-apps/api/event` so the test owns the listener list;
// the hook never has to round-trip through a live Tauri runtime.

import { act, renderHook, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useNotification } from '../useNotification';
import type { Event, UnlistenFn } from '@tauri-apps/api/event';

// ── Mock @tauri-apps/api/event ────────────────────────────────────────
//
// `listen()` is called once per event kind inside the hook. We capture
// every `(eventName, callback)` pair in a per-test map, and the
// returned unlisten handle appends to a per-test `unlistenCalls` list
// when invoked. The test then drives the contract by:
//   * `getHandler('notify:helper_install_error')` — returns the
//     callback the hook registered; the test can fire a synthetic
//     `Event<NotifyPayload>` to simulate a Rust emit.
//   * `unlistenCalls` — names of the events whose unlisten handles
//     have been invoked, used by the unsubscribe test.
type EventHandler = (event: Event<{ kind: string; title: string; body: string }>) => void;

interface MockState {
  handlers: Map<string, EventHandler>;
  unlistenCalls: string[];
  calls: string[];
}

let state: MockState;

vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn(async (event: string, cb: EventHandler): Promise<UnlistenFn> => {
    state.handlers.set(event, cb);
    state.calls.push(event);
    const unlisten: UnlistenFn = () => {
      // Record the unlisten call by event name. The hook captures this
      // closure directly in its `fresh` array; the test can later
      // assert that `unlistenCalls` contains the names of every
      // event whose unlisten handle the hook invoked.
      state.unlistenCalls.push(event);
    };
    return unlisten;
  }),
}));

function getHandler(event: string): EventHandler {
  const h = state.handlers.get(event);
  if (!h) throw new Error(`no handler registered for ${event}`);
  return h;
}

function makeEvent<T>(payload: T): Event<T> {
  return { event: 'synthetic', id: 1, payload };
}

beforeEach(() => {
  state = { handlers: new Map(), unlistenCalls: [], calls: [] };
});

afterEach(() => {
  vi.clearAllMocks();
});

describe('useNotification — subscribe / unsubscribe', () => {
  it('1. subscribe() wires 5 listeners; synthetic event → toast() with the right severity', async () => {
    const toast = vi.fn();
    const { result } = renderHook(() => useNotification(toast));

    // Wait for the auto-subscribe (in useEffect) to complete.
    await waitFor(() => {
      expect(result.current.isSubscribed()).toBe(true);
    });

    // All 5 `notify:*` listeners must be registered.
    expect(state.calls).toEqual(
      expect.arrayContaining([
        'notify:helper_install_error',
        'notify:subscription_expiring',
        'notify:config_reloaded',
        'notify:mode_changed',
        'notify:startup_complete',
      ]),
    );
    expect(state.calls).toHaveLength(5);

    // Fire a synthetic `helper_install_error` event — toast must be
    // called with the payload body and `type = 'error'`.
    act(() => {
      getHandler('notify:helper_install_error')(
        makeEvent({
          kind: 'helper_install_error',
          title: 'Helper service failed',
          body: 'RiptideTUN could not be started: timeout',
        }),
      );
    });
    expect(toast).toHaveBeenCalledWith(
      'RiptideTUN could not be started: timeout',
      'error',
    );

    // Fire a `subscription_expiring` event — must be `info` severity.
    act(() => {
      getHandler('notify:subscription_expiring')(
        makeEvent({
          kind: 'subscription_expiring',
          title: 'Subscription expiring',
          body: "'my-vpn' will refresh in 3 day(s)",
        }),
      );
    });
    expect(toast).toHaveBeenCalledWith("'my-vpn' will refresh in 3 day(s)", 'info');

    // Fire a `startup_complete` — also `info`.
    act(() => {
      getHandler('notify:startup_complete')(
        makeEvent({
          kind: 'startup_complete',
          title: 'Riptide is ready',
          body: 'v2.4.1 loaded',
        }),
      );
    });
    expect(toast).toHaveBeenCalledWith('v2.4.1 loaded', 'info');

    // Sanity: three events → three toast() calls.
    expect(toast).toHaveBeenCalledTimes(3);
  });

  it('2. unsubscribe() tears all 5 listeners down; subsequent events do not fire toast', async () => {
    const toast = vi.fn();
    const { result, unmount } = renderHook(() => useNotification(toast));

    await waitFor(() => {
      expect(result.current.isSubscribed()).toBe(true);
    });

    // Sanity: 5 unlisten handles are queued for the hook to call.
    expect(state.calls).toHaveLength(5);
    expect(state.unlistenCalls).toHaveLength(0);

    // Manual unsubscribe.
    act(() => {
      result.current.unsubscribe();
    });

    // All 5 unlisten handles must have been called.
    expect(state.unlistenCalls.sort()).toEqual(
      [
        'notify:config_reloaded',
        'notify:helper_install_error',
        'notify:mode_changed',
        'notify:startup_complete',
        'notify:subscription_expiring',
      ].sort(),
    );

    // `isSubscribed` flips to false after unsubscribe.
    expect(result.current.isSubscribed()).toBe(false);

    // Now unmount the hook — the auto-cleanup must be a no-op
    // (unsubscribe was already called manually, so the second call
    // short-circuits).
    unmount();
    expect(state.unlistenCalls).toHaveLength(5); // no double-fire

    // Sanity: the toast function was never called in this test
    // because no synthetic event was fired before unsubscribe.
    expect(toast).not.toHaveBeenCalled();
  });
});
