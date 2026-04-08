import { useEffect } from 'react';
import { useRiptideStore } from '../stores/riptide';
import { Activity, ArrowDown, ArrowUp, Clock } from 'lucide-react';

export function Dashboard() {
  const { isRunning, traffic, activeProfile, setTraffic } = useRiptideStore();

  // Simulate traffic updates (replace with real data later)
  useEffect(() => {
    if (!isRunning) return;
    
    const interval = setInterval(() => {
      setTraffic({
        upload: Math.floor(Math.random() * 1000000),
        download: Math.floor(Math.random() * 5000000),
        uploadSpeed: Math.floor(Math.random() * 100000),
        downloadSpeed: Math.floor(Math.random() * 500000),
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [isRunning, setTraffic]);

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const formatSpeed = (bytes: number) => formatBytes(bytes) + '/s';

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold text-slate-100">概览</h2>
      
      {/* Status cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6">
          <div className="flex items-center gap-3 mb-4">
            <div className={`w-3 h-3 rounded-full ${isRunning ? 'bg-emerald-500' : 'bg-red-500'}`} />
            <span className="text-slate-400">运行状态</span>
          </div>
          <p className="text-2xl font-semibold text-slate-100">
            {isRunning ? '运行中' : '已停止'}
          </p>
        </div>

        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6">
          <div className="flex items-center gap-3 mb-4">
            <Clock size={20} className="text-blue-400" />
            <span className="text-slate-400">当前配置</span>
          </div>
          <p className="text-2xl font-semibold text-slate-100 truncate">
            {activeProfile || '未选择'}
          </p>
        </div>

        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6">
          <div className="flex items-center gap-3 mb-4">
            <ArrowDown size={20} className="text-emerald-400" />
            <span className="text-slate-400">下载速度</span>
          </div>
          <p className="text-2xl font-semibold text-slate-100">
            {formatSpeed(traffic.downloadSpeed)}
          </p>
          <p className="text-sm text-slate-500 mt-1">
            总计: {formatBytes(traffic.download)}
          </p>
        </div>

        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6">
          <div className="flex items-center gap-3 mb-4">
            <ArrowUp size={20} className="text-blue-400" />
            <span className="text-slate-400">上传速度</span>
          </div>
          <p className="text-2xl font-semibold text-slate-100">
            {formatSpeed(traffic.uploadSpeed)}
          </p>
          <p className="text-sm text-slate-500 mt-1">
            总计: {formatBytes(traffic.upload)}
          </p>
        </div>
      </div>

      {/* Placeholder for traffic chart */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-6">
        <h3 className="text-lg font-semibold text-slate-100 mb-4">流量统计</h3>
        <div className="h-64 flex items-center justify-center text-slate-500">
          <Activity size={48} className="opacity-20" />
          <span className="ml-4">流量图表即将上线</span>
        </div>
      </div>
    </div>
  );
}
