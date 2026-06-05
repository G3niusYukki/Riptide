// Zustand store for the persistent Logbook surface.
//
// Holds the locally-cached list of logbook entries plus the current
// filter selection. The actual data fetch lives in `hooks/useLogbook.ts`
// (TanStack Query); this store is the synchronous read-side cache and
// filter holder that components subscribe to.
//
// State layout matches the macOS `LogbookViewModel` shape (a 4-tuple
// of entries / filters / loading / error) so the eventual Phase C UI
// can read both sides through the same mental model.

import { create } from 'zustand';
import type { LogEntry, LogCategory, LogLevel } from '../services/tauri';

export interface LogbookFilters {
  level?: LogLevel;
  category?: LogCategory;
  /** ISO 8601 string. */
  from?: string;
  /** ISO 8601 string. */
  to?: string;
}

export interface LogbookState {
  /** Cached entries (newest first). Source of truth is TanStack Query;
   *  the store mirrors it so synchronous components can subscribe. */
  entries: LogEntry[];
  /** Active filter selection. Persisted for the lifetime of the app
   *  process; cleared on `clearLocal`. */
  filters: LogbookFilters;
  /** Mirrors the query's loading flag for components that don't want
   *  to wire up the query itself. */
  loading: boolean;
  /** Mirrors the query's last error, if any. */
  error: string | null;

  setEntries: (entries: LogEntry[]) => void;
  setFilter: (patch: Partial<LogbookFilters>) => void;
  clearFilter: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  /** Wipe the local cache and filters without touching the backend. */
  clearLocal: () => void;
}

export const useLogbookStore = create<LogbookState>((set) => ({
  entries: [],
  filters: {},
  loading: false,
  error: null,

  setEntries: (entries) => set({ entries }),
  setFilter: (patch) => set((state) => ({ filters: { ...state.filters, ...patch } })),
  clearFilter: () => set({ filters: {} }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  clearLocal: () => set({ entries: [], filters: {}, loading: false, error: null }),
}));
