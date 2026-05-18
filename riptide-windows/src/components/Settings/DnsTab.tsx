import { useEffect, useState } from 'react';
import { Globe, Save } from 'lucide-react';
import * as tauri from '../../services/tauri';

/** DNS tab — edit the persistent DnsPolicy that overlays on profile YAML. */
export function DnsTab() {
  const [policy, setPolicy] = useState<tauri.DnsPolicy | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState<string | null>(null);

  useEffect(() => {
    tauri.getDnsPolicy().then(setPolicy).catch(console.error);
  }, []);

  if (!policy) return <div className="text-slate-500">加载中…</div>;

  const update = <K extends keyof tauri.DnsPolicy>(key: K, value: tauri.DnsPolicy[K]) =>
    setPolicy({ ...policy, [key]: value });

  const updateList = (key: 'nameserver' | 'fallback' | 'default_nameserver' | 'fake_ip_filter', text: string) =>
    update(key, text.split('\n').map((s) => s.trim()).filter(Boolean));

  const save = async () => {
    setSaving(true);
    setSavedMsg(null);
    try {
      await tauri.setDnsPolicy(policy);
      setSavedMsg('已保存。下次启动代理时生效。');
    } catch (e) {
      setSavedMsg(`保存失败：${e}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-3">
            <Globe size={20} className="text-emerald-400" />
            <h3 className="text-lg font-semibold text-slate-100">DNS 策略</h3>
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={policy.enable_override}
              onChange={(e) => update('enable_override', e.target.checked)}
              className="rounded"
            />
            <span className="text-slate-300">启用覆盖</span>
          </label>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          关闭时使用 profile 自带的 DNS 配置。启用后，下列字段非空者覆盖 profile 对应项；空字段保持 profile 值。
        </p>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">Enhanced Mode</label>
            <select
              value={policy.enhanced_mode || ''}
              onChange={(e) => update('enhanced_mode', e.target.value || undefined)}
              disabled={!policy.enable_override}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            >
              <option value="">(保留 profile)</option>
              <option value="fake-ip">fake-ip</option>
              <option value="redir-host">redir-host</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">FakeIP 范围</label>
            <input
              type="text"
              value={policy.fake_ip_range || ''}
              onChange={(e) => update('fake_ip_range', e.target.value || undefined)}
              disabled={!policy.enable_override}
              placeholder="198.18.0.1/16"
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            />
          </div>
        </div>

        <div className="mt-4">
          <label className="block text-xs text-slate-400 mb-1.5">主 DNS（每行一个 DoH/DoT/DoQ URL）</label>
          <textarea
            rows={3}
            value={policy.nameserver.join('\n')}
            onChange={(e) => updateList('nameserver', e.target.value)}
            disabled={!policy.enable_override}
            placeholder="https://1.1.1.1/dns-query&#10;tls://8.8.8.8"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 font-mono focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>

        <div className="mt-4">
          <label className="block text-xs text-slate-400 mb-1.5">Fallback DNS</label>
          <textarea
            rows={2}
            value={policy.fallback.join('\n')}
            onChange={(e) => updateList('fallback', e.target.value)}
            disabled={!policy.enable_override}
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 font-mono focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>

        <div className="mt-4">
          <label className="block text-xs text-slate-400 mb-1.5">Bootstrap DNS（用于解析 DoH 主机名）</label>
          <textarea
            rows={2}
            value={policy.default_nameserver.join('\n')}
            onChange={(e) => updateList('default_nameserver', e.target.value)}
            disabled={!policy.enable_override}
            placeholder="223.5.5.5&#10;119.29.29.29"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 font-mono focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>

        <div className="mt-4">
          <label className="block text-xs text-slate-400 mb-1.5">FakeIP 过滤（绕过 FakeIP 的域名）</label>
          <textarea
            rows={2}
            value={policy.fake_ip_filter.join('\n')}
            onChange={(e) => updateList('fake_ip_filter', e.target.value)}
            disabled={!policy.enable_override}
            placeholder="*.lan&#10;localhost.ptlogin2.qq.com"
            className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 font-mono focus:outline-none focus:border-blue-500 disabled:opacity-50"
          />
        </div>

        <div className="flex items-center justify-between mt-5 pt-4 border-t border-slate-800">
          {savedMsg && <p className="text-xs text-slate-400">{savedMsg}</p>}
          <button
            onClick={save}
            disabled={saving}
            className="ml-auto flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            <Save size={14} />
            {saving ? '保存中…' : '保存'}
          </button>
        </div>
      </div>
    </div>
  );
}
