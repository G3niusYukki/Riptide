import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useRiptideStore } from '../../stores/riptide';
import { Settings, Globe, Shield } from 'lucide-react';
import * as tauri from '../../services/tauri';

export function SettingsPage() {
  const { t } = useTranslation();
  const {
    systemProxyEnabled, setSystemProxyEnabled,
    tunModeEnabled, setTunModeEnabled,
    autoStart, setAutoStart,
    silentStart, setSilentStart,
  } = useRiptideStore();
  const [httpPort, setHttpPort] = useState(7890);
  const [socksPort, setSocksPort] = useState(7891);
  const [serviceInstalling, setServiceInstalling] = useState(false);

  const toggleSystemProxy = async () => {
    try {
      if (systemProxyEnabled) {
        await tauri.disableSystemProxy();
        setSystemProxyEnabled(false);
      } else {
        await tauri.enableSystemProxy(httpPort, socksPort);
        setSystemProxyEnabled(true);
      }
    } catch (error) {
      console.error('Failed to toggle system proxy:', error);
    }
  };

  const toggleTunMode = async () => {
    try {
      if (tunModeEnabled) {
        await tauri.stopTunService();
        setTunModeEnabled(false);
      } else {
        await tauri.startTunService();
        setTunModeEnabled(true);
      }
    } catch (error) {
      console.error('Failed to toggle TUN mode:', error);
    }
  };

  const installTunService = async () => {
    setServiceInstalling(true);
    try {
      await tauri.installTunService();
      alert('TUN 服务安装成功');
    } catch (error) {
      console.error('Failed to install TUN service:', error);
      alert('TUN 服务安装失败');
    } finally {
      setServiceInstalling(false);
    }
  };

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold text-slate-100">设置</h2>

      {/* General Settings */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <Settings size={20} className="text-blue-400" />
          <h3 className="text-lg font-semibold text-slate-100">常规设置</h3>
        </div>
        
        <div className="space-y-4">
          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">{t('settings.autoStart')}</p>
              <p className="text-xs text-slate-500">{t('settings.autoStartDesc')}</p>
            </div>
            <button
              onClick={() => setAutoStart(!autoStart)}
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 ${autoStart ? 'bg-blue-600' : 'bg-slate-700'}`}
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
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 ${silentStart ? 'bg-blue-600' : 'bg-slate-700'}`}
            >
              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${silentStart ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          </div>
        </div>
      </div>

      {/* System Proxy Settings */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <Globe size={20} className="text-emerald-400" />
          <h3 className="text-lg font-semibold text-slate-100">系统代理</h3>
        </div>
        
        <div className="space-y-4">
          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">启用系统代理</p>
              <p className="text-xs text-slate-500">自动配置 Windows 系统代理设置</p>
            </div>
            <button 
              onClick={toggleSystemProxy}
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${systemProxyEnabled ? 'bg-emerald-600' : 'bg-slate-700'}`}
            >
              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${systemProxyEnabled ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          </div>
          
          <div className="grid grid-cols-2 gap-3 pt-3">
            <div>
              <label className="block text-xs text-slate-400 mb-1.5">HTTP 端口</label>
              <input
                type="number"
                value={httpPort}
                onChange={(e) => setHttpPort(Number(e.target.value))}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all"
              />
            </div>
            <div>
              <label className="block text-xs text-slate-400 mb-1.5">SOCKS 端口</label>
              <input
                type="number"
                value={socksPort}
                onChange={(e) => setSocksPort(Number(e.target.value))}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30 transition-all"
              />
            </div>
          </div>
        </div>
      </div>

      {/* TUN Settings */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <Shield size={20} className="text-blue-400" />
          <h3 className="text-lg font-semibold text-slate-100">TUN 模式</h3>
        </div>
        
        <div className="space-y-4">
          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">安装 TUN 服务</p>
              <p className="text-xs text-slate-500">需要管理员权限安装 Windows 服务</p>
            </div>
            <button
              onClick={installTunService}
              disabled={serviceInstalling}
              className="px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50"
            >
              {serviceInstalling ? '安装中...' : '安装服务'}
            </button>
          </div>

          <div className="flex items-center justify-between py-2">
            <div>
              <p className="text-slate-200 font-medium text-sm">启用 TUN 模式</p>
              <p className="text-xs text-slate-500">系统级流量拦截（需要先安装服务）</p>
            </div>
            <button
              onClick={toggleTunMode}
              className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 ${tunModeEnabled ? 'bg-blue-600' : 'bg-slate-700'}`}
            >
              <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${tunModeEnabled ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          </div>
        </div>
      </div>

      {/* About */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <h3 className="text-lg font-semibold text-slate-100 mb-3">{t('settings.about')}</h3>
        <div className="text-xs text-slate-400 space-y-1.5">
          <p className="font-medium text-slate-300">Riptide v1.1.0</p>
          <p>{t('settings.aboutText')}</p>
          <p className="text-slate-600">© 2026 Riptide Team</p>
          <button
            onClick={async () => {
              try {
                const info = await tauri.checkUpdate();
                if (info.update_available) {
                  alert(`发现新版本 ${info.latest_version}（当前 ${info.current_version}）\n下载: ${info.release_url}`);
                } else {
                  alert(`已是最新版本 (${info.current_version})`);
                }
              } catch (e) {
                console.error('Update check failed:', e);
              }
            }}
            className="mt-2 px-3 py-1 bg-slate-800 hover:bg-slate-700 rounded text-slate-400 hover:text-slate-200 transition-colors text-xs"
          >
            检查更新
          </button>
        </div>
      </div>
    </div>
  );
}
