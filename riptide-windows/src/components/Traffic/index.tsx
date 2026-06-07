// C13.2 — Traffic top-level tab.
//
// Extracted from the previous Dashboard "实时流量" panel. The chart
// rendering logic is unchanged — only the layout host moved. Phase C13
// can later add per-process / per-rule breakdown here without touching
// Dashboard.

import { Activity, ArrowDown, ArrowUp } from 'lucide-react';
import { useRiptideStore } from '../../stores/riptide';
import { useTraffic } from '../../hooks/useTraffic';
import { TrafficChart } from './TrafficChart';

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(bytes) / Math.log(k)), sizes.length - 1);
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatSpeed(bytes: number): string {
  return formatBytes(bytes) + '/s';
}

export function Traffic() {
  const { isRunning, traffic } = useRiptideStore();
  const { isError } = useTraffic();

  return (
    <div className="space-y-6" data-testid="traffic-page">
      <div className="flex items-end justify-between">
        <div>
          <h2 className="text-2xl font-bold text-slate-100 tracking-tight">流量</h2>
          <p className="text-xs text-slate-500 mt-1">实时上下行速率与累计量</p>
        </div>
        <span className="text-[10px] text-slate-600">
          {isRunning ? '● 运行中' : '○ 已停止'}
        </span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          className="bg-slate-900/40 border border-slate-800/70 rounded-2xl p-5 shadow-sm shadow-black/10"
          data-testid="traffic-stat-download"
        >
          <div className="flex items-center gap-2 mb-3 text-xs text-slate-400 font-medium">
            <span className="w-7 h-7 rounded-lg bg-slate-800/70 flex items-center justify-center">
              <ArrowDown size={18} className="text-emerald-300" />
            </span>
            下载
          </div>
          <p className="text-xl font-semibold text-slate-100 tracking-tight">
            {formatSpeed(traffic.downloadSpeed)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">总计 {formatBytes(traffic.download)}</p>
        </div>

        <div
          className="bg-slate-900/40 border border-slate-800/70 rounded-2xl p-5 shadow-sm shadow-black/10"
          data-testid="traffic-stat-upload"
        >
          <div className="flex items-center gap-2 mb-3 text-xs text-slate-400 font-medium">
            <span className="w-7 h-7 rounded-lg bg-slate-800/70 flex items-center justify-center">
              <ArrowUp size={18} className="text-amber-300" />
            </span>
            上传
          </div>
          <p className="text-xl font-semibold text-slate-100 tracking-tight">
            {formatSpeed(traffic.uploadSpeed)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">总计 {formatBytes(traffic.upload)}</p>
        </div>
      </div>

      <div
        className="bg-slate-900/40 border border-slate-800/70 rounded-2xl p-6 shadow-sm shadow-black/10"
        data-testid="traffic-chart-card"
      >
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
