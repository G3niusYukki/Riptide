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
    <header className="h-14 border-b border-slate-800 bg-slate-900/50 flex items-center justify-between px-5 select-none">
      <h1 className="text-base font-semibold text-slate-100">Riptide</h1>
      
      <div className="flex items-center gap-3">
        {/* Status indicators */}
        <div className="flex items-center gap-2 text-xs">
          {systemProxyEnabled && (
            <span className="flex items-center gap-1 text-emerald-400 bg-emerald-500/10 px-2 py-1 rounded-full">
              <Globe size={12} />
              系统代理
            </span>
          )}
          {tunModeEnabled && (
            <span className="flex items-center gap-1 text-blue-400 bg-blue-500/10 px-2 py-1 rounded-full">
              <Shield size={12} />
              TUN
            </span>
          )}
        </div>

        {/* Power button */}
        <button
          onClick={toggleProxy}
          className={`
            flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all focus:outline-none focus:ring-2 focus:ring-offset-1 focus:ring-offset-slate-900
            ${isRunning
              ? 'bg-red-600/20 text-red-400 hover:bg-red-600/30 border border-red-600/30 focus:ring-red-500/50'
              : 'bg-emerald-600/20 text-emerald-400 hover:bg-emerald-600/30 border border-emerald-600/30 focus:ring-emerald-500/50'
            }
          `}
        >
          <Power size={14} />
          {isRunning ? '停止' : '启动'}
        </button>
      </div>
    </header>
  );
}
