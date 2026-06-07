// Tests for the Scene editor (Phase C, C8.3).
//
// The Scene editor's MVP form covers three matcher kinds
// (process / domain / ipset) and a mode override picker. These two
// tests pin the rendering contract:
//
//   1. SceneEditorView with an initial scene containing one of each
//      matcher kind renders all three kind badges.
//   2. The form's "Add matcher" controls surface one button per
//      kind, and clicking each one appends the right Matcher shape
//      to the editor's matchers list.
//
// We pass `initialScenes` to bypass the IPC layer — the tests
// exercise the pure render/edit path, not the Tauri command wire.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { SceneEditorView } from "../SceneEditorView";
import type { Scene } from "../../../types/scene";

// Mock the Tauri service so the IPC wrappers used by the view don't
// reach into the real Tauri runtime. We only need the `sceneList`
// stub — the view calls it on mount when `initialScenes` is not
// provided, so the mock is the fallback. Tests that pass
// `initialScenes` never hit the mock.
vi.mock("../../../services/tauri", () => ({
  sceneList: vi.fn(() => Promise.resolve([])),
  sceneCreate: vi.fn(() => Promise.reject(new Error("not used in these tests"))),
  sceneUpdate: vi.fn(() => Promise.reject(new Error("not used in these tests"))),
  sceneDelete: vi.fn(() => Promise.reject(new Error("not used in these tests"))),
  sceneApply: vi.fn(() => Promise.reject(new Error("not used in these tests"))),
}));

function makeScene(overrides: Partial<Scene> = {}): Scene {
  return {
    id: overrides.id ?? "scene-1",
    name: overrides.name ?? "测试场景",
    mode: overrides.mode ?? "tun",
    enabled: overrides.enabled ?? true,
    matchers: overrides.matchers ?? [],
    created_at: overrides.created_at ?? "2026-06-07T08:00:00.000Z",
    updated_at: overrides.updated_at ?? "2026-06-07T08:00:00.000Z",
  };
}

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  cleanup();
});

function renderWithRouter(ui: React.ReactNode) {
  return render(
    <MemoryRouter initialEntries={["/scenes"]}>
      <Routes>
        <Route path="/scenes" element={ui} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("SceneEditorView — renders three matcher kinds", () => {
  it("shows a kind badge for process / domain / ipset when all three are present", () => {
    const scene = makeScene({
      matchers: [
        { kind: "process", pattern: "chrome.exe" },
        { kind: "domain", pattern: "example.com" },
        { kind: "ipset", value: "10.0.0.0/8" },
      ],
    });

    renderWithRouter(<SceneEditorView initialScenes={[scene]} />);

    // Open the editor for the seeded scene so the form is on screen.
    fireEvent.click(screen.getByTestId("scene-row-edit"));

    // The form's matchers list is on screen.
    const list = screen.getByTestId("scene-form-matchers");
    const rows = within(list).getAllByTestId("scene-form-matcher");
    expect(rows).toHaveLength(3);

    // Each row carries a `data-kind` attribute that pins the matcher
    // shape — this is the C8.4 "renders 3 matcher kinds" gate.
    const kinds = rows.map((r) => r.getAttribute("data-kind")).sort();
    expect(kinds).toEqual(["domain", "ipset", "process"]);

    // The summary line at the bottom of the form surfaces the
    // sorted list of unique kinds. Sorted alphabetically: 域名 +
    // 进程 + IP 集.
    const summary = screen.getByTestId("scene-form-kinds-summary");
    expect(summary.textContent).toMatch(/进程/);
    expect(summary.textContent).toMatch(/域名/);
    expect(summary.textContent).toMatch(/IP 集/);
  });

  it("renders a per-kind Add Matcher button and appends the right shape to matchers", () => {
    renderWithRouter(<SceneEditorView initialScenes={[]} />);

    // The empty state shows the "新建场景" CTA.
    fireEvent.click(screen.getByTestId("scene-new"));

    // Three Add Matcher buttons exist — one per matcher kind.
    const addProcess = screen.getByTestId("scene-form-add-process");
    const addDomain = screen.getByTestId("scene-form-add-domain");
    const addIpset = screen.getByTestId("scene-form-add-ipset");
    expect(addProcess).toHaveAttribute("data-matcher-kind", "process");
    expect(addDomain).toHaveAttribute("data-matcher-kind", "domain");
    expect(addIpset).toHaveAttribute("data-matcher-kind", "ipset");

    // Click each one — the matchers list grows by one row of the
    // correct kind, in the order they were added.
    fireEvent.click(addProcess);
    fireEvent.click(addDomain);
    fireEvent.click(addIpset);

    const list = screen.getByTestId("scene-form-matchers");
    const rows = within(list).getAllByTestId("scene-form-matcher");
    expect(rows).toHaveLength(3);
    expect(rows[0]).toHaveAttribute("data-kind", "process");
    expect(rows[1]).toHaveAttribute("data-kind", "domain");
    expect(rows[2]).toHaveAttribute("data-kind", "ipset");

    // Each row has a text input. The kind-specific placeholder
    // confirms the right field shape is rendered (process / domain
    // use `pattern`; ipset uses `value`).
    const inputs = within(list).getAllByTestId("scene-form-matcher-input");
    expect(inputs).toHaveLength(3);
    expect(inputs[0]).toHaveAttribute("placeholder", expect.stringContaining("chrome.exe"));
    expect(inputs[1]).toHaveAttribute("placeholder", expect.stringContaining("example.com"));
    expect(inputs[2]).toHaveAttribute("placeholder", expect.stringContaining("10.0.0.0/24"));
  });
});
