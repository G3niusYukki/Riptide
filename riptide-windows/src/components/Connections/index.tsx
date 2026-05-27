import { useConnections, useCloseConnection, useCloseAllConnections } from '../../hooks/useConnections';
import { useRiptideStore } from '../../stores/riptide';
import { Zap, X, ArrowDown, ArrowUp, Loader2, ChevronDown, ChevronRight, Clock, Link, Target } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import { zhCN } from 'date-fns/locale';
import { useState } from 'react';

export function Connections() {
  const { isRunning } = useRiptideStore();
  const { data: connections = [], isLoading, isError } = useConnections();
  const { mutate: closeConnection } = useCloseConnection();
  const { mutate: closeAllConnections } = useCloseAllConnections();
  const [expandedId, setExpandedId] = useState<string | null>(null);

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
          <div className="px-4 py-3 border-b border-slate-800 grid grid-cols-12 gap-2 text-sm font-medium text-slate-400">
            <div className="col-span-3">目标地址</div>
            <div className="col-span-2">节点链</div>
            <div className="col-span-2">上传</div>
            <div className="col-span-2">下载</div>
            <div className="col-span-2">时长</div>
            <div className="col-span-1 text-right">操作</div>
          </div>
          
          <div className="divide-y divide-slate-800 max-h-[calc(100vh-280px)] overflow-y-auto">
            {connections.map((conn) => {
              const isExpanded = expandedId === conn.id;
              return (
              <div key={conn.id}>
                <div 
                  className="px-4 py-3 grid grid-cols-12 gap-2 items-center hover:bg-slate-800/40 transition-colors cursor-pointer"
                  onClick={() => setExpandedId(isExpanded ? null : conn.id)}
                >
                  <div className="col-span-3 min-w-0 flex items-center gap-1.5">
                    {isExpanded ? <ChevronDown size={14} className="text-slate-500 flex-shrink-0" /> : <ChevronRight size={14} className="text-slate-600 flex-shrink-0" />}
                    <div className="min-w-0">
                      <div className="text-sm text-slate-200 truncate" title={`${conn.metadata.host || conn.metadata.destinationIP || 'unknown'}:${conn.metadata.destinationPort}`}>
                        {conn.metadata.host || conn.metadata.destinationIP || 'unknown'}
                        :{conn.metadata.destinationPort}
                      </div>
                      <div className="text-xs text-slate-500 truncate">{conn.rule || 'DIRECT'}</div>
                    </div>
                  </div>
                  <div className="col-span-2 text-sm text-slate-300 truncate" title={conn.chains.join(' → ')}>
                    {conn.chains.join(' → ')}
                  </div>
                  <div className="col-span-2 text-sm text-slate-300 flex items-center gap-1.5">
                    <ArrowUp size={12} className="text-blue-400 flex-shrink-0" />
                    <span className="truncate">{formatBytes(conn.upload)}</span>
                  </div>
                  <div className="col-span-2 text-sm text-slate-300 flex items-center gap-1.5">
                    <ArrowDown size={12} className="text-emerald-400 flex-shrink-0" />
                    <span className="truncate">{formatBytes(conn.download)}</span>
                  </div>
                  <div className="col-span-2 text-sm text-slate-400">
                    {getDuration(conn.start)}
                  </div>
                  <div className="col-span-1 text-right">
                    <button
                      onClick={(e) => { e.stopPropagation(); closeConnection(conn.id); }}
                      className="p-1.5 text-slate-500 hover:text-red-400 transition-colors rounded hover:bg-slate-800"
                      title="关闭连接"
                    >
                      <X size={16} />
                    </button>
                  </div>
                </div>

                {/* Expanded detail panel */}
                {isExpanded && (
                  <div className="px-6 py-3 bg-slate-800/30 border-t border-slate-800/50 space-y-2 text-xs">
                    <div className="grid grid-cols-2 gap-4">
                      <div>
                        <span className="text-slate-500 flex items-center gap-1 mb-1"><Target size={12} /> 5元组</span>
                        <div className="text-slate-300 font-mono">
                          {conn.metadata.sourceIP}:{conn.metadata.sourcePort} → {conn.metadata.destinationIP || '?'}:{conn.metadata.destinationPort}
                        </div>
                      </div>
                      <div>
                        <span className="text-slate-500 flex items-center gap-1 mb-1"><Clock size={12} /> 时间</span>
                        <div className="text-slate-300">
                          建立于 {new Date(conn.start).toLocaleString()} · {getDuration(conn.start)}
                        </div>
                      </div>
                    </div>
                    {conn.rule && (
                      <div>
                        <span className="text-slate-500 flex items-center gap-1 mb-1"><Target size={12} /> 命中规则</span>
                        <span className="inline-block px-2 py-0.5 bg-blue-500/15 text-blue-400 rounded font-mono">{conn.rule}</span>
                      </div>
                    )}
                    {conn.chains.length > 0 && (
                      <div>
                        <span className="text-slate-500 flex items-center gap-1 mb-1"><Link size={12} /> 代理链</span>
                        <div className="flex items-center gap-1 flex-wrap">
                          {conn.chains.map((node, idx) => (
                            <span key={idx} className="flex items-center gap-1">
                              <span className={`px-1.5 py-0.5 rounded font-mono ${idx === conn.chains.length - 1 ? 'bg-emerald-500/15 text-emerald-400' : 'bg-slate-700/50 text-slate-400'}`}>
                                {node}
                              </span>
                              {idx < conn.chains.length - 1 && <span className="text-slate-600">→</span>}
                            </span>
                          ))}
                        </div>
                      </div>
                    )}
                    <div className="flex gap-6 text-slate-500">
                      <span>↑ {formatBytes(conn.upload)} 上传</span>
                      <span>↓ {formatBytes(conn.download)} 下载</span>
                      <span>∑ {formatBytes(conn.upload + conn.download)} 总计</span>
                    </div>
                  </div>
                )}
              </div>
            )})}
          </div>
        </div>
      )}
    </div>
  );
}
