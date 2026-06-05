// Tests for src/i18n/index.ts
//
// i18n is a singleton initialized at module load. We exercise:
//   1. `changeLanguage` actually swaps the active language.
//   2. Missing keys fall back to the `fallbackLng: 'en-US'` value
//      rather than returning the key string unchanged.

import { beforeEach, describe, expect, it } from "vitest";
import i18next from "./index";
import enUS from "./locales/en-US.json";
import zhCN from "./locales/zh-CN.json";

beforeEach(async () => {
  // Make sure every test starts from a known language.
  await i18next.changeLanguage("en-US");
});

describe("i18n — changeLanguage", () => {
  it("switches the active language to zh-CN and back to en-US", async () => {
    // Default language is whatever was saved (or zh-CN fallback);
    // don't pin the assertion to the initial value, only to the
    // post-change value.
    await i18next.changeLanguage("zh-CN");
    expect(i18next.language).toBe("zh-CN");
    // `app.overview` differs between en-US ("Overview") and zh-CN
    // ("概览"), so it's a reliable asymmetric marker that the swap
    // actually took effect.
    expect(i18next.t("app.overview")).toBe(zhCN.app.overview);

    await i18next.changeLanguage("en-US");
    expect(i18next.language).toBe("en-US");
    expect(i18next.t("app.overview")).toBe(enUS.app.overview);
  });
});

describe("i18n — fallback to en-US", () => {
  it("falls back to en-US for keys missing in the active language", async () => {
    // Use a fresh, never-existed key. We add it ONLY to the en-US
    // bundle, then verify the active language (zh-CN) still resolves
    // it via the fallback chain.
    const FRESH_KEY = "test.fallback_marker_123";
    const FRESH_VALUE = "en-US-fallback-value";
    i18next.addResourceBundle(
      "en-US",
      "translation",
      { [FRESH_KEY]: FRESH_VALUE },
      true,
      true,
    );

    // Switch to zh-CN. The key is missing there — the resolution
    // chain should walk fallbackLng and return the en-US value.
    await i18next.changeLanguage("zh-CN");
    expect(i18next.t(FRESH_KEY)).toBe(FRESH_VALUE);

    // Sanity: same key resolves in en-US too.
    await i18next.changeLanguage("en-US");
    expect(i18next.t(FRESH_KEY)).toBe(FRESH_VALUE);

    // And a key that exists in NEITHER language is returned as the
    // key string by i18next, which is the documented behavior we
    // rely on across the UI for unfinished translations.
    expect(i18next.t("test.absent_key_456")).toBe("test.absent_key_456");
  });
});
