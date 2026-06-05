// React hooks for the persistent Logbook (Phase B B3).
//
// Three hooks live here:
//   - `useLogbook(filters)` — query the backend; auto-refetch on focus.
//   - `useLogbookClear()`   — mutation with a built-in confirm step so
//                             the Phase C UI can wire it up without
//                             re-implementing the dialog.
//   - `useLogbookExport()`  — mutation that writes a JSONL snapshot to
//                             a caller-supplied path.
//
// The data shape (`LogEntry` / `LogLevel` / `LogCategory` / `LogbookQuery`)
// is defined in `services/tauri.ts` so the IPC boundary and the hook
// surface can never drift.

import { useEffect } from 'react';
import { useQuery, useMutation, useQueryClient, type UseQueryResult } from '@tanstack/react-query';
import * as tauri from '../services/tauri';
import { useLogbookStore } from '../stores/logbook';
import type { LogEntry, LogCategory, LogLevel } from '../services/tauri';

// Query keys — keep hierarchical so `invalidateQueries({queryKey: ['logbook']})`
// from `useLogbookClear` sweeps both the list and any future detail queries.
const LOGBOOK_KEYS = {
  all: ['logbook'] as const,
  list: (filters: tauri.LogbookQuery) => [...LOGBOOK_KEYS.all, 'list', filters] as const,
};

/** Inputs for `useLogbook`. Mirrors `LogbookQuery` but makes the
 *  `level` / `category` fields strictly typed (no `null` shim needed
 *  for the hook API). */
export interface UseLogbookFilters {
  limit?: number;
  level?: LogLevel;
  category?: LogCategory;
  from?: string;
  to?: string;
}

/** Query the persistent logbook. Auto-refetches on window focus
 *  (`refetchOnWindowFocus: true` is set explicitly because the global
 *  `QueryClient` in `main.tsx` turns it off — the global default is
 *  tuned for the polling-based traffic / connection queries). */
export function useLogbook(filters: UseLogbookFilters = {}): UseQueryResult<LogEntry[]> {
  const setEntries = useLogbookStore((s) => s.setEntries);
  const setLoading = useLogbookStore((s) => s.setLoading);
  const setError = useLogbookStore((s) => s.setError);

  const query = useQuery({
    queryKey: LOGBOOK_KEYS.list(filters),
    queryFn: () =>
      tauri.logbookQuery({
        limit: filters.limit ?? null,
        level: filters.level ?? null,
        category: filters.category ?? null,
        from: filters.from ?? null,
        to: filters.to ?? null,
      }),
    // Explicit opt-in: the global default is false; logbook users
    // expect a fresh pull when they return to the tab.
    refetchOnWindowFocus: true,
    // Keep last data around on remount so the UI doesn't blank out
    // when filters change.
    placeholderData: (previous) => previous,
  });

  // Mirror the query state into the Zustand store for components that
  // only need synchronous access (e.g. a small badge that shows the
  // current entry count without subscribing to the query).
  useEffect(() => {
    setLoading(query.isFetching);
  }, [query.isFetching, setLoading]);

  useEffect(() => {
    if (query.data) {
      setEntries(query.data);
      if (query.error) {
        setError(String(query.error));
      } else {
        setError(null);
      }
    } else if (query.error) {
      setError(String(query.error));
    }
  }, [query.data, query.error, setEntries, setError]);

  return query;
}

/** Inputs for `useLogbookClear`. Both fields are optional; omit both
 *  to wipe everything. */
export interface LogbookClearArgs {
  category?: LogCategory;
  /** `YYYY-MM-DD` — delete entries from days strictly before this. */
  beforeDate?: string;
}

/** Mutation: clear logbook entries. On success, invalidates the
 *  list query so subscribers refetch (and the local store cache is
 *  repopulated via the `useLogbook` mirror effect).
 *
 *  Built-in `confirmAndClear` helper: wraps the mutation in a
 *  `window.confirm()` step. Phase C can replace this with a real
 *  dialog component without touching call sites that only need
 *  "clear with confirmation" semantics. */
export function useLogbookClear() {
  const queryClient = useQueryClient();

  const mutation = useMutation({
    mutationFn: async (args: LogbookClearArgs = {}) => {
      const removed = await tauri.logbookClear(args.category ?? null, args.beforeDate ?? null);
      return { args, removed };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: LOGBOOK_KEYS.all });
    },
  });

  /** Wrap `mutate` with a `window.confirm()` step. Returns the
   *  mutation result on accept, or `null` if the user cancelled.
   *  Defaults the message to the destructive variant; pass a
   *  custom string for category-scoped clears. */
  const confirmAndClear = async (
    args: LogbookClearArgs = {},
    confirmMessage = 'Clear logbook entries? This cannot be undone.',
  ) => {
    if (typeof window === 'undefined' || !window.confirm) {
      return mutation.mutateAsync(args);
    }
    if (!window.confirm(confirmMessage)) return null;
    return mutation.mutateAsync(args);
  };

  return { ...mutation, confirmAndClear };
}

/** Inputs for `useLogbookExport`. `destPath` is required — the UI is
 *  expected to source it from a save dialog. */
export interface LogbookExportArgs {
  from?: string;
  to?: string;
  destPath: string;
}

/** Mutation: write a JSONL snapshot of logbook entries to `destPath`.
 *  On success, returns the count written (so the UI can show a
 *  "Exported 1,234 entries" toast without a follow-up query). */
export function useLogbookExport() {
  return useMutation({
    mutationFn: async (args: LogbookExportArgs) => {
      const written = await tauri.logbookExport(args.from ?? null, args.to ?? null, args.destPath);
      return { ...args, written };
    },
  });
}
