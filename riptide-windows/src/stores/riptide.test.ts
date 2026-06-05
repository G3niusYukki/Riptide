// Tests for src/stores/riptide.ts
//
// The Riptide Zustand store is the single source of truth for global
// state (mode, profiles, proxies, traffic, settings). It uses the
// `persist` middleware, so we must clear `localStorage` between tests
// to avoid cross-test leakage.

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { useRiptideStore } from "./riptide";

function resetStore() {
  // Drop any persisted slices so each test starts from the
  // documented initial state in riptide.ts.
  useRiptideStore.setState({
    isRunning: false,
    activeProfile: null,
    systemProxyEnabled: false,
    tunModeEnabled: false,
    autoStart: false,
    silentStart: false,
    theme: "dark",
    profiles: [],
    proxies: [],
    proxyGroups: [],
    selectedProxy: null,
    connections: [],
    traffic: { upload: 0, download: 0, uploadSpeed: 0, downloadSpeed: 0 },
    mode: "off",
    modeTransitioning: false,
    modeError: null,
  });
  localStorage.removeItem("riptide-storage");
}

beforeEach(() => {
  resetStore();
});

afterEach(() => {
  resetStore();
});

describe("stores/riptide — initial state", () => {
  it("starts with mode='off' and no error / no transition", () => {
    const s = useRiptideStore.getState();
    expect(s.mode).toBe("off");
    expect(s.modeTransitioning).toBe(false);
    expect(s.modeError).toBeNull();
    expect(s.isRunning).toBe(false);
    expect(s.systemProxyEnabled).toBe(false);
    expect(s.tunModeEnabled).toBe(false);
  });
});

describe("stores/riptide — mode coordinator actions", () => {
  it("setMode updates mode and keeps legacy flags in sync", () => {
    const { setMode } = useRiptideStore.getState();

    setMode("system_proxy");
    let s = useRiptideStore.getState();
    expect(s.mode).toBe("system_proxy");
    expect(s.isRunning).toBe(true);
    expect(s.systemProxyEnabled).toBe(true);
    expect(s.tunModeEnabled).toBe(false);

    setMode("tun");
    s = useRiptideStore.getState();
    expect(s.mode).toBe("tun");
    expect(s.isRunning).toBe(true);
    expect(s.systemProxyEnabled).toBe(false);
    expect(s.tunModeEnabled).toBe(true);

    setMode("off");
    s = useRiptideStore.getState();
    expect(s.mode).toBe("off");
    expect(s.isRunning).toBe(false);
    expect(s.systemProxyEnabled).toBe(false);
    expect(s.tunModeEnabled).toBe(false);
  });

  it("setModeTransitioning flips the boolean without touching other state", () => {
    const { setMode, setModeTransitioning } = useRiptideStore.getState();

    setMode("tun");
    setModeTransitioning(true);
    let s = useRiptideStore.getState();
    expect(s.modeTransitioning).toBe(true);
    expect(s.mode).toBe("tun");
    expect(s.modeError).toBeNull();

    setModeTransitioning(false);
    s = useRiptideStore.getState();
    expect(s.modeTransitioning).toBe(false);
  });

  it("setModeError stores and clears the error string", () => {
    const { setModeError } = useRiptideStore.getState();

    setModeError("mihomo exited unexpectedly");
    let s = useRiptideStore.getState();
    expect(s.modeError).toBe("mihomo exited unexpectedly");

    setModeError(null);
    s = useRiptideStore.getState();
    expect(s.modeError).toBeNull();
  });
});
