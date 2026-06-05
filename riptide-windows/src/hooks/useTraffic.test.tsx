// Tests for src/hooks/useTraffic.ts
//
// The traffic hook subscribes to mihomo's `/traffic` endpoint once per
// second and derives upload/download speeds from a per-instance
// `useRef<{ up, down, time }>`. We use fake timers + `act` so the
// polling interval is deterministic, and `vi.setSystemTime` to pin
// `Date.now()` for the speed calculation.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useTraffic } from "./useTraffic";

vi.mock("../services/tauri", () => ({
  getTraffic: vi.fn(),
}));

vi.mock("../stores/riptide", () => {
  type Slice = { isRunning: boolean; setTraffic: ReturnType<typeof vi.fn> };
  const state: Slice = { isRunning: true, setTraffic: vi.fn() };
  const useStore = <T,>(selector: (s: Slice) => T) => selector(state);
  (useStore as unknown as { getState: () => Slice }).getState = () => state;
  (useStore as unknown as { setState: (next: Partial<Slice>) => void }).setState = (next) => {
    Object.assign(state, next);
  };
  return { useRiptideStore: useStore };
});

import * as tauri from "../services/tauri";
import { useRiptideStore } from "../stores/riptide";

const mockedTauri = vi.mocked(tauri);

function makeWrapper() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
}

function setStoreState(partial: { isRunning?: boolean; setTraffic?: ReturnType<typeof vi.fn> }) {
  (useRiptideStore as unknown as { setState: (s: object) => void }).setState(partial);
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));
});

afterEach(() => {
  vi.useRealTimers();
  vi.resetAllMocks();
  setStoreState({
    isRunning: true,
    setTraffic: (useRiptideStore.getState() as unknown as { setTraffic: ReturnType<typeof vi.fn> })
      .setTraffic,
  });
});

describe("hooks/useTraffic — polling lifecycle", () => {
  it("fires an initial fetch and stops polling on unmount", async () => {
    mockedTauri.getTraffic.mockResolvedValue({ up: 0, down: 0 });

    const { result, unmount } = renderHook(() => useTraffic(), {
      wrapper: makeWrapper(),
    });

    // Initial fetch — flush the queued setTimeout(0) inside react-query.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(result.current.isSuccess).toBe(true);
    const initialCalls = mockedTauri.getTraffic.mock.calls.length;
    expect(initialCalls).toBeGreaterThanOrEqual(1);

    // Advance time well past the 1-second refetchInterval and confirm
    // additional polls happen while mounted.
    mockedTauri.getTraffic.mockResolvedValue({ up: 10, down: 20 });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(3500);
    });
    const midCalls = mockedTauri.getTraffic.mock.calls.length;
    expect(midCalls).toBeGreaterThan(initialCalls);

    // Unmount: react-query should clear the interval. We assert that
    // no further fetches happen after unmount.
    const callsAtUnmount = mockedTauri.getTraffic.mock.calls.length;
    unmount();
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000);
    });
    expect(mockedTauri.getTraffic.mock.calls.length).toBe(callsAtUnmount);
  });

  it("merges successive polls and computes upload/download speed from deltas", async () => {
    const setTraffic = vi.fn();
    setStoreState({ isRunning: true, setTraffic });

    // React-query's refetchInterval is 1s. Polls therefore fire at
    // t = 0, 1000, 2000 (relative to query-enable). prevValues is
    // updated after each fetch, so the timeDiff between consecutive
    // polls is ~1s.
    //
    // Poll 1 at t=0: baseline — no previous → speeds = 0.
    mockedTauri.getTraffic.mockResolvedValueOnce({ up: 1000, down: 5000 });
    // Poll 2 at t=1000ms: +1000 / +5000 over 1s → 1000 / 5000 B/s.
    mockedTauri.getTraffic.mockResolvedValueOnce({ up: 2000, down: 10000 });
    // Poll 3 at t=2000ms: +1000 / +5000 over 1s → 1000 / 5000 B/s.
    mockedTauri.getTraffic.mockResolvedValueOnce({ up: 3000, down: 15000 });

    const { result } = renderHook(() => useTraffic(), { wrapper: makeWrapper() });

    // Drive the first poll (t=0).
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0);
    });
    expect(setTraffic).toHaveBeenCalledTimes(1);
    const first = setTraffic.mock.calls[0][0] as {
      upload: number;
      download: number;
      uploadSpeed: number;
      downloadSpeed: number;
    };
    expect(first.upload).toBe(1000);
    expect(first.download).toBe(5000);
    expect(first.uploadSpeed).toBe(0);
    expect(first.downloadSpeed).toBe(0);

    // Drive 1 second — poll 2.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });
    expect(setTraffic.mock.calls.length).toBeGreaterThanOrEqual(2);
    const second = setTraffic.mock.calls[1][0] as {
      upload: number;
      download: number;
      uploadSpeed: number;
      downloadSpeed: number;
    };
    expect(second.upload).toBe(2000);
    expect(second.download).toBe(10000);
    expect(second.uploadSpeed).toBeCloseTo(1000, 5);
    expect(second.downloadSpeed).toBeCloseTo(5000, 5);

    // Drive 1 more second — poll 3.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1000);
    });
    expect(setTraffic.mock.calls.length).toBeGreaterThanOrEqual(3);
    const third = setTraffic.mock.calls[2][0] as {
      upload: number;
      download: number;
      uploadSpeed: number;
      downloadSpeed: number;
    };
    expect(third.upload).toBe(3000);
    expect(third.download).toBe(15000);
    expect(third.uploadSpeed).toBeCloseTo(1000, 5);
    expect(third.downloadSpeed).toBeCloseTo(5000, 5);

    expect(result.current.isError).toBe(false);
  });
});
