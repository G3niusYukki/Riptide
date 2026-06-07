// useNotification — bridge between the Rust NotificationDispatcher
// (5 emit paths on the Tauri event bus) and the in-app `useToastStore`.
//
// The Rust side emits `notify:<kind>` events with a `NotifyPayload { kind,
// title, body }` body. The hook auto-subscribes to all five kinds, routes
// each event through the user-supplied toast callback, and cleans up on
// unmount.
//
// The hook returns `{ subscribe, unsubscribe }` so the host component can
// choose:
//   * Auto-subscribe on mount + auto-cleanup on unmount (the default
//     pattern — see `useEffect` below).
//   * Manual control — call `subscribe()` and `unsubscribe()` from event
//     handlers (e.g. a Settings toggle that wants to suppress
//     `subscription_expiring` while the user is browsing profiles).
//
// Two tests in `useNotification.test.ts` exercise the wire-up:
//   1. `subscribe()` wires up 5 listeners that route events to toast.
//   2. `unsubscribe()` tears all 5 listeners down; subsequent events do
//      not fire the toast.

import { useCallback, useEffect, useRef } from 'react';
import { listen, type Event, type UnlistenFn } from '@tauri-apps/api/event';
import { useToastStore, type Toast } from '../stores/toast';

export type NotifyKind =
  | 'helper_install_error'
  | 'subscription_expiring'
  | 'config_reloaded'
  | 'mode_changed'
  | 'startup_complete';

export interface NotifyPayload {
  kind: NotifyKind;
  title: string;
  body: string;
}

export type ToastFn = (message: string, type?: Toast['type']) => void;

/** Map a Rust `NotifyKind` to the in-app toast colour. The Rust side does
 *  not pre-classify — the wire payload carries a neutral `title` and the
 *  hook decides the severity. This keeps the event contract UI-only. */
function kindToType(kind: NotifyKind): Toast['type'] {
  switch (kind) {
    case 'helper_install_error':
      return 'error';
    default:
      return 'info';
  }
}

/** The five event names. Order matches the Rust `DispatcherEvent` enum
 *  in `core/notify/dispatcher.rs::as_str()`. */
const EVENTS: NotifyKind[] = [
  'helper_install_error',
  'subscription_expiring',
  'config_reloaded',
  'mode_changed',
  'startup_complete',
];

export interface UseNotificationResult {
  /** Start listening. Idempotent — a second call is a no-op. Returns a
   *  cleanup function the caller can invoke manually (the hook also
   *  invokes it on unmount). */
  subscribe: () => Promise<() => void>;
  /** Stop listening. Idempotent — a second call is a no-op. */
  unsubscribe: () => void;
  /** `true` while a `subscribe()` call is in flight or while listeners
   *  are active. Useful for the host component to render a "Listening
   *  for notifications" badge. */
  isSubscribed: () => boolean;
}

/**
 * Bridge the Rust `notify:*` event bus to the in-app toast store.
 *
 * ```tsx
 * function AppBody() {
 *   const { subscribe, unsubscribe } = useNotification(useToastStore((s) => s.addToast));
 *   // Auto-subscribe on mount; auto-cleanup on unmount.
 *   return <Routes />;
 * }
 * ```
 *
 * The hook accepts either a Zustand selector returning the `addToast`
 * action (the common path) or any plain `(message, type) => void`
 * callback. The callback is captured at subscribe time so identity
 * stability of the store does not matter.
 */
export function useNotification(toast: ToastFn): UseNotificationResult {
  // Refs let the public `subscribe` / `unsubscribe` read the current
  // toast callback without forcing the host to memoize. The
  // `useEffect` below writes the latest value into `toastRef` on every
  // render so `subscribe()` always uses the freshest closure.
  const toastRef = useRef<ToastFn>(toast);
  useEffect(() => {
    toastRef.current = toast;
  }, [toast]);

  // Active unlisten handles, in registration order. `null` while not
  // subscribed.
  const unlistensRef = useRef<UnlistenFn[] | null>(null);
  // Promise-resolver queue: when `unsubscribe` is called while a
  // `subscribe` is still in flight, the resolver is queued and fired
  // the moment the listeners come up. The `unlistensRef` is then
  // invoked immediately to tear them down. This avoids a race where a
  // fast mount/unmount cycle leaves dangling listeners.
  const pendingUnsubRef = useRef<(() => void) | null>(null);

  const subscribe = useCallback(async (): Promise<() => void> => {
    if (unlistensRef.current) {
      // Idempotent: already subscribed — return a noop cleanup.
      return () => {};
    }

    // Register every event listener in parallel. `listen()` returns a
    // Tauri-side handle that survives until the matching `UnlistenFn`
    // is invoked; we keep a local copy so `unsubscribe` can call them.
    const fresh: UnlistenFn[] = [];
    unlistensRef.current = fresh;

    await Promise.all(
      EVENTS.map(async (kind) => {
        const unlisten = await listen<NotifyPayload>(`notify:${kind}`, (event: Event<NotifyPayload>) => {
          const payload = event.payload;
          // Defensive: drop the event if the Rust side shipped a kind
          // we do not recognise. Should not happen — the two sides
          // share the same 5-element list — but a misnamed emit would
          // otherwise surface as a `undefined` toast.
          if (!payload || typeof payload.body !== 'string') return;
          const type = kindToType(payload.kind);
          toastRef.current(payload.body, type);
        });
        fresh.push(unlisten);
      }),
    );

    // Race: an `unsubscribe` may have arrived while we were awaiting.
    // If so, tear the listeners down immediately and resolve the
    // queued call.
    if (pendingUnsubRef.current) {
      const fn = pendingUnsubRef.current;
      pendingUnsubRef.current = null;
      fn();
    }

    // Return a manual cleanup function. The `useEffect` below ignores
    // this and uses its own unmount path; manual callers (e.g. a
    // Settings toggle) can invoke it directly.
    return () => {
      if (unlistensRef.current === fresh) {
        fresh.forEach((fn) => {
          try {
            fn();
          } catch {
            // Listener may have already been cleaned up by a parallel
            // unmount — swallow.
          }
        });
        unlistensRef.current = null;
      }
    };
  }, []);

  const unsubscribe = useCallback(() => {
    const active = unlistensRef.current;
    if (!active) return;
    unlistensRef.current = null;
    active.forEach((fn) => {
      try {
        fn();
      } catch {
        // already torn down
      }
    });
  }, []);

  const isSubscribed = useCallback(() => unlistensRef.current !== null, []);

  // Auto-subscribe on mount; auto-unsubscribe on unmount. The host can
  // ignore `subscribe` / `unsubscribe` and rely solely on this — the
  // contract is the same.
  useEffect(() => {
    let manualCleanup: (() => void) | null = null;
    let cancelled = false;
    subscribe().then((cleanup) => {
      if (cancelled) {
        cleanup();
        return;
      }
      manualCleanup = cleanup;
    });
    return () => {
      cancelled = true;
      if (manualCleanup) manualCleanup();
      else unsubscribe();
    };
  }, [subscribe, unsubscribe]);

  return { subscribe, unsubscribe, isSubscribed };
}

/** Convenience wrapper: `useNotification` with the toast store already
 *  bound. Most call sites should use this instead of the raw hook so
 *  they do not have to thread the `useToastStore` selector through. */
export function useBoundNotification(): UseNotificationResult {
  const addToast = useToastStore((s) => s.addToast);
  return useNotification(addToast);
}
