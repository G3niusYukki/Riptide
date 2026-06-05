// Vitest global setup: extends `expect` with @testing-library/jest-dom
// matchers (toBeInTheDocument, toHaveTextContent, etc.) and forces a
// clean JSDOM environment per test file.
import "@testing-library/jest-dom/vitest";
import { afterEach } from "vitest";
import { cleanup } from "@testing-library/react";

afterEach(() => {
  cleanup();
});
