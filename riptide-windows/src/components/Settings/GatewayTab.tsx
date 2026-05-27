import { useEffect, useState } from 'react';
import { Power, Wifi } from 'lucide-react';
import * as tauri from '../../services/tauri';
import type { GatewayDevice } from '../../services/tauri';

export function GatewayTab() {
  const [enabled, setEnabled] = useState(false);
  const [outboundIface, setOutboundIface] = useState('Ethernet');
  const [subnet, setSubnet] = useState('192.168.137.0/24');
  const [devices, setDevices] = useState<GatewayDevice[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    tauri.isGatewayEnabled().then(setEnabled).catch(console.error);
    refreshDevices();
  }, []);

  const refreshDevices = async () => {
    try {
      const devs = await tauri.getGatewayDevices();
      setDevices(devs);
    } catch (e) {
      console.error('Failed to get devices:', e);
    }
  };

  const handleToggle = async () => {
    setLoading(true);
    setError(null);
    try {
      if (enabled) {
        await tauri.disableGateway();
        setEnabled(false);
      } else {
        await tauri.enableGateway(outboundIface, subnet);
        setEnabled(true);
      }
      await refreshDevices();
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-5">
      <div>
        <h3 className="text-lg font-semibold text-slate-100">网关模式</h3>
        <p className="text-xs text-slate-500 mt-1">
          启用 Windows  Internet 连接共享 (ICS)，为局域网设备提供代理上网服务。需要管理员权限。
        </p>
      </div>

      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5 space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">外网接口</label>
            <input
              type="text"
              value={outboundIface}
              onChange={(e) => setOutboundIface(e.target.value)}
              disabled={enabled}
              placeholder="Ethernet"
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            />
          </div>
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">子网</label>
            <input
              type="text"
              value={subnet}
              onChange={(e) => setSubnet(e.target.value)}
              disabled={enabled}
              placeholder="192.168.137.0/24"
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            />
          </div>
        </div>

        {error && (
          <div className="text-xs text-red-400 bg-red-500/10 p-2 rounded">{error}</div>
        )}

        <button
          onClick={handleToggle}
          disabled={loading}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
            enabled
              ? 'bg-red-600/20 hover:bg-red-600/30 text-red-400'
              : 'bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-400'
          } disabled:opacity-50`}
        >
          <Power size={16} /> {loading ? '处理中…' : enabled ? '关闭网关模式' : '启用网关模式'}
        </button>
      </div>

      {/* Connected devices */}
      <div>
        <h4 className="text-sm font-medium text-slate-300 mb-3 flex items-center gap-2">
          <Wifi size={14} className="text-emerald-400" />
          已连接设备 ({devices.length})
        </h4>
        {devices.length === 0 ? (
          <p className="text-xs text-slate-500">暂无设备连接</p>
        ) : (
          <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
            <div className="grid grid-cols-3 gap-2 px-4 py-2 text-xs text-slate-500 border-b border-slate-800">
              <span>IP 地址</span>
              <span>MAC 地址</span>
              <span>接口</span>
            </div>
            {devices.map((dev, i) => (
              <div key={i} className="grid grid-cols-3 gap-2 px-4 py-2 text-xs text-slate-300 hover:bg-slate-800/30">
                <span className="font-mono">{dev.ip}</span>
                <span className="font-mono text-slate-400">{dev.mac}</span>
                <span className="text-slate-400">{dev.interface}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
