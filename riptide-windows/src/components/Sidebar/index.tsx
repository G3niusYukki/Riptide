import { Link, useLocation } from 'react-router-dom';
import {
  Activity,
  Globe,
  FileText,
  Settings,
  Shield,
  Terminal,
  Zap,
} from 'lucide-react';

const navItems = [
  { path: '/', icon: Activity, label: '概览' },
  { path: '/proxies', icon: Globe, label: '代理' },
  { path: '/profiles', icon: FileText, label: '配置' },
  { path: '/rules', icon: Shield, label: '规则' },
  { path: '/connections', icon: Zap, label: '连接' },
  { path: '/logs', icon: Terminal, label: '日志' },
  { path: '/settings', icon: Settings, label: '设置' },
];

export function Sidebar() {
  const location = useLocation();

  return (
    <aside className="w-16 bg-slate-900 border-r border-slate-800 flex flex-col items-center py-4 select-none">
      <div className="mb-6">
        <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center shadow-lg">
          <span className="text-white font-bold text-lg">R</span>
        </div>
      </div>
      
      <nav className="flex-1 flex flex-col gap-1">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = location.pathname === item.path;
          
          return (
            <Link
              key={item.path}
              to={item.path}
              className={`
                w-12 h-12 rounded-lg flex items-center justify-center transition-all duration-150
                ${isActive 
                  ? 'bg-blue-600/20 text-blue-400 shadow-sm' 
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/70'
                }
              `}
              title={item.label}
            >
              <Icon size={22} strokeWidth={isActive ? 2 : 1.5} />
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
