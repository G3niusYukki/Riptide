import { useEffect, useState } from 'react';
import { Database, RefreshCw, Loader2 } from 'lucide-react';
import * as tauri from '../../services/tauri';

/** Geo assets tab — GeoIP / GeoSite presence + refresh. */
export function AssetsTab() {
  const [assets, setAssets] = useState<tauri.GeoAsset[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const refresh = () => tauri.getGeoAssets().then(setAssets).catch(console.error);

  useEffect(() => {
    refresh();
  }, []);

  const download = async () => {
    setRefreshing(true);
    setMsg(null);
    try {
      await tauri.downloadGeoAssets();
      await refresh();
      setMsg('已更新。');
    } catch (e) {
      setMsg(`更新失败：${e}`);
    } finally {
      setRefreshing(false);
    }
  };

  const formatBytes = (n?: number) => {
    if (!n) return '—';
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
  };

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-3">
            <Database size={20} className="text-cyan-400" />
            <h3 className="text-lg font-semibold text-slate-100">Geo 资源</h3>
          </div>
          <button
            onClick={download}
            disabled={refreshing}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {refreshing ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
            更新全部
          </button>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          mihomo 的 GeoIP / GeoSite 数据库。规则中的 `GEOIP,CN` / `GEOSITE,gfw` 等需要这些文件。
        </p>

        <div className="space-y-2">
          {assets.map((asset) => (
            <div
              key={asset.name}
              className="flex items-center justify-between p-3 bg-slate-950/50 rounded-lg border border-slate-800"
            >
              <div className="flex items-center gap-3">
                <span
                  className={`w-2 h-2 rounded-full ${asset.installed ? 'bg-emerald-500' : 'bg-red-500'}`}
                />
                <span className="font-mono text-sm text-slate-200">{asset.name}</span>
              </div>
              <div className="text-xs text-slate-500">
                {formatBytes(asset.size_bytes)}
                {asset.last_modified && (
                  <span className="ml-3">
                    更新于 {new Date(asset.last_modified).toLocaleDateString()}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>

        {msg && <p className="mt-3 text-xs text-slate-400">{msg}</p>}
      </div>
    </div>
  );
}
