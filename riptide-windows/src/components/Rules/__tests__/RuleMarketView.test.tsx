import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { RuleMarketView } from "../RuleMarketView";

// Mock the toast store so addToast calls don't fail in isolation.
// Zustand's useToastStore accepts a selector — we must apply it.
const addToastMock = vi.fn();
vi.mock("../../../stores/toast", () => ({
  useToastStore: (selector: (s: Record<string, unknown>) => unknown) =>
    selector({ addToast: addToastMock }),
}));

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  cleanup();
});

function renderWithRouter(ui: React.ReactNode) {
  return render(
    <MemoryRouter initialEntries={["/rule-market"]}>
      <Routes>
        <Route path="/rule-market" element={ui} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("RuleMarketView", () => {
  it("renders the rule-set list", () => {
    renderWithRouter(<RuleMarketView />);

    const list = screen.getByTestId("rule-market-list");
    const items = screen.getAllByTestId("rule-market-item");
    expect(list).toBeInTheDocument();
    expect(items.length).toBe(4);
  });

  it("each rule-set has an install button", () => {
    renderWithRouter(<RuleMarketView />);

    const items = screen.getAllByTestId("rule-market-item");
    for (const item of items) {
      const btn = item.querySelector('[data-testid="rule-install-btn"]');
      expect(btn).toBeInTheDocument();
    }
  });

  it("clicking install shows a toast notification", () => {
    renderWithRouter(<RuleMarketView />);

    const btns = screen.getAllByTestId("rule-install-btn");
    fireEvent.click(btns[0]);

    expect(addToastMock).toHaveBeenCalledTimes(1);
    // The i18n key is passed to addToast; the resolved string depends on
    // the locale loaded in the test env. We assert on the key pattern.
    expect(addToastMock).toHaveBeenCalledWith(
      expect.stringContaining("installPending"),
      "info",
    );

    // After clicking, the button is replaced by an installed badge.
    const badge = screen.getAllByTestId("rule-installed-badge");
    expect(badge.length).toBe(1);
  });

  it("empty state renders correctly", () => {
    renderWithRouter(<RuleMarketView bundledRuleSets={[]} />);

    const empty = screen.getByTestId("rule-market-empty");
    expect(empty).toBeInTheDocument();

    // No install buttons or items should be present.
    expect(screen.queryAllByTestId("rule-market-item")).toHaveLength(0);
    expect(screen.queryAllByTestId("rule-install-btn")).toHaveLength(0);
  });
});
