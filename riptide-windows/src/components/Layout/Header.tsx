import { useRiptideStore } from '../../stores/riptide';
import { Power, Shield, Globe, Zap } from 'lucide-react';
import * as tauri from '../../services/tauri';

export function Header() {
  const isRunning = useRiptideStore((s) => s.isRunning);
  const systemProxyEnabled = useRiptideStore((s) => s.systemProxyEnabled);
  const tunModeEnabled = useRiptideStore((s) => s.tunModeEnabled);
  const setIsRunning = useRiptideStore((s) => s.setIsRunning);

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
    <header className="h-14 border-b border-slate-800/70 bg-slate-900/40 backdrop-blur-sm flex items-center justify-between px-5 select-none">
      <div className="flex items-center gap-2 text-xs text-slate-500">
        <Zap size={13} className="text-slate-600" />
        <span>本地代理</span>
        <span className="font-mono text-slate-400">127.0.0.1:7890</span>
      </div>

      <div className="flex items-center gap-2">
        {systemProxyEnabled && (
          <span className="flex items-center gap-1.5 text-[11px] text-emerald-300 bg-emerald-500/10 border border-emerald-500/20 px-2.5 py-1 rounded-full">
            <Globe size={11} />
            系统代理
          </span>
        )}
        {tunModeEnabled && (
          <span className="flex items-center gap-1.5 text-[11px] text-blue-300 bg-blue-500/10 border border-blue-500/20 px-2.5 py-1 rounded-full">
            <Shield size={11} />
            TUN
          </span>
        )}

        <button
          onClick={toggleProxy}
          className={`
            flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all
            border focus:outline-none focus:ring-2 focus:ring-offset-1 focus:ring-offset-slate-900
            ${
              isRunning
                ? 'bg-red-500/15 text-red-300 hover:bg-red-500/25 border-red-500/30 focus:ring-red-500/50'
                : 'bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25 border-emerald-500/30 focus:ring-emerald-500/50'
            }
          `}
        >
          <Power size={13} />
          {isRunning ? '停止' : '启动'}
        </button>
      </div>
    </header>
  );
}
