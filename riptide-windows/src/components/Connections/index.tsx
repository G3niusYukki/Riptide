import { useConnections, useCloseConnection, useCloseAllConnections } from '../../hooks/useConnections';
import { useRiptideStore } from '../../stores/riptide';
import { Zap, X, ArrowDown, ArrowUp, Loader2 } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { zhCN } from 'date-fns/locale';

export function Connections() {
  const { isRunning } = useRiptideStore();
  const { data: connections = [], isLoading, isError } = useConnections();
  const { mutate: closeConnection } = useCloseConnection();
  const { mutate: closeAllConnections } = useCloseAllConnections();

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const getDuration = (startTime: string) => {
    try {
      return formatDistanceToNow(new Date(startTime), { 
        addSuffix: false,
        locale: zhCN 
      });
    } catch {
      return '-';
    }
  };

  if (!isRunning) {
    return (
      <div className="space-y-6">
        <h2 className="text-2xl font-bold text-slate-100">连接列表</h2>
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Zap size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">启动代理以查看连接列表</p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <h2 className="text-2xl font-bold text-slate-100">连接列表</h2>
        <div className="flex items-center justify-center h-64">
          <Loader2 size={32} className="text-blue-400 animate-spin" />
          <span className="ml-3 text-slate-400">加载中...</span>
        </div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="space-y-6">
        <h2 className="text-2xl font-bold text-slate-100">连接列表</h2>
        <div className="bg-red-900/20 border border-red-800 rounded-xl p-6">
          <p className="text-red-400">加载连接数据失败</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-slate-100">连接列表</h2>
        <div className="flex items-center gap-4">
          <span className="text-sm text-slate-400">
            {connections.length} 个活动连接
          </span>
          <button
            onClick={() => closeAllConnections()}
            className="px-4 py-2 bg-red-600/20 hover:bg-red-600/30 text-red-400 rounded-lg text-sm font-medium transition-colors"
          >
            关闭全部
          </button>
        </div>
      </div>

      {connections.length === 0 ? (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Zap size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">暂无活动连接</p>
        </div>
      ) : (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-800 grid grid-cols-12 gap-4 text-sm font-medium text-slate-400">
            <div className="col-span-4">目标地址</div>
            <div className="col-span-2">节点链</div>
            <div className="col-span-2">上传</div>
            <div className="col-span-2">下载</div>
            <div className="col-span-1">时长</div>
            <div className="col-span-1">操作</div>
          </div>
          
          <div className="divide-y divide-slate-800 max-h-96 overflow-y-auto">
            {connections.map((conn) => (
              <div 
                key={conn.id}
                className="px-6 py-4 grid grid-cols-12 gap-4 items-center hover:bg-slate-800/30 transition-colors"
              >
                <div className="col-span-4">
                  <div className="text-sm text-slate-200">
                    {conn.metadata.host || conn.metadata.destinationIP || 'unknown'}
                    :{conn.metadata.destinationPort}
                  </div>
                  <div className="text-xs text-slate-500">{conn.rule || 'DIRECT'}</div>
                </div>
                <div className="col-span-2 text-sm text-slate-300 truncate">
                  {conn.chains.join(' -> ')}
                </div>
                <div className="col-span-2 text-sm text-slate-300 flex items-center gap-1">
                  <ArrowUp size={12} className="text-blue-400" />
                  {formatBytes(conn.upload)}
                </div>
                <div className="col-span-2 text-sm text-slate-300 flex items-center gap-1">
                  <ArrowDown size={12} className="text-emerald-400" />
                  {formatBytes(conn.download)}
                </div>
                <div className="col-span-1 text-sm text-slate-400">
                  {getDuration(conn.start)}
                </div>
                <div className="col-span-1">
                  <button
                    onClick={() => closeConnection(conn.id)}
                    className="p-1.5 text-slate-500 hover:text-red-400 transition-colors"
                  >
                    <X size={16} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
