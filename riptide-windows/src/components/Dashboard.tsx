import { useTraffic } from '../hooks/useTraffic';
import { useRiptideStore } from '../stores/riptide';
import { Activity, ArrowDown, ArrowUp, Clock, Cloud, Wifi } from 'lucide-react';
import { TrafficChart } from './Dashboard/TrafficChart';
import { useMemo } from 'react';

export function Dashboard() {
  const { isRunning, traffic, activeProfile, profiles, connections } = useRiptideStore();
  const { isError } = useTraffic();

  // Collect subscription info from profiles with metadata
  const subscriptions = useMemo(() =>
    profiles
      .filter(p => p.metadata?.subscription)
      .map(p => ({ name: p.name, ...p.metadata!.subscription! }))
  , [profiles]);

  // Recent 5 connections
  const recentConnections = useMemo(() => connections.slice(0, 5), [connections]);

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const formatSpeed = (bytes: number) => formatBytes(bytes) + '/s';

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between">
        <div>
          <h2 className="text-2xl font-bold text-slate-100 tracking-tight">概览</h2>
          <p className="text-xs text-slate-500 mt-1">实时流量与连接状态一览</p>
        </div>
        <span className="text-[10px] text-slate-600">
          {isRunning ? '● 运行中' : '○ 已停止'}
        </span>
      </div>

      {/* Status cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          tone={isRunning ? 'emerald' : 'slate'}
          icon={
            <span
              className={`w-2.5 h-2.5 rounded-full ${
                isRunning
                  ? 'bg-emerald-400 shadow-[0_0_8px_rgba(52,211,153,0.6)]'
                  : 'bg-slate-500'
              }`}
            />
          }
          label="运行状态"
          value={isRunning ? '运行中' : '已停止'}
        />

        <StatCard
          tone="blue"
          icon={<Clock size={18} className="text-blue-300" />}
          label="当前配置"
          value={activeProfile || '未选择'}
        />

        <StatCard
          tone="emerald"
          icon={<ArrowDown size={18} className="text-emerald-300" />}
          label="下载"
          value={formatSpeed(traffic.downloadSpeed)}
          sub={`总计 ${formatBytes(traffic.download)}`}
        />

        <StatCard
          tone="amber"
          icon={<ArrowUp size={18} className="text-amber-300" />}
          label="上传"
          value={formatSpeed(traffic.uploadSpeed)}
          sub={`总计 ${formatBytes(traffic.upload)}`}
        />
      </div>

      {/* Subscription Quota */}
      {subscriptions.length > 0 && (
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-300 flex items-center gap-2">
            <Cloud size={16} className="text-blue-400" /> 订阅配额
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {subscriptions.map((sub, i) => {
              const used = (sub.upload ?? 0) + (sub.download ?? 0);
              const total = sub.total ?? 0;
              const ratio = total > 0 ? Math.min(used / total, 1) : 0;
              const pct = (ratio * 100).toFixed(0);
              const expireDate = sub.expire_at ? new Date(sub.expire_at) : null;
              const isExpired = expireDate ? expireDate < new Date() : false;
              const isExpiringSoon = expireDate && !isExpired && (expireDate.getTime() - Date.now() < 72 * 3600 * 1000);

              return (
                <div key={i} className="bg-slate-900/40 border border-slate-800/70 rounded-xl p-4 shadow-sm">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-xs font-medium text-slate-300 truncate">{sub.name}</span>
                    {expireDate && (
                      <span className={`text-[10px] px-1.5 py-0.5 rounded ${isExpired ? 'bg-red-500/20 text-red-400' : isExpiringSoon ? 'bg-amber-500/20 text-amber-400' : 'bg-slate-700/50 text-slate-400'}`}>
                        {isExpired ? '已过期' : isExpiringSoon ? '即将到期' : `${pct}%`}
                      </span>
                    )}
                  </div>
                  {total > 0 && (
                    <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden mb-2">
                      <div
                        className={`h-full rounded-full transition-all ${ratio > 0.9 ? 'bg-red-500' : ratio > 0.7 ? 'bg-amber-500' : 'bg-emerald-500'}`}
                        style={{ width: `${ratio * 100}%` }}
                      />
                    </div>
                  )}
                  <div className="flex justify-between text-[10px] text-slate-500">
                    <span>{formatBytes(used)} / {formatBytes(total)}</span>
                    {expireDate && <span>{expireDate.toLocaleDateString()}</span>}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Recent Connections */}
      {isRunning && recentConnections.length > 0 && (
        <div className="space-y-3">
          <h3 className="text-sm font-semibold text-slate-300 flex items-center gap-2">
            <Wifi size={16} className="text-emerald-400" /> 最近连接
          </h3>
          <div className="bg-slate-900/40 border border-slate-800/70 rounded-2xl overflow-hidden shadow-sm">
            {recentConnections.map((conn, i) => (
              <div key={conn.id} className={`flex items-center gap-3 px-4 py-2.5 text-xs ${i > 0 ? 'border-t border-slate-800/50' : ''}`}>
                <span className="text-slate-500 font-mono w-20 truncate">{conn.host}</span>
                <span className="text-slate-500">:{conn.port}</span>
                <div className="flex-1" />
                <span className="text-[10px] px-1.5 py-0.5 bg-slate-800 rounded text-slate-400">{conn.rule || 'DIRECT'}</span>
                <span className="text-slate-500 w-16 text-right">{formatBytes(conn.upload + conn.download)}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Traffic Chart */}
      <div className="bg-slate-900/40 border border-slate-800/70 rounded-2xl p-6 shadow-sm shadow-black/10">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-base font-semibold text-slate-100">实时流量</h3>
          {isRunning && (
            <span className="text-[10px] text-emerald-400 flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              LIVE
            </span>
          )}
        </div>
        {!isRunning ? (
          <div className="h-64 flex flex-col items-center justify-center text-slate-500 gap-3">
            <Activity size={36} className="opacity-25" />
            <span className="text-sm">启动代理后即可查看流量曲线</span>
          </div>
        ) : isError ? (
          <div className="h-64 flex items-center justify-center">
            <span className="text-red-400 text-sm">加载流量数据失败</span>
          </div>
        ) : (
          <TrafficChart />
        )}
      </div>
    </div>
  );
}

type Tone = 'emerald' | 'blue' | 'amber' | 'slate';

function StatCard({
  tone,
  icon,
  label,
  value,
  sub,
}: {
  tone: Tone;
  icon: React.ReactNode;
  label: string;
  value: string;
  sub?: string;
}) {
  const ring: Record<Tone, string> = {
    emerald: 'before:bg-emerald-500/10',
    blue: 'before:bg-blue-500/10',
    amber: 'before:bg-amber-500/10',
    slate: 'before:bg-slate-500/10',
  };
  return (
    <div
      className={`
        relative bg-slate-900/40 border border-slate-800/70 rounded-2xl p-5
        overflow-hidden shadow-sm shadow-black/10 transition-colors hover:border-slate-700
        before:content-[''] before:absolute before:-top-12 before:-right-12 before:w-32 before:h-32
        before:rounded-full before:blur-2xl before:opacity-60
        ${ring[tone]}
      `}
    >
      <div className="relative flex items-center gap-2 mb-3 text-xs text-slate-400 font-medium">
        <span className="w-7 h-7 rounded-lg bg-slate-800/70 flex items-center justify-center">
          {icon}
        </span>
        {label}
      </div>
      <p className="relative text-xl font-semibold text-slate-100 truncate tracking-tight">
        {value}
      </p>
      {sub && <p className="relative text-[11px] text-slate-500 mt-1">{sub}</p>}
    </div>
  );
}
