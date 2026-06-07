// Tests for the Override UI shell.
//
// Phase C2 ships the UI ahead of the Rust backend. The wrappers in
// `services/tauri.ts` reject every override-related call with a
// `NotImplementedError`, so the components handle the rejection
// gracefully and surface a "backend pending" banner. The five
// scenarios here lock in that contract:
//
//   1. OverrideListView renders the empty state and renders 3 rows
//      after the store is seeded.
//   2. Clicking a row promotes the active id, which surfaces in the
//      editor tab.
//   3. OverrideEditorView calls the not-implemented wrapper on save
//      and surfaces the rejection as an inline error message.
//   4. OverrideApplyView renders a preview panel and keeps the
//      "Apply" button disabled when no preview/apply result has
//      landed yet (the mock never resolves).
//   5. The /overrides route renders the page shell directly via
//      `<MemoryRouter>`.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { useOverridesStore } from "../../../stores/overrides";
import type { Override, OverrideId } from "../../../types/override";

// Mock services/tauri so the override wrappers don't reach the real
// Tauri runtime in jsdom. The default behavior for the not-implemented
// wrappers is to reject — individual tests can override per-function.
vi.mock("../../../services/tauri", () => {
  const NotImplemented = (cmd: string) => {
    const err = new Error(`tauri command '${cmd}' is not implemented: deferred to v2.5.0`);
    (err as Error & { isNotImplemented?: boolean }).isNotImplemented = true;
    return err;
  };
  return {
    listOverrides: vi.fn(() => Promise.reject(NotImplemented("list_overrides"))),
    createOverride: vi.fn(() => Promise.reject(NotImplemented("create_override"))),
    updateOverride: vi.fn(() => Promise.reject(NotImplemented("update_override"))),
    deleteOverride: vi.fn(() => Promise.reject(NotImplemented("delete_override"))),
    previewOverride: vi.fn(() => Promise.reject(NotImplemented("preview_override"))),
    applyOverride: vi.fn(() => Promise.reject(NotImplemented("apply_override"))),
    isNotImplementedError: (err: unknown) =>
      typeof err === "object" &&
      err !== null &&
      (err as { isNotImplemented?: boolean }).isNotImplemented === true,
  };
});

// Components are imported AFTER the mock so the mock is in place.
import * as tauri from "../../../services/tauri";
import { OverrideListView } from "../OverrideListView";
import { OverrideEditorView } from "../OverrideEditorView";
import { OverrideApplyView } from "../OverrideApplyView";
import { Overrides } from "../index";

const mockedTauri = vi.mocked(tauri);

function makeOverride(overrides: Partial<Override> = {}): Override {
  return {
    id: overrides.id ?? cryptoRandomId(),
    name: overrides.name ?? "my-override",
    rawYAML: overrides.rawYAML ?? "# empty\n",
    createdAt: overrides.createdAt ?? "2026-06-07T08:00:00.000Z",
    updatedAt: overrides.updatedAt ?? "2026-06-07T08:00:00.000Z",
  };
}

function cryptoRandomId(): OverrideId {
  // crypto.randomUUID exists in modern jsdom; fall back if missing.
  const c = globalThis.crypto as Crypto | undefined;
  if (c && typeof c.randomUUID === "function") return c.randomUUID();
  return "id-" + Math.random().toString(36).slice(2);
}

function resetStore() {
  useOverridesStore.setState({
    overrides: [],
    activeId: null,
    loading: false,
    error: null,
  });
}

beforeEach(() => {
  resetStore();
});

afterEach(() => {
  cleanup();
  resetStore();
  vi.resetAllMocks();
  // Re-establish the default not-implemented rejection after resetAllMocks.
  mockedTauri.listOverrides.mockImplementation(() =>
    Promise.reject(notImpl("list_overrides")),
  );
  mockedTauri.createOverride.mockImplementation(() =>
    Promise.reject(notImpl("create_override")),
  );
  mockedTauri.updateOverride.mockImplementation(() =>
    Promise.reject(notImpl("update_override")),
  );
  mockedTauri.deleteOverride.mockImplementation(() =>
    Promise.reject(notImpl("delete_override")),
  );
  mockedTauri.previewOverride.mockImplementation(() =>
    Promise.reject(notImpl("preview_override")),
  );
  mockedTauri.applyOverride.mockImplementation(() =>
    Promise.reject(notImpl("apply_override")),
  );
});

function notImpl(cmd: string): Error {
  const err = new Error(`tauri command '${cmd}' is not implemented: deferred to v2.5.0`);
  (err as Error & { isNotImplemented?: boolean }).isNotImplemented = true;
  return err;
}

describe("OverrideListView — empty + populated states", () => {
  it("renders the empty state when the store has no overrides", async () => {
    render(
      <MemoryRouter>
        <OverrideListView />
      </MemoryRouter>,
    );

    // The IPC wrapper rejects with not-implemented, which is the
    // expected path during the UI-shell phase. The component must
    // not crash — we just see the empty-state shell.
    expect(await screen.findByTestId("override-list-view")).toBeInTheDocument();
    expect(screen.getByTestId("override-empty")).toBeInTheDocument();
    expect(screen.getByText("暂无覆盖配置")).toBeInTheDocument();
  });

  it("renders three rows when the store is seeded with three overrides", async () => {
    const seeded: Override[] = [
      makeOverride({ name: "alpha" }),
      makeOverride({ name: "beta" }),
      makeOverride({ name: "gamma" }),
    ];
    // Bypass the not-implemented wrapper — let the store fill directly.
    mockedTauri.listOverrides.mockResolvedValueOnce(seeded);

    render(
      <MemoryRouter>
        <OverrideListView />
      </MemoryRouter>,
    );

    await waitFor(() =>
      expect(useOverridesStore.getState().overrides).toHaveLength(3),
    );
    expect(screen.getByTestId("override-table")).toBeInTheDocument();
    const rows = screen.getAllByTestId("override-row");
    expect(rows).toHaveLength(3);
    expect(screen.getByText("alpha")).toBeInTheDocument();
    expect(screen.getByText("beta")).toBeInTheDocument();
    expect(screen.getByText("gamma")).toBeInTheDocument();
  });
});

describe("OverrideListView — row click promotes activeId", () => {
  it("clicking a row writes the row's id to activeId and surfaces it in the editor tab", async () => {
    const target = makeOverride({ name: "alpha" });
    const others = [makeOverride({ name: "beta" }), makeOverride({ name: "gamma" })];
    mockedTauri.listOverrides.mockResolvedValueOnce([target, ...others]);

    // Render the full page so the list click flips the active tab.
    render(
      <MemoryRouter initialEntries={["/overrides"]}>
        <Routes>
          <Route path="/overrides" element={<Overrides />} />
        </Routes>
      </MemoryRouter>,
    );

    await waitFor(() =>
      expect(useOverridesStore.getState().overrides).toHaveLength(3),
    );

    // The list tab is the default; click the row to set activeId.
    const targetRow = screen
      .getAllByTestId("override-row")
      .find((el) => el.getAttribute("data-override-id") === target.id);
    expect(targetRow).toBeDefined();
    fireEvent.click(targetRow!);

    // After click, the page should switch to the editor tab and the
    // store should reflect the new activeId. The list view also
    // surfaces the active id via a hidden data-testid span.
    await waitFor(() =>
      expect(useOverridesStore.getState().activeId).toBe(target.id),
    );
    expect(screen.getByTestId("override-editor-view")).toBeInTheDocument();
  });
});

describe("OverrideEditorView — save reaches the not-implemented wrapper", () => {
  it("calls the mock create wrapper and surfaces the rejection inline", async () => {
    render(
      <MemoryRouter>
        <OverrideEditorView createMode />
      </MemoryRouter>,
    );

    // Fill the name + ensure YAML has content (the seed template does).
    const nameInput = screen.getByTestId("override-name") as HTMLInputElement;
    fireEvent.change(nameInput, { target: { value: "my-new-override" } });

    const saveBtn = screen.getByTestId("override-save") as HTMLButtonElement;
    expect(saveBtn).not.toBeDisabled();
    fireEvent.click(saveBtn);

    // The wrapper is called with the right name + the seed YAML.
    await waitFor(() =>
      expect(mockedTauri.createOverride).toHaveBeenCalledTimes(1),
    );
    const callArgs = mockedTauri.createOverride.mock.calls[0];
    expect(callArgs[0]).toBe("my-new-override");
    expect(typeof callArgs[1]).toBe("string");
    expect((callArgs[1] as string).length).toBeGreaterThan(0);

    // And the rejection surfaces in the UI — the editor must NOT
    // crash, it must show the inline error.
    await waitFor(() =>
      expect(screen.getByTestId("override-save-error")).toBeInTheDocument(),
    );
    expect(
      screen.getByText(/后端尚未实现/),
    ).toBeInTheDocument();
  });
});

describe("OverrideApplyView — preview + disabled Apply when backend mock is in place", () => {
  it("renders the preview panel and disables the Apply button when no result has landed", async () => {
    const active = makeOverride({
      name: "to-apply",
      rawYAML: "# preview me\ndns:\n  enable: true\n",
    });
    useOverridesStore.setState({ overrides: [active], activeId: active.id });

    render(
      <MemoryRouter>
        <OverrideApplyView />
      </MemoryRouter>,
    );

    expect(screen.getByTestId("override-apply-view")).toBeInTheDocument();
    // The two side-by-side panels render, and the raw-YAML pane shows
    // the override body (the seed YAML's "preview me" comment is unique
    // enough to be unambiguous in this test).
    expect(screen.getByTestId("override-raw-section")).toBeInTheDocument();
    expect(screen.getByTestId("override-preview-section")).toBeInTheDocument();

    // Apply button is rendered and disabled because the wrapper
    // never resolves.
    const applyBtn = screen.getByTestId("override-apply") as HTMLButtonElement;
    expect(applyBtn).toBeInTheDocument();
    expect(applyBtn).toBeDisabled();
    expect(applyBtn.getAttribute("aria-disabled")).toBe("true");
  });
});

describe("/overrides route — direct deep-link renders the page", () => {
  it("renders the Overrides page shell at /overrides", () => {
    render(
      <MemoryRouter initialEntries={["/overrides"]}>
        <Routes>
          <Route path="/overrides" element={<Overrides />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(screen.getByTestId("overrides-page")).toBeInTheDocument();
    // Page-level H2 — the list subview also renders an H2 with the
    // same string, so we use the page testid as the anchor and just
    // assert the page is mounted (the subview render is exercised
    // by the other tests).
    const page = screen.getByTestId("overrides-page");
    expect(page).toHaveTextContent("配置覆盖");

    // The three tabs are all rendered.
    expect(screen.getByTestId("overrides-tab-list")).toBeInTheDocument();
    expect(screen.getByTestId("overrides-tab-editor")).toBeInTheDocument();
    expect(screen.getByTestId("overrides-tab-apply")).toBeInTheDocument();

    // The list tab is the default — list view shell is in the DOM.
    expect(screen.getByTestId("overrides-panel-list")).toBeInTheDocument();
    expect(screen.getByTestId("override-list-view")).toBeInTheDocument();
  });
});
