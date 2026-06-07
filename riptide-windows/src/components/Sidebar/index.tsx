import { Link, useLocation } from 'react-router-dom';
import {
  Activity,
  Globe,
  FileText,
  Settings,
  Shield,
  Terminal,
  Zap,
  BookText,
} from 'lucide-react';
import { useRiptideStore } from '../../stores/riptide';

const navItems = [
  { path: '/', icon: Activity, label: '概览' },
  { path: '/proxies', icon: Globe, label: '代理' },
  { path: '/profiles', icon: FileText, label: '配置' },
  { path: '/rules', icon: Shield, label: '规则' },
  { path: '/connections', icon: Zap, label: '连接' },
  { path: '/logs', icon: Terminal, label: '日志' },
  { path: '/logbook', icon: BookText, label: 'Logbook' },
  { path: '/settings', icon: Settings, label: '设置' },
];

const MODE_LABEL: Record<string, string> = {
  off: '已停止',
  system_proxy: '系统代理',
  tun: 'TUN 模式',
};

export function Sidebar() {
  const location = useLocation();
  const mode = useRiptideStore((s) => s.mode);
  const modeTransitioning = useRiptideStore((s) => s.modeTransitioning);

  return (
    <aside className="w-52 bg-gradient-to-b from-slate-900 to-slate-950 border-r border-slate-800/80 flex flex-col select-none">
      <div className="px-5 py-5 border-b border-slate-800/80">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 bg-gradient-to-br from-blue-500 to-blue-700 rounded-lg flex items-center justify-center shadow-md shadow-blue-900/40 ring-1 ring-blue-400/20">
            <span className="text-white font-bold text-base">R</span>
          </div>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-slate-100 tracking-tight leading-tight">
              Riptide
            </p>
            <p className="text-[10px] text-slate-500 leading-tight">v2.0.0</p>
          </div>
        </div>
      </div>

      <nav className="flex-1 px-2 py-3 space-y-0.5">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive =
            item.path === '/'
              ? location.pathname === '/'
              : location.pathname.startsWith(item.path);
          return (
            <Link
              key={item.path}
              to={item.path}
              className={`
                group flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-all duration-150
                ${
                  isActive
                    ? 'bg-blue-600/15 text-blue-300 shadow-sm shadow-blue-950/30'
                    : 'text-slate-400 hover:text-slate-100 hover:bg-slate-800/60'
                }
              `}
            >
              <Icon
                size={17}
                strokeWidth={isActive ? 2.2 : 1.7}
                className={isActive ? 'text-blue-400' : 'text-slate-500 group-hover:text-slate-300'}
              />
              <span className="flex-1">{item.label}</span>
              {isActive && (
                <span className="w-1 h-4 bg-blue-400 rounded-full shadow shadow-blue-500/50" />
              )}
            </Link>
          );
        })}
      </nav>

      <div className="px-3 py-3 border-t border-slate-800/80">
        <div className="flex items-center gap-2 px-2 py-1.5 rounded-md bg-slate-800/40">
          <span
            className={`w-2 h-2 rounded-full ${
              modeTransitioning
                ? 'bg-amber-400 animate-pulse'
                : mode === 'off'
                ? 'bg-slate-500'
                : 'bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.6)]'
            }`}
          />
          <span className="text-[11px] text-slate-300 truncate">
            {modeTransitioning ? '切换中…' : MODE_LABEL[mode] ?? mode}
          </span>
        </div>
      </div>
    </aside>
  );
}
