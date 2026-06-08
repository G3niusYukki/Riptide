import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { getVersion } from '@tauri-apps/api/app';
import { NetworkTab } from './NetworkTab';
import { DnsTab } from './DnsTab';
import { SyncTab } from './SyncTab';
import { AssetsTab } from './AssetsTab';
import { RecoveryTab } from './RecoveryTab';
import { RewriteTab } from './RewriteTab';
import { AppearanceTab } from './AppearanceTab';
import { GatewayTab } from './GatewayTab';
import { MITMTab } from './MITMTab';
import { useRiptideStore } from '../../stores/riptide';
import { SUPPORTED_LANGUAGES } from '../../i18n';
import i18n from '../../i18n';
import * as tauri from '../../services/tauri';

// Phase A 1.1 removed the placeholder 'diagnostics' tab. The full
// diagnostics view (Logbook) now lives at /logbook in its own route
// (Phase C C1) and is linked from the Sidebar; Settings keeps the
// recovery/runtime knobs that belong alongside the other configuration
// surfaces.
type Tab = 'network' | 'dns' | 'rewrite' | 'gateway' | 'sync' | 'assets' | 'recovery' | 'mitm' | 'appearance' | 'about';

export function SettingsPage() {
  const { t } = useTranslation();
  const [active, setActive] = useState<Tab>('network');
  const theme = useRiptideStore((s) => s.theme);
  const setTheme = useRiptideStore((s) => s.setTheme);
  const [lang, setLang] = useState(i18n.language);
  const [updateStatus, setUpdateStatus] = useState<
    | { state: 'idle' }
    | { state: 'checking' }
    | { state: 'up-to-date' }
    | { state: 'available'; version: string; url: string }
    | { state: 'error'; message: string; notConfigured?: boolean }
  >({ state: 'idle' });
  const [installing, setInstalling] = useState(false);
  const handleLangChange = (code: string) => {
    setLang(code);
    localStorage.setItem('riptide-lang', code);
    void i18n.changeLanguage(code);
  };

  // Read the real app version from Tauri (sourced from tauri.conf.json /
  // Cargo.toml at build time). The version is fixed for a given binary, so a
  // single mount-time fetch is enough. We fall back to an em-dash if the call
  // somehow fails (e.g. running outside the Tauri runtime in dev tests).
  const [appVersion, setAppVersion] = useState<string>('—');
  useEffect(() => {
    let cancelled = false;
    void getVersion()
      .then((v) => {
        if (!cancelled) setAppVersion(v);
      })
      .catch((e) => {
        // Surface to console so a future regression isn't silent, but don't
        // block the About panel — the em-dash is informative enough.
        console.error('Failed to read app version:', e);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const tabs: { id: Tab; label: string }[] = [
    { id: 'network', label: '网络' },
    { id: 'dns', label: 'DNS' },
    { id: 'rewrite', label: '重写' },
    { id: 'gateway', label: '网关' },
    { id: 'sync', label: '同步' },
    { id: 'assets', label: '资源' },
    { id: 'recovery', label: '恢复' },
    { id: 'mitm', label: 'MITM' },
    { id: 'appearance', label: '外观' },
    { id: 'about', label: '关于' },
  ];

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold text-slate-100">设置</h2>

      <div className="flex items-center gap-1 border-b border-slate-800">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActive(tab.id)}
            className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
              active === tab.id
                ? 'border-blue-500 text-blue-400'
                : 'border-transparent text-slate-400 hover:text-slate-200'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {active === 'network' && <NetworkTab />}
      {active === 'dns' && <DnsTab />}
      {active === 'rewrite' && <RewriteTab />}
      {active === 'gateway' && <GatewayTab />}
      {active === 'sync' && <SyncTab />}
      {active === 'assets' && <AssetsTab />}
      {active === 'recovery' && <RecoveryTab />}
      {active === 'mitm' && <MITMTab />}
      {active === 'appearance' && <AppearanceTab />}
      {active === 'about' && (
        <div className="space-y-3">
          <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
            <h3 className="text-lg font-semibold text-slate-100 mb-3">外观</h3>
            <div className="space-y-3">
              <label className="flex items-center justify-between text-sm">
                <span className="text-slate-300">主题</span>
                <select
                  value={theme}
                  onChange={(e) => setTheme(e.target.value as 'light' | 'dark' | 'system')}
                  className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500"
                >
                  <option value="system">跟随系统</option>
                  <option value="dark">深色</option>
                  <option value="light">浅色</option>
                </select>
              </label>
              <label className="flex items-center justify-between text-sm">
                <span className="text-slate-300">语言</span>
                <select
                  value={lang}
                  onChange={(e) => handleLangChange(e.target.value)}
                  className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500"
                >
                  {SUPPORTED_LANGUAGES.map((l) => (
                    <option key={l.code} value={l.code}>
                      {l.label}
                    </option>
                  ))}
                </select>
              </label>
            </div>
          </div>

          <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
            <h3 className="text-lg font-semibold text-slate-100 mb-3">{t('settings.about')}</h3>
            <div className="text-xs text-slate-400 space-y-1.5">
              <p className="font-medium text-slate-300">Riptide v{appVersion}</p>
              <p>{t('settings.aboutText')}</p>
              <p className="text-slate-600">© 2026 Riptide Team</p>
            </div>
            {/* Update section */}
            <div className="mt-4 pt-3 border-t border-slate-800 space-y-2">
              <button
                onClick={async () => {
                  setUpdateStatus({ state: 'checking' });
                  try {
                    const info = await tauri.checkUpdate();
                    if (info.update_available) {
                      setUpdateStatus({
                        state: 'available',
                        version: info.latest_version,
                        url: info.release_url,
                      });
                    } else {
                      setUpdateStatus({ state: 'up-to-date' });
                    }
                  } catch (e) {
                    const msg = e instanceof Error ? e.message : String(e);
                    const notConfigured =
                      msg.includes('pubkey') ||
                      msg.includes('signature') ||
                      msg.includes('REPLACE_WITH_YOUR_PUBLIC_KEY');
                    setUpdateStatus({
                      state: 'error',
                      message: msg,
                      notConfigured,
                    });
                  }
                }}
                disabled={updateStatus.state === 'checking'}
                className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-50 rounded text-slate-300 hover:text-slate-100 transition-colors text-xs"
              >
                {updateStatus.state === 'checking' ? '检查中…' : '检查更新'}
              </button>
              {updateStatus.state === 'up-to-date' && (
                <p className="text-xs text-green-400">已是最新版本 (v{appVersion})</p>
              )}
              {updateStatus.state === 'available' && (
                <div className="flex items-center gap-3">
                  <p className="text-xs text-blue-400">
                    新版本可用：v{updateStatus.version}
                  </p>
                  <button
                    onClick={async () => {
                      setInstalling(true);
                      try {
                        const { openUrl } = await import('@tauri-apps/plugin-opener');
                        await openUrl(updateStatus.url);
                      } catch (e) {
                        console.error('Failed to open download URL:', e);
                      } finally {
                        setInstalling(false);
                      }
                    }}
                    disabled={installing}
                    className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 rounded text-white text-xs transition-colors"
                  >
                    {installing ? '打开中…' : '下载并安装'}
                  </button>
                </div>
              )}
              {updateStatus.state === 'error' && (
                <p className="text-xs text-amber-400">
                  {updateStatus.notConfigured
                    ? '自动更新尚未配置'
                    : `检查失败：${updateStatus.message}`}
                </p>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
