import { useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { listen } from '@tauri-apps/api/event';
import { onOpenUrl, getCurrent as getCurrentDeepLink } from '@tauri-apps/plugin-deep-link';
import { Layout } from './components/Layout';
import { Dashboard } from './components/Dashboard';
import { Proxies } from './components/Proxies';
import { Profiles } from './components/Profiles';
import { Rules } from './components/Rules';
import { Connections } from './components/Connections';
import { SettingsPage } from './components/Settings';
import { LogViewer } from './components/LogViewer';
import { LogbookView } from './components/Logbook';
import { useRiptideStore } from './stores/riptide';
import { modeCurrent, importProfileFromUrl, importShareUri, type AppMode } from './services/tauri';

interface ModeStateEvent {
  mode: AppMode;
  transitioning: boolean;
  error?: string | null;
}

interface SystemProxyDriftEvent {
  observed: { enable: boolean; host: string; port: number };
  expected: { enable: boolean; host: string; port: number };
  reapply_count: number;
  gave_up: boolean;
}

/**
 * Parse and dispatch a riptide:// URL. Supported shapes:
 *   riptide://import?url=<subscription_url>
 *   riptide://import?uri=<share_uri>
 */
async function handleDeepLink(rawUrl: string) {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    console.warn('Ignoring malformed deep link:', rawUrl);
    return;
  }
  if (url.protocol !== 'riptide:') return;

  const action = url.host || url.pathname.replace(/^\/*/, '');
  if (action === 'import') {
    const subUrl = url.searchParams.get('url');
    const shareUri = url.searchParams.get('uri');
    try {
      if (subUrl) {
        const profile = await importProfileFromUrl(subUrl);
        alert(`已通过 deep link 导入订阅：${profile.name}`);
      } else if (shareUri) {
        const profile = await importShareUri(shareUri);
        alert(`已通过 deep link 导入节点：${profile.name}`);
      } else {
        console.warn('riptide://import missing url= or uri= parameter');
      }
    } catch (e) {
      alert(`Deep link 导入失败：${e}`);
    }
  } else {
    console.warn('Unknown deep link action:', action);
  }
}

function App() {
  const theme = useRiptideStore((s) => s.theme);

  // Apply theme as a class on <html>. Tailwind picks it up via the `dark:`
  // variant when configured. Light-theme styling is a future pass; for now
  // `dark` is the only fully-styled variant and the default.
  useEffect(() => {
    const root = document.documentElement;
    const apply = (mode: 'light' | 'dark') => {
      root.classList.toggle('dark', mode === 'dark');
      root.classList.toggle('light', mode === 'light');
    };
    if (theme === 'system') {
      const mq = window.matchMedia('(prefers-color-scheme: dark)');
      apply(mq.matches ? 'dark' : 'light');
      const handler = (e: MediaQueryListEvent) => apply(e.matches ? 'dark' : 'light');
      mq.addEventListener('change', handler);
      return () => mq.removeEventListener('change', handler);
    }
    apply(theme);
  }, [theme]);

  useEffect(() => {
    // Reflect the initial backend mode before any user interaction.
    modeCurrent()
      .then((mode) => useRiptideStore.getState().setMode(mode))
      .catch((err) => console.warn('Failed to read current mode:', err));

    const unlistenMode = listen<ModeStateEvent>('mode_state', (event) => {
      const { mode, transitioning, error } = event.payload;
      const store = useRiptideStore.getState();
      store.setMode(mode);
      store.setModeTransitioning(transitioning);
      store.setModeError(error ?? null);
    });

    const unlistenDrift = listen<SystemProxyDriftEvent>('system_proxy_drift', (event) => {
      const { gave_up, reapply_count } = event.payload;
      if (gave_up) {
        console.warn(
          `System proxy drift could not be corrected after ${reapply_count} attempts.`,
        );
      } else {
        console.info(`System proxy drift restored (attempt ${reapply_count})`);
      }
    });

    // Global hotkey events forwarded by the Rust listener.
    const unlistenToggleProxy = listen('hotkey-toggle-proxy', async () => {
      const store = useRiptideStore.getState();
      const target = store.mode === 'off' ? 'system_proxy' : 'off';
      try {
        if (target === 'off') {
          await (await import('./services/tauri')).modeSwitchOff();
        } else {
          await (await import('./services/tauri')).modeSwitchToSystemProxy(7890, 7891);
        }
      } catch (e) {
        console.warn('Hotkey toggle-proxy failed:', e);
      }
    });

    const unlistenToggleMode = listen('hotkey-toggle-mode', async () => {
      const store = useRiptideStore.getState();
      // Cycle off → system_proxy → tun → off
      const next = store.mode === 'off' ? 'system_proxy' : store.mode === 'system_proxy' ? 'tun' : 'off';
      const t = await import('./services/tauri');
      try {
        if (next === 'off') await t.modeSwitchOff();
        else if (next === 'system_proxy') await t.modeSwitchToSystemProxy(7890, 7891);
        else await t.modeSwitchToTun();
      } catch (e) {
        console.warn('Hotkey toggle-mode failed:', e);
      }
    });

    // Deep link: handle the URL that launched the app (if any) + future ones.
    getCurrentDeepLink()
      .then((urls) => {
        if (urls && urls.length > 0) handleDeepLink(urls[0]);
      })
      .catch((err) => console.warn('Failed to read launch deep link:', err));
    const unlistenDeepLink = onOpenUrl((urls) => {
      if (urls.length > 0) handleDeepLink(urls[0]);
    });

    return () => {
      unlistenMode.then((fn) => fn()).catch(() => {});
      unlistenDrift.then((fn) => fn()).catch(() => {});
      unlistenDeepLink.then((fn) => fn()).catch(() => {});
      unlistenToggleProxy.then((fn) => fn()).catch(() => {});
      unlistenToggleMode.then((fn) => fn()).catch(() => {});
    };
  }, []);

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Layout />}>
          <Route index element={<Dashboard />} />
          <Route path="proxies" element={<Proxies />} />
          <Route path="profiles" element={<Profiles />} />
          <Route path="rules" element={<Rules />} />
          <Route path="connections" element={<Connections />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="logs" element={<LogViewer />} />
          <Route path="logbook" element={<LogbookView />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
