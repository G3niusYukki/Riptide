import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { NetworkTab } from './NetworkTab';
import { DnsTab } from './DnsTab';
import { SyncTab } from './SyncTab';
import { AssetsTab } from './AssetsTab';
import { RecoveryTab } from './RecoveryTab';
import { useRiptideStore } from '../../stores/riptide';
import { SUPPORTED_LANGUAGES } from '../../i18n';
import i18n from '../../i18n';
import * as tauri from '../../services/tauri';

type Tab = 'network' | 'dns' | 'sync' | 'assets' | 'recovery' | 'diagnostics' | 'about';

export function SettingsPage() {
  const { t } = useTranslation();
  const [active, setActive] = useState<Tab>('network');
  const theme = useRiptideStore((s) => s.theme);
  const setTheme = useRiptideStore((s) => s.setTheme);
  const [lang, setLang] = useState(i18n.language);

  const handleLangChange = (code: string) => {
    setLang(code);
    localStorage.setItem('riptide-lang', code);
    void i18n.changeLanguage(code);
  };

  const tabs: { id: Tab; label: string }[] = [
    { id: 'network', label: '网络' },
    { id: 'dns', label: 'DNS' },
    { id: 'sync', label: '同步' },
    { id: 'assets', label: '资源' },
    { id: 'recovery', label: '恢复' },
    { id: 'diagnostics', label: '诊断' },
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
      {active === 'sync' && <SyncTab />}
      {active === 'assets' && <AssetsTab />}
      {active === 'recovery' && <RecoveryTab />}
      {active === 'diagnostics' && <RecoveryTab showDiagnostics />}
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
              <p className="font-medium text-slate-300">Riptide v2.0.0</p>
              <p>{t('settings.aboutText')}</p>
              <p className="text-slate-600">© 2026 Riptide Team</p>
              <button
                onClick={async () => {
                  try {
                    const info = await tauri.checkUpdate();
                    if (info.update_available) {
                      const ok = confirm(
                        `发现新版本 ${info.latest_version}（当前 ${info.current_version}）\n打开下载页？`,
                      );
                      if (ok) {
                        // Use tauri-plugin-opener to open in default browser.
                        const { openUrl } = await import('@tauri-apps/plugin-opener');
                        await openUrl(info.release_url);
                      }
                    } else {
                      alert(`已是最新版本 (${info.current_version})`);
                    }
                  } catch (e) {
                    console.error('Update check failed:', e);
                    alert(`检查失败：${e}`);
                  }
                }}
                className="mt-2 px-3 py-1 bg-slate-800 hover:bg-slate-700 rounded text-slate-400 hover:text-slate-200 transition-colors text-xs"
              >
                检查更新
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
