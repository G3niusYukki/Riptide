import { useTraffic } from '../hooks/useTraffic';
import { useRiptideStore } from '../stores/riptide';
import { Activity, ArrowDown, ArrowUp, Clock } from 'lucide-react';
import { TrafficChart } from './Dashboard/TrafficChart';

export function Dashboard() {
  const { isRunning, traffic, activeProfile } = useRiptideStore();
  const { isError } = useTraffic();

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
