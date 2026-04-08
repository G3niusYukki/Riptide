import { useRiptideStore } from '../../stores/riptide';
import { Power, Shield, Globe } from 'lucide-react';
import * as tauri from '../../services/tauri';

export function Header() {
  const { isRunning, systemProxyEnabled, tunModeEnabled, setIsRunning } = useRiptideStore();

  const toggleProxy = async () => {
    try {
      if (isRunning) {
        await tauri.stopProxy();
        setIsRunning(false);
      } else {
        await tauri.startProxy();
        setIsRunning(true);
      }
    } catch (error) {
      console.error('Failed to toggle proxy:', error);
    }
  };

  return (
    <header className="h-16 border-b border-slate-800 bg-slate-900/50 flex items-center justify-between px-6">
      <h1 className="text-lg font-semibold text-slate-100">Riptide</h1>
      
      <div className="flex items-center gap-4">
        {/* Status indicators */}
        <div className="flex items-center gap-3 text-sm">
          {systemProxyEnabled && (
            <span className="flex items-center gap-1.5 text-emerald-400">
              <Globe size={14} />
              系统代理
            </span>
          )}
          {tunModeEnabled && (
            <span className="flex items-center gap-1.5 text-blue-400">
              <Shield size={14} />
              TUN 模式
            </span>
          )}
        </div>

        {/* Power button */}
        <button
          onClick={toggleProxy}
          className={`
            flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-all
            ${isRunning
              ? 'bg-red-600/20 text-red-400 hover:bg-red-600/30 border border-red-600/30'
              : 'bg-emerald-600/20 text-emerald-400 hover:bg-emerald-600/30 border border-emerald-600/30'
            }
          `}
        >
          <Power size={18} />
          {isRunning ? '停止' : '启动'}
        </button>
      </div>
    </header>
  );
}
