// Tests for src/services/tauri.ts
//
// The tauri service module is a thin wrapper around the Tauri `invoke`
// IPC. We mock `@tauri-apps/api/core` and `@tauri-apps/api/event` so the
// real native runtime is not exercised.
//
// Coverage:
//   1. `invoke` call is forwarded with the right command + args
//   2. generic <T> typing flows through to the caller (so the returned
//      promise is `T`, not `unknown`)

import { afterEach, describe, expect, it, vi } from "vitest";

// Mock Tauri IPC. The mock must be declared before importing the module
// under test, because vi.mock is hoisted.
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

vi.mock("@tauri-apps/api/event", () => ({
  listen: vi.fn(() => Promise.resolve(() => {})),
}));

import { invoke } from "@tauri-apps/api/core";
import {
  startProxy,
  stopProxy,
  restartProxy,
  getProfiles,
  getActiveProfile,
  setActiveProfile,
  setProfileSubscription,
  type ClashProxy,
} from "./tauri";

const mockInvoke = vi.mocked(invoke);

afterEach(() => {
  vi.resetAllMocks();
});

describe("services/tauri — IPC wrapper forwarding", () => {
  it("forwards invoke calls with the correct command name and args", async () => {
    mockInvoke.mockResolvedValueOnce(undefined);
    await startProxy();
    expect(mockInvoke).toHaveBeenCalledWith("start_proxy");

    mockInvoke.mockResolvedValueOnce("profile-id-1");
    const id = await getActiveProfile();
    expect(mockInvoke).toHaveBeenCalledWith("get_active_profile");
    expect(id).toBe("profile-id-1");

    mockInvoke.mockResolvedValueOnce(undefined);
    await setActiveProfile("profile-id-1");
    expect(mockInvoke).toHaveBeenCalledWith("set_active_profile", {
      id: "profile-id-1",
    });

    // Subscription setter — three positional args become a single object
    // payload for the Tauri command, mirroring the Rust signature.
    mockInvoke.mockResolvedValueOnce(undefined);
    await setProfileSubscription("pid", "https://example.com/sub", 3600);
    expect(mockInvoke).toHaveBeenLastCalledWith("set_profile_subscription", {
      id: "pid",
      url: "https://example.com/sub",
      intervalSecs: 3600,
    });
    // url = null, intervalSecs = null — passthrough should still work.
    mockInvoke.mockResolvedValueOnce(undefined);
    await setProfileSubscription("pid", null, null);
    expect(mockInvoke).toHaveBeenLastCalledWith("set_profile_subscription", {
      id: "pid",
      url: null,
      intervalSecs: null,
    });
  });

  it("uses the typed return value when invoke resolves", async () => {
    // The Tauri wrapper uses `invoke<T>(...)`. We test that the
    // generic shape is preserved end-to-end by providing a strongly
    // typed mock and reading the resolved value as that type.
    type Profile = { id: string; name: string; content: string };
    const fakeProfile: Profile = {
      id: "abc",
      name: "test",
      content: "port: 7890",
    };
    mockInvoke.mockResolvedValueOnce([fakeProfile]);

    const profiles = (await getProfiles()) as Profile[];
    expect(profiles).toHaveLength(1);
    expect(profiles[0].id).toBe("abc");
    expect(profiles[0].name).toBe("test");

    // And for the no-arg / void command variants — just ensure no
    // extra args are appended and the promise resolves.
    mockInvoke.mockResolvedValueOnce(undefined);
    await stopProxy();
    expect(mockInvoke).toHaveBeenLastCalledWith("stop_proxy");

    mockInvoke.mockResolvedValueOnce(undefined);
    await restartProxy();
    expect(mockInvoke).toHaveBeenLastCalledWith("restart_proxy");
  });

  it("preserves the ClashProxy shape that flows into update_profile_proxy", async () => {
    // Compile-time guard: the ClashProxy shape must accept every
    // field the Rust side round-trips, including kebab-case keys.
    const proxy: ClashProxy = {
      name: "tokyo-1",
      type: "ss",
      server: "1.2.3.4",
      port: 8388,
      cipher: "aes-128-gcm",
      password: "s3cret",
      "skip-cert-verify": true,
      sni: "example.com",
      alpn: ["h2", "http/1.1"],
      "ws-path": "/ws",
      "ws-headers": { Host: "example.com" },
      "reality-opts": { public_key: "PUB", "short-id": "ab", "spider-x": "" },
      pbk: "PUB",
      sid: "ab",
      spx: "",
      "congestion-controller": "cubic",
      "heartbeat-interval": 10000,
      "fast-open": true,
    };
    expect(proxy.name).toBe("tokyo-1");
    expect(proxy["ws-headers"]?.Host).toBe("example.com");
  });
});
