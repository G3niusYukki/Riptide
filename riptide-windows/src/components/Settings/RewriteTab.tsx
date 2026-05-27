import { useEffect, useState } from 'react';
import { Save, Plus, Trash2, Power } from 'lucide-react';
import * as tauri from '../../services/tauri';
import type { RewriteRule } from '../../types';

export function RewriteTab() {
  const [rules, setRules] = useState<RewriteRule[]>([]);
  const [saving, setSaving] = useState(false);
  const [showAdd, setShowAdd] = useState(false);

  // New rule form state
  const [newPattern, setNewPattern] = useState('');
  const [newActionType, setNewActionType] = useState<string>('Reject');
  const [newRedirectUrl, setNewRedirectUrl] = useState('');
  const [newHeaderKey, setNewHeaderKey] = useState('');
  const [newHeaderValue, setNewHeaderValue] = useState('');

  useEffect(() => {
    tauri.getRewriteRules().then(setRules).catch(console.error);
  }, []);

  const save = async (updated: RewriteRule[]) => {
    setSaving(true);
    try {
      await tauri.setRewriteRules(updated);
      setRules(updated);
    } catch (e) {
      console.error('Failed to save rewrite rules:', e);
    } finally {
      setSaving(false);
    }
  };

  const toggleRule = async (id: string, enabled: boolean) => {
    try {
      await tauri.toggleRewriteRule(id, enabled);
      setRules(rules.map(r => r.id === id ? { ...r, enabled } : r));
    } catch (e) {
      console.error('Failed to toggle rule:', e);
    }
  };

  const deleteRule = async (id: string) => {
    try {
      await tauri.deleteRewriteRule(id);
      setRules(rules.filter(r => r.id !== id));
    } catch (e) {
      console.error('Failed to delete rule:', e);
    }
  };

  const addRule = async () => {
    if (!newPattern.trim()) return;

    const action = {
      action_type: newActionType as 'Reject' | 'Redirect' | 'ModifyHeader' | 'ModifyResponseHeader',
      target: newActionType === 'Redirect' ? newRedirectUrl : undefined,
      header_key: (newActionType === 'ModifyHeader' || newActionType === 'ModifyResponseHeader') ? newHeaderKey : undefined,
      header_value: (newActionType === 'ModifyHeader' || newActionType === 'ModifyResponseHeader') ? newHeaderValue : undefined,
    };

    const rule: RewriteRule = {
      id: crypto.randomUUID(),
      pattern: newPattern.trim(),
      action,
      enabled: true,
    };

    try {
      await tauri.addRewriteRule(rule);
      setRules([...rules, rule]);
      setShowAdd(false);
      setNewPattern('');
      setNewRedirectUrl('');
      setNewHeaderKey('');
      setNewHeaderValue('');
    } catch (e) {
      console.error('Failed to add rule:', e);
    }
  };

  const actionLabel = (action: RewriteRule['action']): string => {
    switch (action.action_type) {
      case 'Reject': return '拦截';
      case 'Redirect': return `重定向 → ${action.target || ''}`;
      case 'ModifyHeader': return `修改请求头 ${action.header_key || ''}=${action.header_value || ''}`;
      case 'ModifyResponseHeader': return `修改响应头 ${action.header_key || ''}=${action.header_value || ''}`;
    }
  };

  const actionColor = (action: RewriteRule['action']): string => {
    switch (action.action_type) {
      case 'Reject': return 'text-red-400 bg-red-500/10';
      case 'Redirect': return 'text-amber-400 bg-amber-500/10';
      default: return 'text-blue-400 bg-blue-500/10';
    }
  };

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-slate-100">URL 重写规则</h3>
          <p className="text-xs text-slate-500 mt-1">
            Surge 兼容格式：URL 正则匹配 → 拦截/重定向/修改请求头
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => save(rules)}
            disabled={saving}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium transition-colors disabled:opacity-50"
          >
            <Save size={14} /> {saving ? '保存中…' : '保存'}
          </button>
          <button
            onClick={() => setShowAdd(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-xs font-medium transition-colors"
          >
            <Plus size={14} /> 添加规则
          </button>
        </div>
      </div>

      {/* Add rule form */}
      {showAdd && (
        <div className="bg-slate-800/50 border border-slate-700 rounded-xl p-4 space-y-3">
          <h4 className="text-sm font-medium text-slate-300">新建规则</h4>
          <div>
            <label className="block text-xs text-slate-400 mb-1">URL 正则模式</label>
            <input
              type="text"
              value={newPattern}
              onChange={(e) => setNewPattern(e.target.value)}
              placeholder="^https?://.*\\.doubleclick\\.net/.*"
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-sm text-slate-100 font-mono focus:outline-none focus:border-blue-500"
            />
          </div>
          <div>
            <label className="block text-xs text-slate-400 mb-1">动作类型</label>
            <select
              value={newActionType}
              onChange={(e) => setNewActionType(e.target.value)}
              className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
            >
              <option value="Reject">拦截 (REJECT)</option>
              <option value="Redirect">重定向 (REDIRECT)</option>
              <option value="ModifyHeader">修改请求头</option>
              <option value="ModifyResponseHeader">修改响应头</option>
            </select>
          </div>
          {newActionType === 'Redirect' && (
            <div>
              <label className="block text-xs text-slate-400 mb-1">目标 URL</label>
              <input
                type="text"
                value={newRedirectUrl}
                onChange={(e) => setNewRedirectUrl(e.target.value)}
                placeholder="https://example.com"
                className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
              />
            </div>
          )}
          {(newActionType === 'ModifyHeader' || newActionType === 'ModifyResponseHeader') && (
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="block text-xs text-slate-400 mb-1">Header 名称</label>
                <input
                  type="text"
                  value={newHeaderKey}
                  onChange={(e) => setNewHeaderKey(e.target.value)}
                  placeholder="User-Agent"
                  className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs text-slate-400 mb-1">Header 值</label>
                <input
                  type="text"
                  value={newHeaderValue}
                  onChange={(e) => setNewHeaderValue(e.target.value)}
                  placeholder="Mozilla/5.0"
                  className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
                />
              </div>
            </div>
          )}
          <div className="flex items-center justify-end gap-2">
            <button
              onClick={() => setShowAdd(false)}
              className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200"
            >
              取消
            </button>
            <button
              onClick={addRule}
              disabled={!newPattern.trim()}
              className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium disabled:opacity-50"
            >
              添加
            </button>
          </div>
        </div>
      )}

      {/* Rules list */}
      {rules.length === 0 ? (
        <div className="text-center py-8 text-slate-500 text-sm">
          暂无规则。点击"添加规则"创建第一条。
        </div>
      ) : (
        <div className="space-y-2">
          {rules.map((rule) => (
            <div
              key={rule.id}
              className={`flex items-center gap-3 p-3 bg-slate-900/50 border border-slate-800 rounded-xl ${!rule.enabled ? 'opacity-50' : ''}`}
            >
              <button
                onClick={() => toggleRule(rule.id, !rule.enabled)}
                className={`p-1 rounded transition-colors ${rule.enabled ? 'text-emerald-400 hover:text-emerald-300' : 'text-slate-600 hover:text-slate-400'}`}
                title={rule.enabled ? '禁用' : '启用'}
              >
                <Power size={16} />
              </button>
              <div className="flex-1 min-w-0">
                <div className="text-sm text-slate-200 font-mono truncate">{rule.pattern}</div>
                <div className="text-xs mt-0.5">
                  <span className={`px-1.5 py-0.5 rounded text-[10px] ${actionColor(rule.action)}`}>
                    {actionLabel(rule.action)}
                  </span>
                </div>
              </div>
              <button
                onClick={() => deleteRule(rule.id)}
                className="p-1 text-slate-500 hover:text-red-400 transition-colors"
                title="删除"
              >
                <Trash2 size={16} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
