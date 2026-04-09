import { useState } from 'react';
import { useProxyData, useTestDelay, useSwitchProxy } from '../../hooks/useProxies';
import { useRiptideStore } from '../../stores/riptide';
import { Globe, Zap, Check, Loader2 } from 'lucide-react';

export function Proxies() {
  const { isRunning } = useRiptideStore();
  const { groups, proxies, isLoading, isError } = useProxyData();
  const { mutateAsync: testDelayAsync, isPending: isTesting } = useTestDelay();
  const { mutateAsync: switchProxyAsync, isPending: isSwitching } = useSwitchProxy();
  const [testingProxy, setTestingProxy] = useState<string | null>(null);

  const handleTestDelay = async (proxyName: string) => {
    setTestingProxy(proxyName);
    try {
      await testDelayAsync({ name: proxyName });
    } finally {
      setTestingProxy(null);
    }
  };

  const handleTestAllDelay = async () => {
    const proxyNames = [...new Set(groups.flatMap(group => group.proxies))];

    for (const proxyName of proxyNames) {
      await handleTestDelay(proxyName);
    }
  };

  const handleSwitchProxy = async (group: string, proxyName: string) => {
    await switchProxyAsync({ group, proxyName });
  };

  const getDelayColor = (delay?: number) => {
    if (!delay || delay === 0) return 'text-slate-500';
    if (delay < 100) return 'text-emerald-400';
    if (delay < 300) return 'text-yellow-400';
    return 'text-red-400';
  };

  if (!isRunning) {
    return (
      <div className="space-y-6">
        <h2 className="text-2xl font-bold text-slate-100">代理节点</h2>
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Globe size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">启动代理以查看节点列表</p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <h2 className="text-2xl font-bold text-slate-100">代理节点</h2>
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
        <h2 className="text-2xl font-bold text-slate-100">代理节点</h2>
        <div className="bg-red-900/20 border border-red-800 rounded-xl p-6">
          <p className="text-red-400">加载代理数据失败，请确保 mihomo 正在运行</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-slate-100">代理节点</h2>
        <button 
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          onClick={handleTestAllDelay}
          disabled={isTesting || isSwitching}
        >
          {isTesting ? '测试中...' : '测试全部延迟'}
        </button>
      </div>

      {/* Proxy Groups */}
      <div className="space-y-4">
        {groups.length === 0 ? (
          <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-8 text-center">
            <p className="text-slate-500">暂无代理组</p>
          </div>
        ) : (
          groups.map((group) => (
            <div key={group.name} className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
              <div className="px-6 py-4 border-b border-slate-800 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Globe size={20} className="text-blue-400" />
                  <h3 className="font-semibold text-slate-100">{group.name}</h3>
                  <span className="text-xs px-2 py-1 bg-slate-800 rounded text-slate-400">
                    {group.type}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-sm text-slate-400">当前:</span>
                  <span className="text-sm font-medium text-blue-400">
                    {group.now || 'Auto'}
                  </span>
                </div>
              </div>
              
              <div className="divide-y divide-slate-800">
                {group.proxies.length === 0 ? (
                  <div className="px-6 py-3 text-slate-500 text-sm">暂无代理节点</div>
                ) : (
                  group.proxies.map((proxyName) => {
                    const proxy = proxies.find(p => p.name === proxyName);
                    const isSelected = group.now === proxyName;
                    const isCurrentTesting = testingProxy === proxyName;
                    
                    return (
                      <div 
                        key={proxyName}
                        className={`
                          px-6 py-3 flex items-center justify-between cursor-pointer
                          transition-colors hover:bg-slate-800/50
                          ${isSelected ? 'bg-blue-600/10' : ''}
                          ${isSwitching ? 'opacity-60 cursor-not-allowed' : ''}
                        `}
                        onClick={() => !isSwitching && handleSwitchProxy(group.name, proxyName)}
                      >
                        <div className="flex items-center gap-3">
                          {isSelected && <Check size={16} className="text-emerald-400" />}
                          <span className={`${isSelected ? 'text-slate-100' : 'text-slate-400'}`}>
                            {proxyName}
                          </span>
                        </div>
                        
                        <div className="flex items-center gap-4">
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleTestDelay(proxyName);
                            }}
                            disabled={isCurrentTesting || isSwitching}
                            className="text-xs px-3 py-1.5 bg-slate-800 hover:bg-slate-700 rounded text-slate-300 transition-colors disabled:opacity-50"
                          >
                            {isCurrentTesting ? (
                              <Loader2 size={12} className="animate-spin inline mr-1" />
                            ) : null}
                            测延迟
                          </button>
                          
                          <span className={`text-sm font-medium w-16 text-right ${getDelayColor(proxy?.delay)}`}>
                            {proxy?.delay ? `${proxy.delay}ms` : '-'}
                          </span>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* All Proxies */}
      {proxies.length > 0 && (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-800">
            <h3 className="font-semibold text-slate-100">所有节点 ({proxies.length})</h3>
          </div>
          <div className="divide-y divide-slate-800 max-h-96 overflow-y-auto">
            {proxies.map((proxy) => (
              <div 
                key={proxy.name}
                className="px-6 py-3 flex items-center justify-between hover:bg-slate-800/30"
              >
                <div className="flex items-center gap-3">
                  <Zap size={16} className="text-yellow-400" />
                  <span className="text-slate-300">{proxy.name}</span>
                  <span className="text-xs text-slate-500">{proxy.type}</span>
                </div>
                <div className="flex items-center gap-4">
                    <button
                    onClick={() => handleTestDelay(proxy.name)}
                    disabled={testingProxy === proxy.name || isSwitching}
                    className="text-xs px-2 py-1 bg-slate-800 hover:bg-slate-700 rounded text-slate-400 transition-colors disabled:opacity-50"
                  >
                    {testingProxy === proxy.name ? (
                      <Loader2 size={10} className="animate-spin inline" />
                    ) : '测'}
                  </button>
                  <span className={`text-sm font-medium w-16 text-right ${getDelayColor(proxy.delay)}`}>
                    {proxy.delay ? `${proxy.delay}ms` : '-'}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
