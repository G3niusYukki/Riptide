import { useEffect, useMemo } from 'react';
import { BrowserRouter, Routes, Route, useNavigate } from 'react-router-dom';
import { listen } from '@tauri-apps/api/event';
import { onOpenUrl, getCurrent as getCurrentDeepLink } from '@tauri-apps/plugin-deep-link';
import { Layout } from './components/Layout';
import { Dashboard } from './components/Dashboard';
import { Proxies } from './components/Proxies';
import { Profiles } from './components/Profiles';
import { Config } from './components/Config';
import { Traffic } from './components/Traffic';
import { Rules } from './components/Rules';
import { SceneEditorView } from './components/Rules/SceneEditorView';
import { ScriptEditorView } from './components/Rules/ScriptEditorView';
import { RuleMarketView } from './components/Rules/RuleMarketView';
import { Connections } from './components/Connections';
import { SettingsPage } from './components/Settings';
import { LogViewer } from './components/LogViewer';
import { LogbookView } from './components/Logbook';
import { Overrides } from './components/Overrides';
import { useRiptideStore } from './stores/riptide';
import { useTheme } from './hooks/useTheme';
import { useNotification } from './hooks/useNotification';
import { useToastStore } from './stores/toast';
import { modeCurrent, importProfileFromUrl, importShareUri, type AppMode } from './services/tauri';
import { parseDeepLink, dispatchDeepLink, type DeepLinkDispatchDeps } from './lib/deepLinks';

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
 * Inner App body — must live inside `<BrowserRouter>` so `useNavigate`
 * resolves to the router's navigate function. The outer `App` component
 * is the one exposed to `main.tsx` and only sets up routing.
 */
function AppBody() {
  // C10.1: theme management now lives in `useTheme`, which writes the
  // resolved value to <html data-theme="...">. tokens.css keys off
  // [data-theme="light"] / :root, so the previous class-toggle path
  // (which silently had no effect) is replaced here.
  useTheme();
  // C11: wire the Rust NotificationDispatcher's 5 `notify:*` events to
  // the in-app toast store. The hook auto-subscribes on mount and
  // auto-cleans on unmount; we just hand it the toast callback.
  const addToast = useToastStore((s) => s.addToast);
  useNotification(addToast);
  const navigate = useNavigate();

  // Stable dependency bundle for the deep-link dispatcher. `navigate` is
  // referentially stable across renders, but rebuilding the object would
  // still cause the deep-link useEffect to re-run — useMemo is cheap
  // insurance.
  const dispatchDeps = useMemo<DeepLinkDispatchDeps>(
    () => ({
      navigate,
      importProfileFromUrl: (url: string) => importProfileFromUrl(url),
      importShareUri: (uri: string) => importShareUri(uri),
      modeSwitchOff: () =>
        import('./services/tauri').then((t) => t.modeSwitchOff()),
      modeSwitchToSystemProxy: (httpPort?: number, socksPort?: number) =>
        import('./services/tauri').then((t) =>
          t.modeSwitchToSystemProxy(httpPort ?? 7890, socksPort ?? 7891),
        ),
      modeSwitchToTun: () =>
        import('./services/tauri').then((t) => t.modeSwitchToTun()),
      alert: (message: string) => window.alert(message),
    }),
    [navigate],
  );

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
        const t = await import('./services/tauri');
        if (target === 'off') {
          await t.modeSwitchOff();
        } else {
          await t.modeSwitchToSystemProxy(7890, 7891);
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

    // Deep link: handle the URL that launched the app (if any) + future
    // ones. The parser + dispatcher live in `lib/deepLinks.ts` — single
    // source of truth for the riptide:// scheme, exercised by 8 unit
    // tests in `lib/__tests__/deepLinks.test.ts`.
    const handleDeepLink = async (rawUrl: string) => {
      const cmd = parseDeepLink(rawUrl);
      if (cmd.type === 'noop') {
        console.warn('Ignoring deep link:', cmd.reason);
        return;
      }
      await dispatchDeepLink(cmd, dispatchDeps);
    };

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
  }, [dispatchDeps]);

  return (
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="proxies" element={<Proxies />} />
        <Route path="profiles" element={<Profiles />} />
        <Route path="config" element={<Config />} />
        <Route path="traffic" element={<Traffic />} />
        <Route path="rules" element={<Rules />} />
        <Route path="scenes" element={<SceneEditorView />} />
        <Route path="script-editor" element={<ScriptEditorView />} />
        <Route path="rule-market" element={<RuleMarketView />} />
        <Route path="connections" element={<Connections />} />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="logs" element={<LogViewer />} />
        <Route path="logbook" element={<LogbookView />} />
        <Route path="overrides" element={<Overrides />} />
      </Route>
    </Routes>
  );
}

function App() {
  return (
    <BrowserRouter>
      <AppBody />
    </BrowserRouter>
  );
}

export default App;
