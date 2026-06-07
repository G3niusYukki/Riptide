// Overrides — main page. Hosts the 3 sub-views (List / Editor / Apply)
// behind a small tab strip. The active tab and the active override
// pointer both live in `useOverridesStore` so the tabs are routable
// and the editor/apply views can survive tab switches without losing
// state.
//
// Phase C2 UI shell: the underlying IPC wrappers are not implemented
// (see services/tauri.ts → `listOverrides` / `createOverride` / etc.).
// The sub-views handle the rejection gracefully; this page just
// composes them.

import { useEffect, useState } from 'react';
import { List, Edit3, Play, Plus } from 'lucide-react';
import { OverrideListView } from './OverrideListView';
import { OverrideEditorView } from './OverrideEditorView';
import { OverrideApplyView } from './OverrideApplyView';
import { useOverridesStore } from '../../stores/overrides';
import type { Override } from '../../types/override';

type TabKey = 'list' | 'editor' | 'apply';

const TABS: { key: TabKey; label: string; icon: typeof List }[] = [
  { key: 'list', label: '列表', icon: List },
  { key: 'editor', label: '编辑', icon: Edit3 },
  { key: 'apply', label: '预览 & 应用', icon: Play },
];

export function Overrides() {
  const activeId = useOverridesStore((s) => s.activeId);
  const setActiveId = useOverridesStore((s) => s.setActiveId);
  const [tab, setTab] = useState<TabKey>('list');
  const [createMode, setCreateMode] = useState(false);

  // When the active override disappears (e.g. user deletes it from
  // the list), drop the editor/apply panes back to "no selection".
  useEffect(() => {
    if (activeId === null && (tab === 'editor' || tab === 'apply') && !createMode) {
      setTab('list');
    }
  }, [activeId, tab, createMode]);

  const handleRequestNew = () => {
    setCreateMode(true);
    setActiveId(null);
    setTab('editor');
  };

  const handleSelectFromList = (override: Override) => {
    setActiveId(override.id);
    setCreateMode(false);
    setTab('editor');
  };

  return (
    <div className="space-y-5" data-testid="overrides-page">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-slate-100">配置覆盖</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            基于当前激活的配置叠加部分 YAML — 后端尚未实现,UI shell 阶段。
          </p>
        </div>
        <button
          type="button"
          onClick={handleRequestNew}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
          data-testid="overrides-new-button"
        >
          <Plus size={14} />
          新建覆盖
        </button>
      </div>

      <div
        className="flex items-center gap-1 border-b border-slate-800"
        role="tablist"
        aria-label="Override tabs"
      >
        {TABS.map((t) => {
          const Icon = t.icon;
          const selected = t.key === tab;
          return (
            <button
              key={t.key}
              role="tab"
              type="button"
              aria-selected={selected}
              onClick={() => {
                if (t.key !== 'editor') setCreateMode(false);
                setTab(t.key);
              }}
              className={`
                flex items-center gap-1.5 px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors
                ${selected
                  ? 'text-blue-300 border-blue-400'
                  : 'text-slate-400 border-transparent hover:text-slate-200'}
              `}
              data-testid={`overrides-tab-${t.key}`}
            >
              <Icon size={14} />
              {t.label}
            </button>
          );
        })}
      </div>

      <div role="tabpanel" data-testid={`overrides-panel-${tab}`}>
        {tab === 'list' && <OverrideListView onRequestNew={handleRequestNew} onSelect={handleSelectFromList} />}
        {tab === 'editor' && <OverrideEditorView createMode={createMode} />}
        {tab === 'apply' && <OverrideApplyView />}
      </div>
    </div>
  );
}
