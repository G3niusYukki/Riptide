// Tests for src/stores/logbook.ts
//
// The logbook store is a small synchronous cache that mirrors the
// TanStack Query state (entries, loading, error) plus a filter holder.
// These tests cover the action surface and the `clearLocal` reset
// path. Mutation-driven flows (`useLogbookClear` / `useLogbookExport`)
// are covered separately in the hook tests once the Rust backend
// lands.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { useLogbookStore } from './logbook';
import type { LogEntry } from '../services/tauri';

const sampleEntry = (overrides: Partial<LogEntry> = {}): LogEntry => ({
  ts: '2026-06-05T22:00:00.123Z',
  level: 'info',
  category: 'mode',
  message: 'switched to system_proxy',
  fields: { from: 'off', to: 'system_proxy' },
  ...overrides,
});

beforeEach(() => {
  // Start every test from a known empty state.
  useLogbookStore.getState().clearLocal();
});

afterEach(() => {
  useLogbookStore.getState().clearLocal();
});

describe('stores/logbook — basic actions', () => {
  it('setEntries, setFilter and clearLocal round-trip through the store', () => {
    const { setEntries, setFilter, clearLocal, entries, filters } = useLogbookStore.getState();

    // Initial state after beforeEach.
    expect(entries).toEqual([]);
    expect(filters).toEqual({});

    // Push two entries in newest-first order.
    setEntries([sampleEntry({ message: 'second' }), sampleEntry({ message: 'first' })]);
    expect(useLogbookStore.getState().entries).toHaveLength(2);
    expect(useLogbookStore.getState().entries[0].message).toBe('second');

    // Patches merge into the existing filter object so callers can
    // update a single axis without losing siblings.
    setFilter({ level: 'warning' });
    setFilter({ category: 'subscription' });
    expect(useLogbookStore.getState().filters).toEqual({
      level: 'warning',
      category: 'subscription',
    });

    // clearLocal wipes entries, filters, loading and error in one go.
    useLogbookStore.setState({ loading: true, error: 'boom' });
    clearLocal();
    const after = useLogbookStore.getState();
    expect(after.entries).toEqual([]);
    expect(after.filters).toEqual({});
    expect(after.loading).toBe(false);
    expect(after.error).toBeNull();
  });

  it('setLoading and setError update the mirror flags without touching entries', () => {
    const { setEntries, setLoading, setError, clearFilter } = useLogbookStore.getState();

    setEntries([sampleEntry()]);
    setLoading(true);
    setError('network down');

    const after = useLogbookStore.getState();
    expect(after.entries).toHaveLength(1);
    expect(after.loading).toBe(true);
    expect(after.error).toBe('network down');

    // clearFilter should drop filters but leave entries, loading, and
    // error alone — it is the surgical reset, complementing clearLocal.
    useLogbookStore.setState({ filters: { level: 'error' } });
    clearFilter();
    const filtered = useLogbookStore.getState();
    expect(filtered.filters).toEqual({});
    expect(filtered.entries).toHaveLength(1);
    expect(filtered.error).toBe('network down');
  });
});
