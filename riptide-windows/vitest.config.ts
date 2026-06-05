/// <reference types="vitest" />
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// vitest configuration for riptide-windows frontend tests.
// Mirrors vite.config.ts plugins so that the test environment
// resolves modules the same way as the dev server. Test files
// live next to source as `*.test.ts` / `*.test.tsx`.
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: false,
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    css: false,
    restoreMocks: true,
    clearMocks: true,
  },
});
