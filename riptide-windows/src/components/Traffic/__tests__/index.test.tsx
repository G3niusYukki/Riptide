// Tests for src/components/Traffic/ (C13.2 — top-level Traffic tab).
//
// The Traffic tab was extracted from the Dashboard "实时流量" panel.
// The testable contract is:
//
//   1. Visiting /traffic mounts the page and shows the "流量" header
//      and the live-state card.
//   2. The Sidebar shows the new "流量" entry under /traffic.
//   3. When the proxy is stopped (isRunning=false), the page shows the
//      empty state with the "启动代理后即可查看流量曲线" hint instead of
//      a chart.
//   4. Clicking the Sidebar entry navigates to /traffic.
//
// The Tauri `getTraffic` wrapper is mocked so the React Query effect
// in useTraffic does not crash in jsdom. The chart itself (recharts)
// is not asserted here — its only consumer is the extracted
// TrafficChart which already has its own visual contract; we only
// assert that the page host is in the right state.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";

// Mock the tauri IPC so useTraffic's React Query effect can resolve
// without a real mihomo running. Returning 0/0 keeps the chart in its
// "empty" branch (history.length === 0) and the page in the
// "未启动" empty state.
vi.mock("../../../services/tauri", () => ({
  getTraffic: vi.fn().mockResolvedValue({ up: 0, down: 0 }),
}));

// The Zustand persist middleware hits localStorage in jsdom, which
// can leak state between tests. We mock the store with a plain
// selector so each test owns the slice it cares about.
vi.mock("../../../stores/riptide", () => {
  type Slice = {
    isRunning: boolean;
    mode: string;
    modeTransitioning: boolean;
    traffic: { upload: number; download: number; uploadSpeed: number; downloadSpeed: number };
    setTraffic: ReturnType<typeof vi.fn>;
  };
  const state: Slice = {
    isRunning: false,
    mode: "off",
    modeTransitioning: false,
    traffic: { upload: 0, download: 0, uploadSpeed: 0, downloadSpeed: 0 },
    // useTraffic reads s.setTraffic via a selector; provide a noop fn
    // so the hook mounts without crashing.
    setTraffic: vi.fn(),
  };
  // Accept both `useStore()` (returns full state) and
  // `useStore(selector)` (runs the selector against state) so that
  // Traffic/index.tsx's `const { isRunning, traffic } = useRiptideStore()`
  // and Sidebar's `useRiptideStore((s) => s.mode)` both work.
  const useStore = <T,>(selector?: (s: Slice) => T): T | Slice =>
    selector ? selector(state) : state;
  (useStore as unknown as { getState: () => Slice }).getState = () => state;
  (useStore as unknown as { setState: (next: Partial<Slice>) => void }).setState = (next) =>
    Object.assign(state, next);
  return { useRiptideStore: useStore };
});

import { Traffic } from "../index";
import { Sidebar } from "../../Sidebar";
import { useRiptideStore } from "../../../stores/riptide";

function makeWrapper() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0, refetchOnWindowFocus: false } },
  });
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
}

function setRunning(running: boolean) {
  (useRiptideStore as unknown as { setState: (s: object) => void }).setState({
    isRunning: running,
    mode: running ? "system_proxy" : "off",
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  setRunning(false);
});

afterEach(() => {
  cleanup();
  setRunning(false);
});

describe("/traffic route — Traffic top-level tab", () => {
  it("renders the Traffic page shell at /traffic and the Sidebar shows the new entry", async () => {
    // 1) The route /traffic mounts the page and shows the empty-state
    //    hint (isRunning=false by default; tauri.getTraffic returns 0).
    render(
      <MemoryRouter initialEntries={["/traffic"]}>
        <Routes>
          <Route path="/traffic" element={<Traffic />} />
        </Routes>
      </MemoryRouter>,
      { wrapper: makeWrapper() },
    );
    expect(await screen.findByTestId("traffic-page")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "流量" })).toBeInTheDocument();
    expect(screen.getByTestId("traffic-stat-download")).toBeInTheDocument();
    expect(screen.getByTestId("traffic-stat-upload")).toBeInTheDocument();
    // Stopped-state hint must render in the chart card.
    expect(await screen.findByTestId("traffic-chart-card")).toBeInTheDocument();
    expect(screen.getByText(/启动代理后即可查看流量曲线/)).toBeInTheDocument();

    // 2) The Sidebar exposes the new /traffic link. The 9-tab count
    //    is the same surface target as the Config test.
    render(
      <MemoryRouter initialEntries={["/traffic"]}>
        <Sidebar />
      </MemoryRouter>,
      { wrapper: makeWrapper() },
    );
    const trafficLink = screen.getByRole("link", { name: /流量/ });
    expect(trafficLink).toBeInTheDocument();
    expect(trafficLink.getAttribute("href")).toBe("/traffic");
    expect(screen.getAllByRole("link")).toHaveLength(9);
  });

  it("clicking the Sidebar Traffic entry navigates to /traffic", async () => {
    render(
      <MemoryRouter initialEntries={["/"]}>
        <Sidebar />
        <Routes>
          <Route
            path="/traffic"
            element={
              <QueryClientProvider
                client={
                  new QueryClient({
                    defaultOptions: { queries: { retry: false, gcTime: 0 } },
                  })
                }
              >
                <div data-testid="traffic-route">on traffic</div>
              </QueryClientProvider>
            }
          />
          <Route path="/" element={<div data-testid="root-route">on root</div>} />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByTestId("root-route")).toBeInTheDocument();

    const trafficLink = screen.getByRole("link", { name: /流量/ });
    fireEvent.click(trafficLink);

    await waitFor(() =>
      expect(screen.getByTestId("traffic-route")).toBeInTheDocument(),
    );
  });
});
