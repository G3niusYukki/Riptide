import { useEffect, useState } from 'react';
import { Shield, AlertTriangle, Copy, RefreshCw } from 'lucide-react';
import * as tauri from '../../services/tauri';

/** Recovery tab: kill switch toggle + diagnostic report dump. */
export function RecoveryTab() {
  const [ks, setKs] = useState<tauri.KillSwitchState | null>(null);
  const [report, setReport] = useState<tauri.DiagnosticReport | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  const refreshKs = () => tauri.getKillSwitchState().then(setKs).catch(console.error);

  useEffect(() => {
    refreshKs();
  }, []);

  const toggleKs = async (enabled: boolean) => {
    try {
      await tauri.setKillSwitchEnabled(enabled);
      await refreshKs();
    } catch (e) {
      alert(`Kill switch ${enabled ? '开启' : '关闭'}失败：${e}`);
    }
  };

  const release = async () => {
    try {
      await tauri.killSwitchRelease();
      await refreshKs();
    } catch (e) {
      alert(`释放失败：${e}`);
    }
  };

  const collect = async () => {
    setBusy(true);
    setMsg(null);
    try {
      const r = await tauri.collectDiagnosticReport();
      setReport(r);
    } catch (e) {
      setMsg(`收集失败：${e}`);
    } finally {
      setBusy(false);
    }
  };

  const copyReport = async () => {
    if (!report) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(report, null, 2));
      setMsg('已复制到剪贴板。');
    } catch (e) {
      setMsg(`复制失败：${e}`);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-3">
            <Shield size={20} className="text-red-400" />
            <h3 className="text-lg font-semibold text-slate-100">Kill Switch</h3>
          </div>
          {ks?.armed && (
            <span className="flex items-center gap-1.5 px-2 py-1 bg-red-600/20 text-red-400 rounded text-xs font-medium">
              <AlertTriangle size={12} />
              已触发
            </span>
          )}
        </div>

        <p className="text-xs text-slate-500 mb-4">
          TUN 模式下 mihomo 崩溃时，自动在路由表插入 <code>0.0.0.0/0 → 127.0.0.1</code> 阻断所有出站流量直到手动释放。
          仅推荐对泄漏敏感场景启用。
        </p>

        <div className="flex items-center justify-between">
          <span className="text-slate-200 text-sm font-medium">启用 Kill switch</span>
          <button
            onClick={() => toggleKs(!ks?.enabled)}
            className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${ks?.enabled ? 'bg-red-600' : 'bg-slate-700'}`}
          >
            <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform ${ks?.enabled ? 'translate-x-6' : 'translate-x-1'}`} />
          </button>
        </div>

        {ks?.armed && (
          <button
            onClick={release}
            className="mt-4 w-full px-3 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg text-sm font-medium transition-colors"
          >
            释放 — 恢复网络
          </button>
        )}
      </div>

      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-5">
          <h3 className="text-lg font-semibold text-slate-100">诊断报告</h3>
          <div className="flex items-center gap-2">
            <button
              onClick={collect}
              disabled={busy}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 text-blue-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            >
              <RefreshCw size={14} className={busy ? 'animate-spin' : ''} />
              {busy ? '收集中…' : '收集'}
            </button>
            {report && (
              <button
                onClick={copyReport}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors"
              >
                <Copy size={14} />
                复制
              </button>
            )}
          </div>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          收集版本、模式、mihomo 状态、TUN 服务、Geo 资源、日志尾部。<strong className="text-slate-300">不包含</strong>profile YAML、活动连接、WebDAV 凭据。
        </p>

        {report && (
          <pre className="bg-slate-950 border border-slate-800 rounded-lg p-3 text-xs text-slate-300 font-mono whitespace-pre-wrap overflow-auto max-h-96">
            {JSON.stringify(report, null, 2)}
          </pre>
        )}

        {msg && <p className="mt-3 text-xs text-slate-400">{msg}</p>}
      </div>
    </div>
  );
}
