import { useEffect, useState } from 'react';
import {
  AlertTriangle,
  Lock,
  KeySquare,
  Plus,
  Pencil,
  Trash2,
  Globe,
} from 'lucide-react';
import * as tauri from '../../services/tauri';
import type { CAState, HostRule } from '../../types/mitm';

/** MITM (HTTPS interception) settings tab.
 *
 *  Phase C7.3 / C7.4 — sandbox UI only. The Rust `mitm` module is
 *  scheduled for v2.5.0 (Phase D); the 5 `tauri.mitm*` wrappers
 *  reject with `not_implemented` so the UI degrades gracefully
 *  instead of crashing. All action buttons are rendered as `disabled`
 *  to make the experimental state obvious to the user.
 *
 *  Mirrors the macOS `MITMSettingsView` in
 *  `Sources/RiptideApp/Views/MITMSettingsView.swift`, minus the
 *  per-row live wiring. Once the Rust side lands, the only
 *  change needed is to drop the `disabled` props and call the
 *  real `getMitmConfig` / `setMitmConfig` / `installCa` etc.
 */
export function MITMTab() {
  // The 5 stubs always reject, so these will stay at their initial
  // values; we still wire the fetch pattern so the post-Phase-D
  // upgrade is a one-line `setX(...)` swap rather than a refactor.
  const [caState, setCaState] = useState<CAState | null>(null);
  const [hostRules] = useState<HostRule[]>([]);
  const [msg, setMsg] = useState<string | null>(null);

  const refresh = () => {
    tauri
      .getCaState()
      .then(setCaState)
      .catch((e) => {
        // Expected: backend stub. Log once so QA can see the rejection
        // without spamming the console.
        console.debug('[mitm] getCaState rejected (expected for v2.4.x):', e);
      });
  };

  useEffect(() => {
    refresh();
  }, []);

  const onInstallCa = async () => {
    setMsg(null);
    try {
      const next = await tauri.installCa();
      setCaState(next);
      setMsg('CA 安装请求已发出。');
    } catch (e) {
      setMsg(`CA 安装失败：${e}`);
    }
  };

  const onUninstallCa = async () => {
    setMsg(null);
    try {
      const next = await tauri.uninstallCa();
      setCaState(next);
      setMsg('CA 卸载请求已发出。');
    } catch (e) {
      setMsg(`CA 卸载失败：${e}`);
    }
  };

  return (
    <div className="space-y-6" data-testid="mitm-tab">
      {/* Experimental warning banner — mirrors the macOS
          MITMSettingsView's "🟡 experimental" callout. */}
      <div
        className="flex items-start gap-3 p-4 bg-amber-500/10 border border-amber-500/30 rounded-xl"
        data-testid="mitm-experimental-warning"
      >
        <AlertTriangle size={20} className="text-amber-400 shrink-0 mt-0.5" />
        <div className="text-xs text-amber-200/90 leading-relaxed">
          <p className="font-semibold text-amber-300 mb-1">
            🟡 experimental — MITM is currently experimental on Windows. Backend
            implementation lands in v2.5.0.
          </p>
          <p>
            HTTPS 中间人解密会暴露所有加密流量，仅供调试与开发用途。
            在 Windows 上启用前请先阅读 MITM 安全模型文档。
          </p>
        </div>
      </div>

      {/* Global enable switch — disabled because the backend is a stub. */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Lock size={20} className="text-blue-400" />
            <div>
              <h3 className="text-lg font-semibold text-slate-100">HTTPS 拦截 (MITM)</h3>
              <p className="text-xs text-slate-500 mt-1">
                启用后匹配白名单的 HTTPS 请求将被解密以便查看/修改。
              </p>
            </div>
          </div>
          <label
            className="relative inline-flex h-7 w-12 items-center rounded-full bg-slate-700 cursor-not-allowed opacity-60"
            data-testid="mitm-enable-switch"
            title="后端尚未实现"
          >
            <span className="inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform translate-x-1" />
            <input
              type="checkbox"
              className="sr-only"
              checked={false}
              disabled
              readOnly
              aria-label="启用 MITM（不可用）"
            />
          </label>
        </div>
      </div>

      {/* CA certificate status card. */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <KeySquare size={20} className="text-emerald-400" />
            <h3 className="text-lg font-semibold text-slate-100">CA 根证书</h3>
          </div>
          <span
            className={`flex items-center gap-1.5 px-2 py-1 rounded text-xs font-medium ${
              caState?.installed
                ? 'bg-emerald-500/20 text-emerald-300'
                : 'bg-slate-700/50 text-slate-400'
            }`}
            data-testid="mitm-ca-status"
          >
            <span
              className={`w-1.5 h-1.5 rounded-full ${
                caState?.installed ? 'bg-emerald-400' : 'bg-slate-500'
              }`}
            />
            {caState?.installed ? '已安装' : '未安装'}
          </span>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          MITM 需要安装 Riptide 自签名的 CA 根证书到系统证书存储。
          安装后浏览器/系统仍可能弹出证书警告，需要在信任设置中手动放行。
        </p>

        {caState?.fingerprint && (
          <div className="mb-4 font-mono text-[11px] text-slate-400 break-all bg-slate-950/50 border border-slate-800 rounded p-2">
            <span className="text-slate-500">SHA-256: </span>
            {caState.fingerprint}
          </div>
        )}

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onInstallCa}
            disabled
            data-testid="mitm-ca-install"
            className="px-3 py-1.5 bg-blue-600/30 text-blue-200 rounded-lg text-xs font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            安装到系统
          </button>
          <button
            type="button"
            onClick={onUninstallCa}
            disabled
            data-testid="mitm-ca-uninstall"
            className="px-3 py-1.5 bg-slate-800 text-slate-300 rounded-lg text-xs font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            卸载
          </button>
          <span className="text-[11px] text-slate-500 ml-1">
            （后端尚未实现 · v2.5.0）
          </span>
        </div>
      </div>

      {/* Host whitelist table — CRUD UI scaffold.
          The 3 controls (add / edit / delete) are always rendered
          (and disabled) so the user can see the CRUD affordance
          even before the backend lands in v2.5.0. */}
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <Globe size={20} className="text-cyan-400" />
            <h3 className="text-lg font-semibold text-slate-100">Host 白名单</h3>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => {
                /* disabled — backend stub */
              }}
              disabled
              data-testid="mitm-host-add"
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/30 text-blue-200 rounded-lg text-xs font-medium disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Plus size={14} /> 添加
            </button>
            <button
              type="button"
              onClick={() => {
                /* disabled — backend stub */
              }}
              disabled
              data-testid="mitm-host-edit"
              className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 text-slate-300 rounded-lg text-xs font-medium disabled:opacity-50 disabled:cursor-not-allowed"
              title="编辑选中行（不可用）"
            >
              <Pencil size={14} /> 编辑
            </button>
            <button
              type="button"
              onClick={() => {
                /* disabled — backend stub */
              }}
              disabled
              data-testid="mitm-host-delete"
              className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 text-slate-300 rounded-lg text-xs font-medium disabled:opacity-50 disabled:cursor-not-allowed"
              title="删除选中行（不可用）"
            >
              <Trash2 size={14} /> 删除
            </button>
          </div>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          仅对列表中的域名进行 HTTPS 解密。支持通配符（<code>*.example.com</code>）。
        </p>

        <div className="overflow-hidden rounded-lg border border-slate-800">
          <table className="w-full text-xs" data-testid="mitm-host-table">
            <thead className="bg-slate-950/50 text-slate-400">
              <tr>
                <th className="text-left px-3 py-2 font-medium">域名</th>
                <th className="text-left px-3 py-2 font-medium">备注</th>
                <th className="text-left px-3 py-2 font-medium">状态</th>
              </tr>
            </thead>
            <tbody>
              {hostRules.length === 0 ? (
                <tr data-testid="mitm-host-empty-row">
                  <td
                    colSpan={3}
                    className="px-3 py-6 text-center text-slate-500 italic"
                  >
                    暂无规则。点击"添加"创建第一条（后端尚未实现）。
                  </td>
                </tr>
              ) : (
                hostRules.map((r) => (
                  <tr key={r.id} className="border-t border-slate-800">
                    <td className="px-3 py-2 font-mono text-slate-200">{r.pattern}</td>
                    <td className="px-3 py-2 text-slate-400">{r.note ?? '—'}</td>
                    <td className="px-3 py-2 text-slate-400">
                      {r.enabled ? '启用' : '禁用'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {msg && <p className="mt-3 text-xs text-slate-400">{msg}</p>}
      </div>
    </div>
  );
}
