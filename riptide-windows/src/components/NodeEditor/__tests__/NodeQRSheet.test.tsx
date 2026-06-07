// Tests for src/components/NodeEditor/NodeQRSheet.tsx
//
// The sheet is a UI surface that turns ClashProxy objects into QR
// codes. We mock the tauri service so the JS layer owns the data
// plane and `qrcode` is exercised end-to-end against a real canvas in
// JSDOM.
//
// Coverage:
//   1. Renders an empty-state message when given no proxies.
//   2. Renders one card per proxy when given a non-empty list.
//   3. Copy All button writes all URIs to the clipboard.
//   4. Save All button triggers a download anchor for each URI.
//   5. Error path: when serializeProxyToUri throws, the error banner
//      surfaces the failure instead of crashing the sheet.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

// Mock the tauri IPC surface so the component doesn't try to talk to
// the Rust backend.
vi.mock("../../../services/tauri", () => ({
  listProfileProxies: vi.fn(),
  serializeProxyToUri: vi.fn(),
  serializeProxiesToUris: vi.fn(),
}));

// Mock the toast store so the click handlers don't blow up on the
// missing `setTimeout` from Zustand during teardown. We honor the
// selector pattern that the real store exposes.
vi.mock("../../../stores/toast", () => {
  const state = {
    addToast: vi.fn(),
    toasts: [],
    removeToast: vi.fn(),
  };
  const useToastStore = (selector?: (s: typeof state) => unknown) =>
    selector ? selector(state) : state;
  return { useToastStore };
});

import * as tauri from "../../../services/tauri";
import { NodeQRSheet } from "../NodeQRSheet";

const mockedTauri = vi.mocked(tauri);

const SAMPLE_PROXIES = [
  { name: "tokyo-1", type: "ss", server: "1.2.3.4", port: 8388, cipher: "aes-128-gcm", password: "p1" },
  { name: "sg-1", type: "vmess", server: "5.6.7.8", port: 443, uuid: "u-1" },
  { name: "us-1", type: "vless", server: "9.10.11.12", port: 443, uuid: "u-2" },
] as Array<tauri.ClashProxy>;

const SAMPLE_URIS = [
  "ss://YWVzLTEyOC1nY206cDFAMTkyLjE2OC4xLjE6ODM4OA#tokyo-1",
  "vmess://eyJ2IjoiMiIsInBzIjoic2ctMSIsImFkZCI6IjUuNi43LjgiLCJwb3J0Ijo0NDMsImlkIjoidS0xIn0=",
  "vless://dS0yQDk0LjE5OS4yMDAuMjM0OjQ0Mw#us-1",
];

beforeEach(() => {
  // The qrcode npm package draws on a real canvas. JSDOM doesn't
  // implement CanvasRenderingContext2D, so we stub just enough of the
  // API for `QRCode.toCanvas` to "succeed" and for the test to find
  // the canvas element in the DOM. The cast through `unknown` keeps
  // tsc happy — JSDOM's `getContext` is heavily overloaded and the
  // cast skips that.
  const stubCtx: unknown = {
    fillRect: () => {},
    clearRect: () => {},
    getImageData: () => ({ data: new Uint8ClampedArray(4) }),
    putImageData: () => {},
    createImageData: () => [],
    setTransform: () => {},
    drawImage: () => {},
    save: () => {},
    fillText: () => {},
    restore: () => {},
    beginPath: () => {},
    moveTo: () => {},
    lineTo: () => {},
    closePath: () => {},
    stroke: () => {},
    translate: () => {},
    scale: () => {},
    rotate: () => {},
    arc: () => {},
    fill: () => {},
    measureText: () => ({ width: 0 }),
    transform: () => {},
    rect: () => {},
    clip: () => {},
  };
  // Use `Object.defineProperty` to side-step JSDOM's overloaded
  // `getContext` / `toDataURL` signatures — tsc would otherwise
  // complain that the stub doesn't satisfy every overload.
  Object.defineProperty(HTMLCanvasElement.prototype, "getContext", {
    configurable: true,
    writable: true,
    value: function () {
      return stubCtx as CanvasRenderingContext2D;
    },
  });
  Object.defineProperty(HTMLCanvasElement.prototype, "toDataURL", {
    configurable: true,
    writable: true,
    value: function () {
      return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
    },
  });

  // navigator.clipboard isn't present in JSDOM by default; install a
  // spy-friendly stub.
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: { writeText: vi.fn().mockResolvedValue(undefined) },
  });
});

afterEach(() => {
  vi.resetAllMocks();
});

describe("NodeQRSheet — empty state", () => {
  it("shows 'No nodes to share' when the proxy list is empty", async () => {
    mockedTauri.listProfileProxies.mockResolvedValueOnce([]);

    render(
      <NodeQRSheet
        profileId="p1"
        profileName="empty-profile"
        onClose={() => {}}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId("node-qr-sheet-empty")).toBeInTheDocument();
    });
    expect(
      screen.getByTestId("node-qr-sheet-empty").textContent,
    ).toMatch(/no nodes to share/i);
    expect(mockedTauri.serializeProxyToUri).not.toHaveBeenCalled();
  });
});

describe("NodeQRSheet — populated state", () => {
  it("renders one QR card per proxy with a canvas", async () => {
    mockedTauri.listProfileProxies.mockResolvedValueOnce(SAMPLE_PROXIES);
    mockedTauri.serializeProxyToUri
      .mockResolvedValueOnce(SAMPLE_URIS[0])
      .mockResolvedValueOnce(SAMPLE_URIS[1])
      .mockResolvedValueOnce(SAMPLE_URIS[2]);

    render(
      <NodeQRSheet
        profileId="p1"
        profileName="demo"
        onClose={() => {}}
      />,
    );

    await waitFor(() => {
      expect(screen.getAllByTestId("node-qr-card")).toHaveLength(3);
    });
    // 3 cards → 3 canvases
    const canvases = screen.getAllByTestId("node-qr-canvas");
    expect(canvases).toHaveLength(3);
    // And the data-attr on each card round-trips the proxy name
    const cards = screen.getAllByTestId("node-qr-card");
    expect(cards[0].getAttribute("data-node-name")).toBe("tokyo-1");
    expect(cards[1].getAttribute("data-node-name")).toBe("sg-1");
    expect(cards[2].getAttribute("data-node-name")).toBe("us-1");
  });
});

describe("NodeQRSheet — copy all", () => {
  it("writes every URI to the clipboard, one per line, on click", async () => {
    mockedTauri.listProfileProxies.mockResolvedValueOnce(SAMPLE_PROXIES);
    mockedTauri.serializeProxyToUri
      .mockResolvedValueOnce(SAMPLE_URIS[0])
      .mockResolvedValueOnce(SAMPLE_URIS[1])
      .mockResolvedValueOnce(SAMPLE_URIS[2]);

    render(
      <NodeQRSheet
        profileId="p1"
        profileName="demo"
        onClose={() => {}}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId("node-qr-copy-all")).toBeInTheDocument();
    });

    const copyAll = screen.getByTestId("node-qr-copy-all");
    fireEvent.click(copyAll);

    await waitFor(() => {
      expect(navigator.clipboard.writeText).toHaveBeenCalledTimes(1);
    });
    const clipboardCall = vi.mocked(navigator.clipboard.writeText).mock
      .calls[0][0] as string;
    // Each URI on its own line, in the same order as the input list.
    expect(clipboardCall).toBe(SAMPLE_URIS.join("\n"));
  });
});

describe("NodeQRSheet — save all", () => {
  it("triggers a download anchor for every URI on click", async () => {
    mockedTauri.listProfileProxies.mockResolvedValueOnce(SAMPLE_PROXIES);
    mockedTauri.serializeProxyToUri
      .mockResolvedValueOnce(SAMPLE_URIS[0])
      .mockResolvedValueOnce(SAMPLE_URIS[1])
      .mockResolvedValueOnce(SAMPLE_URIS[2]);

    // Spy on the DOM API we use to fire downloads.
    const clickSpy = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});
    const appendSpy = vi.spyOn(document.body, "appendChild");

    render(
      <NodeQRSheet
        profileId="p1"
        profileName="demo"
        onClose={() => {}}
      />,
    );

    await waitFor(() => {
      expect(screen.getByTestId("node-qr-save-all")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByTestId("node-qr-save-all"));

    await waitFor(() => {
      expect(clickSpy).toHaveBeenCalledTimes(3);
    });
    // Each anchor's download attribute is the (sanitized) proxy name
    // followed by ".png" — we can at least confirm three distinct
    // .png suffixes were used.
    const downloads = appendSpy.mock.calls
      .map((c) => c[0] as HTMLAnchorElement)
      .filter((a) => a.tagName === "A" && a.download.endsWith(".png"));
    expect(downloads).toHaveLength(3);
    const names = downloads.map((a) => a.download).sort();
    expect(names).toEqual(
      ["sg-1.png", "tokyo-1.png", "us-1.png"],
    );
  });
});

describe("NodeQRSheet — error path", () => {
  it("surfaces a serialize error inline instead of crashing", async () => {
    mockedTauri.listProfileProxies.mockResolvedValueOnce(SAMPLE_PROXIES);
    mockedTauri.serializeProxyToUri
      .mockResolvedValueOnce(SAMPLE_URIS[0])
      .mockRejectedValueOnce(new Error("missing uuid"))
      .mockResolvedValueOnce(SAMPLE_URIS[2]);

    render(
      <NodeQRSheet
        profileId="p1"
        profileName="demo"
        onClose={() => {}}
      />,
    );

    // Two of three cards render. The failing one is rendered with an
    // error chip rather than a canvas.
    await waitFor(() => {
      expect(screen.getAllByTestId("node-qr-card")).toHaveLength(3);
    });
    expect(screen.getAllByTestId("node-qr-canvas")).toHaveLength(2);
    expect(screen.getAllByTestId("node-qr-card-error")).toHaveLength(1);

    // The error banner appears with the failing node's name.
    const banner = await screen.findByTestId("node-qr-sheet-error");
    expect(banner.textContent).toMatch(/sg-1/);
    expect(banner.textContent).toMatch(/missing uuid/);

    // The two working entries should still be copyable.
    const copyAll = screen.getByTestId("node-qr-copy-all") as HTMLButtonElement;
    expect(copyAll).not.toBeDisabled();
    fireEvent.click(copyAll);
    await waitFor(() => {
      expect(navigator.clipboard.writeText).toHaveBeenCalledTimes(1);
    });
    // Only the two working URIs are written — the failed one is skipped.
    const clipboardCall = vi.mocked(navigator.clipboard.writeText).mock
      .calls[0][0] as string;
    expect(clipboardCall).toBe([SAMPLE_URIS[0], SAMPLE_URIS[2]].join("\n"));
  });
});
