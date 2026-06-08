// Vitest global setup: extends `expect` with @testing-library/jest-dom
// matchers (toBeInTheDocument, toHaveTextContent, etc.) and forces a
// clean JSDOM environment per test file.
//
// localStorage polyfill must come FIRST — several modules (i18n/index.ts,
// zustand persist middleware) access localStorage at import time, before
// any test code runs.  Node's jsdom environment does not always provide it.
if (typeof globalThis.localStorage === 'undefined' || globalThis.localStorage === null) {
  const store = new Map<string, string>();
  globalThis.localStorage = {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => { store.set(key, String(value)); },
    removeItem: (key: string) => { store.delete(key); },
    clear: () => { store.clear(); },
    get length() { return store.size; },
    key: (index: number) => [...store.keys()][index] ?? null,
  };
}

import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

afterEach(() => {
  cleanup();
});
