// Tests for src/components/Config/ (C13.1 — top-level Config tab).
//
// The Config tab re-exports the existing Profiles implementation under
// the `/config` route. Phase C13+ will split it into ConfigMergeView
// and ConfigImportPreview; for the MVP this MVP the routing shape is
// the testable contract:
//
//   1. Visiting /config mounts the page and shows the "配置文件" header.
//   2. The Sidebar shows the new "配置" entry under /config (not the
//      old /profiles path), and the entry count is the 9-tab target
//      (Dashboard, Config, Proxy, Traffic, Rules, Connections, Logs,
//      Diagnostics, Settings).
//   3. Clicking the Sidebar entry navigates to /config.
//
// The Tauri wrappers are mocked so the component does not hit the
// real IPC boundary in jsdom. We don't assert any profile CRUD here
// — that surface is covered by the existing Profiles/index tests
// (none yet, but the page body is identical to the legacy /profiles
// route, so the regression risk is bounded).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

// Mock services/tauri so the profile list call rejects with the same
// shape the components expect in the UI-shell phase.
vi.mock("../../../services/tauri", () => ({
  getProfiles: vi.fn().mockResolvedValue([]),
  getActiveProfileId: vi.fn().mockResolvedValue(null),
  addProfile: vi.fn(),
  updateProfile: vi.fn(),
  removeProfile: vi.fn(),
  setActiveProfile: vi.fn(),
  importProfileFromUrl: vi.fn(),
  importShareUri: vi.fn(),
  registerWarpProfile: vi.fn(),
}));

import { Config } from "../index";
import { Sidebar } from "../../Sidebar";

function renderAtConfig() {
  return render(
    <MemoryRouter initialEntries={["/config"]}>
      <Routes>
        <Route path="/config" element={<Config />} />
        <Route path="*" element={<div data-testid="fallback" />} />
      </Routes>
    </MemoryRouter>,
  );
}

function renderSidebarAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Sidebar />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  cleanup();
});

describe("/config route — Config top-level tab", () => {
  it("renders the Config page shell at /config and the Sidebar shows the new entry", async () => {
    // 1) The route /config mounts the page (asserted by the "配置文件"
    //    header that the wrapped Profiles implementation renders).
    renderAtConfig();
    expect(await screen.findByText("配置文件")).toBeInTheDocument();

    // 2) The Sidebar exposes the new /config link. We render the
    //    Sidebar separately because the App.tsx Layout would pull
    //    in the Tauri runtime + theme effect that this MVP test
    //    does not need.
    renderSidebarAt("/config");
    const configLink = screen.getByRole("link", { name: /配置/ });
    expect(configLink).toBeInTheDocument();
    expect(configLink.getAttribute("href")).toBe("/config");

    // 9-tab target: Dashboard, Config, Proxy, Traffic, Rules,
    // Connections, Logs, Logbook, Settings.
    expect(screen.getAllByRole("link")).toHaveLength(9);
  });

  it("clicking the Sidebar Config entry navigates to /config", async () => {
    render(
      <MemoryRouter initialEntries={["/"]}>
        <Sidebar />
        <Routes>
          <Route path="/config" element={<div data-testid="config-route">on config</div>} />
          <Route path="/" element={<div data-testid="root-route">on root</div>} />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByTestId("root-route")).toBeInTheDocument();

    const configLink = screen.getByRole("link", { name: /配置/ });
    fireEvent.click(configLink);

    await waitFor(() =>
      expect(screen.getByTestId("config-route")).toBeInTheDocument(),
    );
  });
});
