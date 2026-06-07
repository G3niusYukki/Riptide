// Tests for src/lib/deepLinks.ts
//
// Covers the 6 riptide:// actions + the noop fallback (C4 deliverable
// contract — 8 tests total). The parser and dispatcher are tested as
// separate units so each can be exercised without coupling to the
// other. The dispatcher receives its tauri / navigate side effects as
// injected mocks, which is exactly the shape the production wiring in
// App.tsx builds at runtime.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  parseDeepLink,
  dispatchDeepLink,
  handleDeepLink,
  type DeepLinkDispatchDeps,
} from "../deepLinks";

interface MockDeps {
  deps: DeepLinkDispatchDeps;
  navigate: ReturnType<typeof vi.fn>;
  importProfileFromUrl: ReturnType<typeof vi.fn>;
  importShareUri: ReturnType<typeof vi.fn>;
  modeSwitchOff: ReturnType<typeof vi.fn>;
  modeSwitchToSystemProxy: ReturnType<typeof vi.fn>;
  modeSwitchToTun: ReturnType<typeof vi.fn>;
  alert: ReturnType<typeof vi.fn>;
}

function makeDeps(overrides: Partial<DeepLinkDispatchDeps> = {}): MockDeps {
  const navigate = vi.fn();
  const importProfileFromUrl = vi.fn().mockResolvedValue({ name: "sub-profile" });
  const importShareUri = vi.fn().mockResolvedValue({ name: "node-profile" });
  const modeSwitchOff = vi.fn().mockResolvedValue(undefined);
  const modeSwitchToSystemProxy = vi.fn().mockResolvedValue(undefined);
  const modeSwitchToTun = vi.fn().mockResolvedValue(undefined);
  const alert = vi.fn();
  const deps: DeepLinkDispatchDeps = {
    navigate,
    importProfileFromUrl,
    importShareUri,
    modeSwitchOff,
    modeSwitchToSystemProxy,
    modeSwitchToTun,
    alert,
    ...overrides,
  };
  return {
    deps,
    navigate,
    importProfileFromUrl,
    importShareUri,
    modeSwitchOff,
    modeSwitchToSystemProxy,
    modeSwitchToTun,
    alert,
  };
}

describe("lib/deepLinks — parseDeepLink", () => {
  it("recognises riptide://import?url= as import-profile-from-url", () => {
    const cmd = parseDeepLink("riptide://import?url=https://sub.example.com/x");
    expect(cmd).toEqual({ type: "import-profile-from-url", url: "https://sub.example.com/x" });
  });

  it("recognises riptide://import?uri= as import-share-uri", () => {
    const cmd = parseDeepLink("riptide://import?uri=ss%3A%2F%2Fabc");
    expect(cmd).toEqual({ type: "import-share-uri", uri: "ss://abc" });
  });

  it("recognises riptide://switch-group?group= as switch-group", () => {
    const cmd = parseDeepLink("riptide://switch-group?group=Proxy");
    expect(cmd).toEqual({ type: "switch-group", group: "Proxy" });
  });

  it("recognises riptide://select-node?group=&node= as select-node", () => {
    const cmd = parseDeepLink("riptide://select-node?group=Proxy&node=HK1");
    expect(cmd).toEqual({ type: "select-node", group: "Proxy", node: "HK1" });
  });

  it("recognises riptide://mode?value=off|system_proxy|tun as mode", () => {
    expect(parseDeepLink("riptide://mode?value=off")).toEqual({ type: "mode", value: "off" });
    expect(parseDeepLink("riptide://mode?value=system_proxy")).toEqual({
      type: "mode",
      value: "system_proxy",
    });
    expect(parseDeepLink("riptide://mode?value=tun")).toEqual({ type: "mode", value: "tun" });
  });

  it("returns noop for unknown actions without throwing", () => {
    expect(() => parseDeepLink("riptide://unknown")).not.toThrow();
    const cmd = parseDeepLink("riptide://unknown");
    expect(cmd.type).toBe("noop");
  });

  it("returns noop for malformed URLs", () => {
    expect(parseDeepLink("not a url").type).toBe("noop");
    expect(parseDeepLink("").type).toBe("noop");
    expect(parseDeepLink("https://example.com").type).toBe("noop");
  });
});

describe("lib/deepLinks — dispatchDeepLink (8 acceptance cases)", () => {
  let m: MockDeps;

  beforeEach(() => {
    m = makeDeps();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("1. riptide://import?url=<subscription> calls importProfileFromUrl", async () => {
    const cmd = parseDeepLink("riptide://import?url=https://sub.example.com/foo");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.importProfileFromUrl).toHaveBeenCalledTimes(1);
    expect(m.importProfileFromUrl).toHaveBeenCalledWith("https://sub.example.com/foo");
    expect(m.importShareUri).not.toHaveBeenCalled();
    expect(m.navigate).not.toHaveBeenCalled();
    expect(m.alert).toHaveBeenCalledTimes(1);
  });

  it("2. riptide://import?uri=<share> calls importShareUri", async () => {
    const cmd = parseDeepLink("riptide://import?uri=vmess%3A%2F%2Fxyz");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.importShareUri).toHaveBeenCalledTimes(1);
    expect(m.importShareUri).toHaveBeenCalledWith("vmess://xyz");
    expect(m.importProfileFromUrl).not.toHaveBeenCalled();
    expect(m.navigate).not.toHaveBeenCalled();
  });

  it("3. riptide://switch-group?group=Proxy navigates to /proxies?group=Proxy", async () => {
    const cmd = parseDeepLink("riptide://switch-group?group=Proxy");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.navigate).toHaveBeenCalledTimes(1);
    expect(m.navigate).toHaveBeenCalledWith("/proxies?group=Proxy");
    expect(m.modeSwitchOff).not.toHaveBeenCalled();
    expect(m.importProfileFromUrl).not.toHaveBeenCalled();
  });

  it("4. riptide://select-node?group=Proxy&node=HK1 navigates with both params", async () => {
    const cmd = parseDeepLink("riptide://select-node?group=Proxy&node=HK1");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.navigate).toHaveBeenCalledTimes(1);
    expect(m.navigate).toHaveBeenCalledWith("/proxies?group=Proxy&node=HK1");
  });

  it("5. riptide://mode?value=off calls modeSwitchOff", async () => {
    const cmd = parseDeepLink("riptide://mode?value=off");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.modeSwitchOff).toHaveBeenCalledTimes(1);
    expect(m.modeSwitchToSystemProxy).not.toHaveBeenCalled();
    expect(m.modeSwitchToTun).not.toHaveBeenCalled();
    expect(m.navigate).not.toHaveBeenCalled();
  });

  it("6. riptide://mode?value=system_proxy calls modeSwitchToSystemProxy", async () => {
    const cmd = parseDeepLink("riptide://mode?value=system_proxy");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.modeSwitchToSystemProxy).toHaveBeenCalledTimes(1);
    expect(m.modeSwitchOff).not.toHaveBeenCalled();
    expect(m.modeSwitchToTun).not.toHaveBeenCalled();
  });

  it("7. riptide://mode?value=tun calls modeSwitchToTun", async () => {
    const cmd = parseDeepLink("riptide://mode?value=tun");
    const actioned = await dispatchDeepLink(cmd, m.deps);
    expect(actioned).toBe(true);
    expect(m.modeSwitchToTun).toHaveBeenCalledTimes(1);
    expect(m.modeSwitchOff).not.toHaveBeenCalled();
    expect(m.modeSwitchToSystemProxy).not.toHaveBeenCalled();
  });

  it("8. riptide://unknown is a no-op (no throw, no side effects)", async () => {
    const cmd = parseDeepLink("riptide://unknown");
    let actioned: boolean | undefined;
    let threw: unknown = undefined;
    try {
      actioned = await dispatchDeepLink(cmd, m.deps);
    } catch (e) {
      threw = e;
    }
    expect(threw).toBeUndefined();
    expect(actioned).toBe(false);
    expect(m.navigate).not.toHaveBeenCalled();
    expect(m.importProfileFromUrl).not.toHaveBeenCalled();
    expect(m.importShareUri).not.toHaveBeenCalled();
    expect(m.modeSwitchOff).not.toHaveBeenCalled();
    expect(m.modeSwitchToSystemProxy).not.toHaveBeenCalled();
    expect(m.modeSwitchToTun).not.toHaveBeenCalled();
    expect(m.alert).not.toHaveBeenCalled();
  });
});

describe("lib/deepLinks — handleDeepLink convenience wrapper", () => {
  it("parses + dispatches in a single call", async () => {
    const m = makeDeps();
    const actioned = await handleDeepLink("riptide://mode?value=tun", m.deps);
    expect(actioned).toBe(true);
    expect(m.modeSwitchToTun).toHaveBeenCalledTimes(1);
  });

  it("returns false for malformed links without throwing", async () => {
    const m = makeDeps();
    const actioned = await handleDeepLink("not-a-url", m.deps);
    expect(actioned).toBe(false);
  });
});
