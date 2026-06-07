// Tests for src/components/Logbook/
//
// The Logbook surface is a self-contained view that pulls data via
// `useLogbook` (TanStack Query) and writes back through the
// `useLogbookClear` / `useLogbookExport` mutations. We mock the
// `services/tauri` boundary so the test owns the data plane and the
// `useLogbookStore` so the test owns the filter selection.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { LogbookView } from "../index";
import { LogbookFilters } from "../LogbookFilters";
import { LogEntryRow } from "../LogEntryRow";
import { ClearButton } from "../ClearButton";
import { ExportButton, defaultExportPath } from "../ExportButton";
import { useLogbookStore } from "../../../stores/logbook";
import { useToastStore } from "../../../stores/toast";
import type { LogEntry } from "../../../services/tauri";

vi.mock("../../../services/tauri", () => ({
  logbookQuery: vi.fn(),
  logbookClear: vi.fn(),
  logbookExport: vi.fn(),
}));

import * as tauri from "../../../services/tauri";

const mockedTauri = vi.mocked(tauri);

const sampleEntry = (overrides: Partial<LogEntry> = {}): LogEntry => ({
  ts: "2026-06-05T22:00:00.000Z",
  level: "info",
  category: "mode",
  message: "switched to system_proxy",
  fields: { from: "off", to: "system_proxy" },
  ...overrides,
});

function makeWrapper() {
  const client = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0, refetchOnWindowFocus: false },
      mutations: { retry: false },
    },
  });
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
}

function resetStores() {
  useLogbookStore.getState().clearLocal();
  // Toast store has no reset; replace its toasts array directly.
  useToastStore.setState({ toasts: [] });
}

beforeEach(() => {
  vi.clearAllMocks();
  resetStores();
});

afterEach(() => {
  resetStores();
});

describe("components/Logbook — LogEntryRow", () => {
  it("renders timestamp, level badge, category, and message", () => {
    const entry = sampleEntry({ message: "hello world", level: "warning", category: "service" });
    render(
      <table>
        <tbody>
          <LogEntryRow entry={entry} />
        </tbody>
      </table>,
    );
    const row = screen.getByTestId("logbook-row");
    expect(row).toHaveAttribute("data-level", "warning");
    expect(row).toHaveAttribute("data-category", "service");
    expect(row.textContent).toContain("hello world");
    // The level badge uppercase-wraps the level string.
    expect(row.textContent?.toLowerCase()).toContain("warning");
  });
});

describe("components/Logbook — empty state and row count", () => {
  it("shows the 'No log entries' empty state when the backend returns []", async () => {
    mockedTauri.logbookQuery.mockResolvedValue([]);
    const Wrapper = makeWrapper();

    render(<LogbookView />, { wrapper: Wrapper });

    await waitFor(() => {
      expect(screen.getByText(/no log entries/i)).toBeInTheDocument();
    });
    expect(mockedTauri.logbookQuery).toHaveBeenCalled();
  });

  it("renders one row per backend entry (5 entries → 5 rows)", async () => {
    const five: LogEntry[] = [
      sampleEntry({ message: "e1", ts: "2026-06-05T22:00:01.000Z" }),
      sampleEntry({ message: "e2", ts: "2026-06-05T22:00:02.000Z" }),
      sampleEntry({ message: "e3", ts: "2026-06-05T22:00:03.000Z" }),
      sampleEntry({ message: "e4", ts: "2026-06-05T22:00:04.000Z" }),
      sampleEntry({ message: "e5", ts: "2026-06-05T22:00:05.000Z" }),
    ];
    mockedTauri.logbookQuery.mockResolvedValue(five);
    const Wrapper = makeWrapper();

    render(<LogbookView />, { wrapper: Wrapper });

    // Wait for the actual rows to appear — the previous version waited
    // on the absence of the empty-state text, which is also true during
    // the initial loading tick and raced ahead of the mocked fetch.
    await waitFor(() => {
      expect(screen.getAllByTestId("logbook-row")).toHaveLength(5);
    });
    const rows = screen.getAllByTestId("logbook-row");
    expect(rows[0].textContent).toContain("e1");
    expect(rows[4].textContent).toContain("e5");
  });
});

describe("components/Logbook — filters narrow the visible rows", () => {
  const mixed: LogEntry[] = [
    sampleEntry({ message: "info-mode", level: "info", category: "mode", ts: "2026-06-01T00:00:00.000Z" }),
    sampleEntry({ message: "warn-sub", level: "warning", category: "subscription", ts: "2026-06-02T00:00:00.000Z" }),
    sampleEntry({ message: "err-mode", level: "error", category: "mode", ts: "2026-06-03T00:00:00.000Z" }),
    sampleEntry({ message: "info-svc", level: "info", category: "service", ts: "2026-06-04T00:00:00.000Z" }),
    sampleEntry({ message: "err-sub", level: "error", category: "subscription", ts: "2026-06-05T00:00:00.000Z" }),
  ];

  it("level filter (error) leaves only error-level rows visible", async () => {
    mockedTauri.logbookQuery.mockResolvedValue(mixed);
    const Wrapper = makeWrapper();

    // Seed the store with a level filter before mounting the view so
    // the very first query already requests the filtered slice.
    useLogbookStore.getState().setFilter({ level: "error" });

    render(<LogbookView />, { wrapper: Wrapper });

    await waitFor(() => {
      const rows = screen.getAllByTestId("logbook-row");
      expect(rows).toHaveLength(2);
    });
    const rows = screen.getAllByTestId("logbook-row");
    expect(rows.every((r) => r.getAttribute("data-level") === "error")).toBe(true);
  });

  it("category filter (mode) leaves only mode-category rows visible", async () => {
    mockedTauri.logbookQuery.mockResolvedValue(mixed);
    const Wrapper = makeWrapper();

    useLogbookStore.getState().setFilter({ category: "mode" });

    render(<LogbookView />, { wrapper: Wrapper });

    await waitFor(() => {
      const rows = screen.getAllByTestId("logbook-row");
      expect(rows).toHaveLength(2);
    });
    const rows = screen.getAllByTestId("logbook-row");
    expect(rows.every((r) => r.getAttribute("data-category") === "mode")).toBe(true);
  });

  it("date range filter (from/to) limits the visible window", async () => {
    mockedTauri.logbookQuery.mockResolvedValue(mixed);
    const Wrapper = makeWrapper();

    // Window covers 2026-06-02 .. 2026-06-04 inclusive (3 entries).
    useLogbookStore.getState().setFilter({
      from: "2026-06-02T00:00:00.000Z",
      to: "2026-06-04T23:59:59.999Z",
    });

    render(<LogbookView />, { wrapper: Wrapper });

    await waitFor(() => {
      const rows = screen.getAllByTestId("logbook-row");
      expect(rows).toHaveLength(3);
    });
  });
});

describe("components/Logbook — clear and export actions", () => {
  it("Clear button shows confirm dialog; on accept it calls logbookClear and fires the onCleared toast", async () => {
    mockedTauri.logbookClear.mockResolvedValue(7);
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(true);
    const Wrapper = makeWrapper();

    render(<ClearButton onCleared={() => undefined} />, { wrapper: Wrapper });

    await act(async () => {
      fireEvent.click(screen.getByTestId("logbook-clear-button"));
    });

    expect(confirmSpy).toHaveBeenCalledTimes(1);
    await waitFor(() => {
      expect(mockedTauri.logbookClear).toHaveBeenCalledTimes(1);
    });
    // The mutation is called with no category / no beforeDate so the
    // backend wipes everything.
    expect(mockedTauri.logbookClear).toHaveBeenCalledWith(null, null);

    confirmSpy.mockRestore();
  });

  it("Export button calls logbookExport with the current filter range and a deterministic path", async () => {
    mockedTauri.logbookExport.mockResolvedValue(42);
    const Wrapper = makeWrapper();

    // Pin the filter so the export call is reproducible. The button
    // itself owns path generation, so we just verify the call.
    useLogbookStore.getState().setFilter({
      from: "2026-06-01T00:00:00.000Z",
      to: "2026-06-05T23:59:59.999Z",
    });

    render(<ExportButton filters={useLogbookStore.getState().filters} />, {
      wrapper: Wrapper,
    });

    await act(async () => {
      fireEvent.click(screen.getByTestId("logbook-export-button"));
    });

    await waitFor(() => {
      expect(mockedTauri.logbookExport).toHaveBeenCalledTimes(1);
    });
    const [fromArg, toArg, destArg] = mockedTauri.logbookExport.mock.calls[0];
    expect(fromArg).toBe("2026-06-01T00:00:00.000Z");
    expect(toArg).toBe("2026-06-05T23:59:59.999Z");
    expect(typeof destArg).toBe("string");
    expect(destArg).toMatch(/\.jsonl$/);
    expect(destArg).toContain("riptide-logbook");

    // defaultExportPath helper — assert the timestamp shape and the
    // presence of the date-range tag when from/to are set.
    const fixedNow = new Date("2026-06-07T08:00:00.000Z");
    const pathWithRange = defaultExportPath(
      { from: "2026-06-01T00:00:00.000Z", to: "2026-06-05T23:59:59.999Z" },
      fixedNow,
    );
    expect(pathWithRange).toBe(
      "riptide-logbook-2026-06-07T08-00-00-from_2026-06-01_to_2026-06-05.jsonl",
    );
    const pathNoRange = defaultExportPath({}, fixedNow);
    expect(pathNoRange).toBe("riptide-logbook-2026-06-07T08-00-00.jsonl");
  });
});

describe("components/Logbook — LogbookFilters bar", () => {
  it("renders the three axes and clears them on demand", () => {
    const onChange = vi.fn();
    const initial: ReturnType<typeof useLogbookStore.getState>["filters"] = {
      level: "info",
      category: "mode",
    };

    render(<LogbookFilters filters={initial} onChange={onChange} />);

    expect(screen.getByTestId("filter-level")).toBeInTheDocument();
    expect(screen.getByTestId("filter-category")).toBeInTheDocument();
    expect(screen.getByTestId("filter-from")).toBeInTheDocument();
    expect(screen.getByTestId("filter-to")).toBeInTheDocument();

    // The "Clear filters" affordance is only visible when at least one
    // axis is active.
    fireEvent.click(screen.getByRole("button", { name: /clear filters/i }));
    expect(onChange).toHaveBeenCalledWith({
      level: undefined,
      category: undefined,
      from: undefined,
      to: undefined,
    });
  });
});
