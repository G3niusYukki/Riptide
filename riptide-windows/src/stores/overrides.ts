// Zustand store for the Override UI shell.
//
// Mirrors the design shape of `stores/riptide.ts` (no `persist`
// middleware — overrides are backend-owned once Phase C2 wires the
// Rust side; until then the store is purely UI-local and reset on
// reload). Slices:
//
//   - overrides: the list returned by the (mocked) `list_overrides`
//     IPC call. Tests seed this slice directly; production will populate
//     it inside `OverridesPage` on mount.
//   - activeId: the override currently being edited / previewed / applied.
//   - loading / error: the same `is-loading` / `error.message` shape used
//     by other Zustand slices in this repo.

import { create } from 'zustand';
import type { Override, OverrideId } from '../types/override';

export interface OverridesState {
  overrides: Override[];
  activeId: OverrideId | null;
  loading: boolean;
  error: string | null;

  setOverrides: (overrides: Override[]) => void;
  upsertOverride: (override: Override) => void;
  removeOverride: (id: OverrideId) => void;
  setActiveId: (id: OverrideId | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  reset: () => void;
}

const initialState = {
  overrides: [] as Override[],
  activeId: null as OverrideId | null,
  loading: false,
  error: null as string | null,
};

export const useOverridesStore = create<OverridesState>()((set) => ({
  ...initialState,

  setOverrides: (overrides) => set({ overrides }),
  upsertOverride: (override) =>
    set((state) => {
      const idx = state.overrides.findIndex((o) => o.id === override.id);
      if (idx === -1) return { overrides: [...state.overrides, override] };
      const next = state.overrides.slice();
      next[idx] = override;
      return { overrides: next };
    }),
  removeOverride: (id) =>
    set((state) => ({
      overrides: state.overrides.filter((o) => o.id !== id),
      // Clear the active pointer if we just removed the active override.
      activeId: state.activeId === id ? null : state.activeId,
    })),
  setActiveId: (id) => set({ activeId: id }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  reset: () => set({ ...initialState }),
}));

/** Selector helper: returns the active Override object, or null. */
export const selectActiveOverride = (s: OverridesState): Override | null =>
  s.activeId === null ? null : s.overrides.find((o) => o.id === s.activeId) ?? null;
