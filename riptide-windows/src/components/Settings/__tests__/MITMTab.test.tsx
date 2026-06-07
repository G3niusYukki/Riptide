// Tests for src/components/Settings/MITMTab.tsx
//
// Phase C7.3 / C7.4 — the MITM tab is a sandbox UI. The 5 `tauri.mitm*`
// wrappers reject with `not_implemented`, so we only assert on the
// rendered shape: experimental warning, CA card, host whitelist
// table/buttons, and the master enable switch. All action controls
// must render as `disabled` to make the experimental state obvious.
//
// 4 tests, mirroring the Phase C7.3 / C7.4 acceptance checklist:
//   1. experimental warning banner (🟡 + v2.5.0 hint)
//   2. CA card: status badge + install button disabled
//   3. host whitelist: table + 3 disabled CRUD buttons (add/edit/delete)
//   4. master enable switch: rendered but disabled

import { describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MITMTab } from '../MITMTab';

// Mock the tauri service so the 5 mitm wrappers don't reach the real
// Tauri IPC. The mocks reject on every call, mirroring the future
// behaviour of the Rust `mitm` module (which doesn't exist yet).
vi.mock('../../../services/tauri', () => ({
  getMitmConfig: vi.fn(() => Promise.reject(new Error('not_implemented'))),
  setMitmConfig: vi.fn(() => Promise.reject(new Error('not_implemented'))),
  getCaState: vi.fn(() => Promise.reject(new Error('not_implemented'))),
  installCa: vi.fn(() => Promise.reject(new Error('not_implemented'))),
  uninstallCa: vi.fn(() => Promise.reject(new Error('not_implemented'))),
}));

describe('Settings/MITMTab — experimental banner', () => {
  it('renders the 🟡 experimental warning with the v2.5.0 hint', () => {
    render(<MITMTab />);
    const warning = screen.getByTestId('mitm-experimental-warning');
    expect(warning).toBeInTheDocument();
    // The warning text must mention the deferred-version marker so
    // users can plan around the roadmap.
    expect(warning.textContent).toMatch(/experimental/i);
    expect(warning.textContent).toMatch(/v2\.5\.0/);
    // The 🟡 status badge must be present to mirror the macOS
    // MITMSettingsView's experimental callout.
    expect(warning.textContent).toMatch(/🟡/);
  });
});

describe('Settings/MITMTab — CA card', () => {
  it('renders the CA status badge and a disabled install button', async () => {
    render(<MITMTab />);
    // Status badge is always rendered (initial state: not installed).
    const status = screen.getByTestId('mitm-ca-status');
    expect(status).toBeInTheDocument();
    // The component logs the rejection via console.debug; we just
    // ensure no unhandled error escaped by waiting a tick.
    await waitFor(() => {
      expect(status).toBeInTheDocument();
    });

    const install = screen.getByTestId('mitm-ca-install');
    const uninstall = screen.getByTestId('mitm-ca-uninstall');
    expect(install).toBeInTheDocument();
    expect(uninstall).toBeInTheDocument();
    // Both buttons must be disabled because the backend is a stub.
    expect(install).toBeDisabled();
    expect(uninstall).toBeDisabled();
  });
});

describe('Settings/MITMTab — host whitelist CRUD', () => {
  it('renders the table plus three disabled CRUD buttons (add / edit / delete)', () => {
    render(<MITMTab />);
    // The table is always rendered (so the user can see the schema)
    // even when the host list is empty. An empty placeholder row
    // indicates the "no rules yet" state.
    const table = screen.getByTestId('mitm-host-table');
    expect(table).toBeInTheDocument();
    expect(screen.getByTestId('mitm-host-empty-row')).toBeInTheDocument();

    // All three CRUD controls are present and disabled.
    const add = screen.getByTestId('mitm-host-add');
    const edit = screen.getByTestId('mitm-host-edit');
    const del = screen.getByTestId('mitm-host-delete');

    expect(add).toBeInTheDocument();
    expect(edit).toBeInTheDocument();
    expect(del).toBeInTheDocument();
    expect(add).toBeDisabled();
    expect(edit).toBeDisabled();
    expect(del).toBeDisabled();
  });
});

describe('Settings/MITMTab — master enable switch', () => {
  it('renders the enable switch as disabled', () => {
    render(<MITMTab />);
    const swatch = screen.getByTestId('mitm-enable-switch');
    expect(swatch).toBeInTheDocument();
    // The toggle label carries a non-interactive visual state
    // (cursor-not-allowed + reduced opacity) so the disabled state
    // is visible even to users who don't notice the underlying
    // <input disabled> attribute. We assert both.
    expect(swatch.className).toMatch(/cursor-not-allowed/);
    const input = swatch.querySelector('input[type="checkbox"]');
    expect(input).not.toBeNull();
    expect(input).toBeDisabled();
  });
});
