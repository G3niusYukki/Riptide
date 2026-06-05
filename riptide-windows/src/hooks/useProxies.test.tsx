// Tests for src/hooks/useProxies.ts
//
// These hooks wrap mihomo REST calls (via the tauri service) in
// `@tanstack/react-query`. We mock both `services/tauri` and
// `useRiptideStore` so the test owns the data plane and the running
// state of the store.

import { afterEach, describe, expect, it, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { useAllProxies, useProxyGroups, useTestDelay } from "./useProxies";

vi.mock("../services/tauri", () => ({
  getAllProxies: vi.fn(),
  getProxyGroups: vi.fn(),
  testProxyDelay: vi.fn(),
  switchProxy: vi.fn(),
  testGroupDelay: vi.fn(),
}));

vi.mock("../stores/riptide", () => {
  // Minimal mock: only the slice the hook reads from is functional.
  // We expose a settable state so the test can flip isRunning to
  // enable the query and seed `proxies` for useTestDelay.
  type Slice = {
    isRunning: boolean;
    setProxies: ReturnType<typeof vi.fn>;
    setProxyGroups: ReturnType<typeof vi.fn>;
    proxies: { name: string; delay?: number }[];
  };
  const state: Slice = {
    isRunning: false,
    setProxies: vi.fn(),
    setProxyGroups: vi.fn(),
    proxies: [],
  };
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

function setStoreState(partial: {
  isRunning?: boolean;
  proxies?: { name: string; delay?: number }[];
  setProxies?: ReturnType<typeof vi.fn>;
}) {
  (useRiptideStore as unknown as { setState: (s: object) => void }).setState(partial);
}

afterEach(() => {
  vi.resetAllMocks();
  // Reset the store mock to off so the next test sees a clean slate.
  // Cast through `unknown` — the real store's `setProxies` is typed
  // as a concrete setter, but in the mocked store it's a vi.fn().
  setStoreState({
    isRunning: false,
    proxies: [],
    setProxies: (useRiptideStore.getState() as unknown as { setProxies: ReturnType<typeof vi.fn> })
      .setProxies,
  });
});

describe("hooks/useProxies — useAllProxies", () => {
  it("stays idle when isRunning is false and fires a fetch when flipped", async () => {
    setStoreState({ isRunning: false });

    mockedTauri.getAllProxies.mockResolvedValue([
      { name: "tokyo-1", type: "ss", delay: 100 },
    ]);

    const { result, rerender } = renderHook(() => useAllProxies(), {
      wrapper: makeWrapper(),
    });

    // Disabled query — no fetch yet.
    expect(result.current.isLoading).toBe(false);
    expect(result.current.isFetching).toBe(false);
    expect(mockedTauri.getAllProxies).not.toHaveBeenCalled();

    // Flip isRunning true and rerender. The query is now enabled and
    // the queryFn should fire once.
    setStoreState({ isRunning: true });
    rerender();

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockedTauri.getAllProxies).toHaveBeenCalledTimes(1);
    expect(result.current.data).toEqual([{ name: "tokyo-1", type: "ss", delay: 100 }]);
  });

  it("surfaces tauri.getAllProxies errors through the query error channel", async () => {
    setStoreState({ isRunning: true });
    mockedTauri.getAllProxies.mockRejectedValueOnce(new Error("mihomo down"));

    const { result } = renderHook(() => useAllProxies(), {
      wrapper: makeWrapper(),
    });

    await waitFor(() => expect(result.current.isError).toBe(true));
    expect(result.current.error).toBeInstanceOf(Error);
    expect((result.current.error as Error).message).toBe("mihomo down");
  });
});

describe("hooks/useProxies — useProxyGroups", () => {
  it("returns the group list from the mihomo API when enabled", async () => {
    setStoreState({ isRunning: true });
    mockedTauri.getProxyGroups.mockResolvedValue([
      { name: "GLOBAL", type: "select", proxies: ["A", "B"], now: "A" },
    ]);

    const { result } = renderHook(() => useProxyGroups(), {
      wrapper: makeWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toEqual([
      { name: "GLOBAL", type: "select", proxies: ["A", "B"], now: "A" },
    ]);
  });
});

describe("hooks/useProxies — useTestDelay", () => {
  it("calls testProxyDelay and writes the new delay back into the store", async () => {
    mockedTauri.testProxyDelay.mockResolvedValue(220);

    const setProxies = vi.fn();
    setStoreState({
      isRunning: true,
      setProxies,
      proxies: [
        { name: "A", delay: 100 },
        { name: "B", delay: 150 },
      ],
    });

    const { result } = renderHook(() => useTestDelay(), { wrapper: makeWrapper() });

    result.current.mutate({ name: "A" });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockedTauri.testProxyDelay).toHaveBeenCalledWith("A", undefined);
    expect(setProxies).toHaveBeenCalledTimes(1);
    const next = setProxies.mock.calls[0][0] as { name: string; delay?: number }[];
    expect(next[0]).toEqual({ name: "A", delay: 220 });
    expect(next[1]).toEqual({ name: "B", delay: 150 });
  });
});
