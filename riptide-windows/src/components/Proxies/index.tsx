import { useState, useEffect } from 'react';
import { useRiptideStore } from '../stores/riptide';
import { Globe, Zap, ChevronDown, Check } from 'lucide-react';
import * as tauri from '../services/tauri';
import type { Proxy, ProxyGroup } from '../types';

export function Proxies() {
  const { proxies, proxyGroups, selectedProxy, setProxies, setProxyGroups, setSelectedProxy } = useRiptideStore();
  const [testingProxy, setTestingProxy] = useState<string | null>(null);

  // Load proxies on mount
  useEffect(() => {
    // TODO: Load from mihomo API
  }, []);

  const testDelay = async (proxyName: string) => {
    setTestingProxy(proxyName);
    try {
      const delay = await tauri.testProxyDelay(proxyName);
      // Update proxy delay
      setProxies(proxies.map(p => 
        p.name === proxyName ? { ...p, delay } : p
      ));
    } catch (error) {
      console.error('Failed to test delay:', error);
    } finally {
      setTestingProxy(null);
    }
  };

  const selectProxy = async (groupName: string, proxyName: string) => {
    // TODO: Switch proxy via mihomo API
    setSelectedProxy(proxyName);
  };

  const getDelayColor = (delay?: number) => {
    if (!delay) return 'text-slate-500';
    if (delay < 100) return 'text-emerald-400';
    if (delay < 300) return 'text-yellow-400';
    return 'text-red-400';
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-slate-100">代理节点</h2>
        <button 
          className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors"
          onClick={() => {/* Test all delays */}}
        >
          测试全部延迟
        </button>
      </div>

      {/* Proxy Groups */}
      <div className="space-y-4">
        {proxyGroups.map((group) => (
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
                <span className="text-sm font-medium text-blue-400">{group.now || 'Auto'}</span>
              </div>
            </div>
            
            <div className="divide-y divide-slate-800">
              {group.proxies.map((proxyName) => {
                const proxy = proxies.find(p => p.name === proxyName);
                const isSelected = group.now === proxyName;
                
                return (
                  <div 
                    key={proxyName}
                    className="px-6 py-3 flex items-center justify-between hover:bg-slate-800/50 transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      {isSelected && <Check size={16} className="text-emerald-400" />}
                      <span className={`${isSelected ? 'text-slate-100' : 'text-slate-400'}`}>
                        {proxyName}
                      </span>
                    </div>
                    
                    <div className="flex items-center gap-4">
                      <button
                        onClick={() => testDelay(proxyName)}
                        disabled={testingProxy === proxyName}
                        className="text-xs px-3 py-1.5 bg-slate-800 hover:bg-slate-700 rounded text-slate-300 transition-colors disabled:opacity-50"
                      >
                        {testingProxy === proxyName ? '测试中...' : '测延迟'}
                      </button>
                      
                      <span className={`text-sm font-medium w-16 text-right ${getDelayColor(proxy?.delay)}`}>
                        {proxy?.delay ? `${proxy.delay}ms` : '-'}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {/* Direct Proxies */}
      {proxies.length > 0 && (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-800">
            <h3 className="font-semibold text-slate-100">所有节点</h3>
          </div>
          <div className="divide-y divide-slate-800">
            {proxies.map((proxy) => (
              <div 
                key={proxy.name}
                className="px-6 py-3 flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <Zap size={16} className="text-yellow-400" />
                  <span className="text-slate-300">{proxy.name}</span>
                  <span className="text-xs text-slate-500">{proxy.server}:{proxy.port}</span>
                </div>
                <span className={`text-sm font-medium ${getDelayColor(proxy.delay)}`}>
                  {proxy.delay ? `${proxy.delay}ms` : '-'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
