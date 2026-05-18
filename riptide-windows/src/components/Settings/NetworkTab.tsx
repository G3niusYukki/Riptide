import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useRiptideStore } from '../../stores/riptide';
import { Settings as SettingsIcon, Power, Shield, Loader2 } from 'lucide-react';
import { enable as enableAutostart, disable as disableAutostart, isEnabled as isAutostartEnabled } from '@tauri-apps/plugin-autostart';
import * as tauri from '../../services/tauri';

/** Network tab — mode selector, port config, general settings, TUN service mgmt. */
export function NetworkTab() {
  const { t } = useTranslation();
  const {
    autoStart, setAutoStart,
    silentStart, setSilentStart,
    mode, modeTransitioning, modeError,
  } = useRiptideStore();
  const [httpPort, setHttpPort] = useState(7890);
  const [socksPort, setSocksPort] = useState(7891);
  const [serviceInstalling, setServiceInstalling] = useState(false);
  const [serviceStatus, setServiceStatus] = useState<tauri.TunServiceStatus>('not_installed');

  useEffect(() => {
    const refresh = () => tauri.getTunServiceStatus().then(setServiceStatus).catch(() => {});
    refresh();
    const id = setInterval(refresh, 3000);

    // Sync autostart toggle with the actual registry entry so the UI doesn't
    // drift after an uninstall/reinstall.
    isAutostartEnabled()
      .then((enabled) => useRiptideStore.getState().setAutoStart(enabled))
      .catch(console.warn);

    return () => clearInterval(id);
  }, []);

  const handleAutoStart = async (next: boolean) => {
    try {
      if (next) {
        await enableAutostart();
      } else {
        await disableAutostart();
      }
      setAutoStart(next);
    } catch (error) {
      alert(`自启动设置失败：${error}`);
    }
  };

  const handleMode = async (target: tauri.AppMode) => {
    if (mode === target || modeTransitioning) return;
    try {
      if (target === 'off') {
        await tauri.modeSwitchOff();
      } else if (target === 'system_proxy') {
        await tauri.modeSwitchToSystemProxy(httpPort, socksPort);
      } else {
        if (serviceStatus === 'stopped') {
          await tauri.startTunService();
        }
        await tauri.modeSwitchToTun();
      }
    } catch (error) {
      console.error('Mode switch failed:', error);
    }
  };

  const installTunService = async () => {
    setServiceInstalling(true);
    try {
      await tauri.installTunService();
      const next = await tauri.getTunServiceStatus();
      setServiceStatus(next);
    } catch (error) {
      alert(`TUN 服务安装失败：${error}`);
    } finally {
      setServiceInstalling(false);
    }
  };

  const uninstallTunService = async () => {
    try {
      await tauri.uninstallTunService();
      const next = await tauri.getTunServiceStatus();
      setServiceStatus(next);
    } catch (error) {
      alert(`TUN 服务卸载失败：${error}`);
    }
  };

  const serviceInstalled = serviceStatus !== 'not_installed' && serviceStatus !== 'unknown';

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-3">
            <Power size={20} className="text-emerald-400" />
            <h3 className="text-lg font-semibold text-slate-100">运行模式</h3>
          </div>
          {modeTransitioning && (
            <div className="flex items-center gap-2 text-xs text-slate-400">
              <Loader2 size={14} className="animate-spin" />
              切换中…
            </div>
          )}
        </div>

        <div className="grid grid-cols-3 gap-2">
          {(['off', 'system_proxy', 'tun'] as const).map((m) => {
            const label = m === 'off' ? '关闭' : m === 'system_proxy' ? '系统代理' : 'TUN';
            const active = mode === m;
            return (
              <button
                key={m}
                onClick={() => handleMode(m)}
                disabled={modeTransitioning}
                className={`px-4 py-3 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 ${
                  active ? 'bg-blue-600 text-white' : 'bg-slate-800 hover:bg-slate-700 text-slate-200'
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>

        {modeError && <p className="mt-3 text-xs text-red-400">错误：{modeError}</p>}

        <div className="grid grid-cols-2 gap-3 pt-4 mt-4 border-t border-slate-800">
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">HTTP 端口</label>
            <input
              type="number"
              value={httpPort}
              onChange={(e) => setHttpPort(Number(e.target.value))}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
            />
          </div>
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">SOCKS 端口</label>
            <input
              type="number"
              value={socksPort}
              onChange={(e) => setSocksPort(Number(e.target.value))}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
            />
          </div>
        </div>
      </div>

      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <SettingsIcon size={20} className="text-blue-400" />
          <h3 className="text-lg font-semibold text-slate-100">常规设置</h3>
        </div>

        <div className="space-y-4">
          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">{t('settings.autoStart')}</p>
              <p className="text-xs text-slate-500">{t('settings.autoStartDesc')}</p>
            </div>
            <button
              onClick={() => handleAutoStart(!autoStart)}
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${autoStart ? 'bg-blue-600' : 'bg-slate-700'}`}
            >
              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${autoStart ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          </div>

          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">静默启动</p>
              <p className="text-xs text-slate-500">启动时最小化到托盘</p>
            </div>
            <button
              onClick={() => setSilentStart(!silentStart)}
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${silentStart ? 'bg-blue-600' : 'bg-slate-700'}`}
            >
              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${silentStart ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          </div>
        </div>
      </div>

      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <Shield size={20} className="text-blue-400" />
          <h3 className="text-lg font-semibold text-slate-100">TUN Windows 服务</h3>
        </div>

        <div className="flex items-center justify-between py-2">
          <div>
            <p className="text-slate-200 font-medium text-sm">
              状态：<span className="text-slate-400">{serviceStatus}</span>
            </p>
            <p className="text-xs text-slate-500">
              安装服务后，TUN 模式可在不提权 UI 的前提下运行。
            </p>
          </div>
          {serviceInstalled ? (
            <button
              onClick={uninstallTunService}
              className="px-3 py-1.5 bg-red-600/20 hover:bg-red-600/30 text-red-400 rounded-lg text-sm font-medium transition-colors"
            >
              卸载服务
            </button>
          ) : (
            <button
              onClick={installTunService}
              disabled={serviceInstalling}
              className="px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            >
              {serviceInstalling ? '安装中…' : '安装服务'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
