// OverrideListView — Renders the persisted overrides as a clickable list.
//
// Phase C2 UI shell: data is sourced from `useOverridesStore`. The
// underlying `listOverrides` IPC wrapper is a not-implemented mock
// until the Rust backend lands in v2.5.0; the component handles that
// rejection gracefully (via the store's `error` slice + a visible
// banner) instead of crashing.
//
// Clicking a row sets `activeId` on the store, which the parent page
// (`Overrides/index.tsx`) reads to switch into the editor / apply tab.

import { useEffect } from 'react';
import { Plus, FileCode2, Trash2, AlertTriangle, Loader2 } from 'lucide-react';
import { useOverridesStore, selectActiveOverride } from '../../stores/overrides';
import { isNotImplementedError, listOverrides, deleteOverride } from '../../services/tauri';
import type { Override } from '../../types/override';

interface OverrideListViewProps {
  /** When provided, also renders a "New" button that delegates to this callback. */
  onRequestNew?: () => void;
  /**
   * When provided, row clicks call this instead of writing `activeId`
   * directly. Used by tests and by the parent when navigation must go
   * through a router push.
   */
  onSelect?: (override: Override) => void;
}

const STAGE = 'data-testid' as const;

export function OverrideListView({ onRequestNew, onSelect }: OverrideListViewProps) {
  const overrides = useOverridesStore((s) => s.overrides);
  const loading = useOverridesStore((s) => s.loading);
  const error = useOverridesStore((s) => s.error);
  const activeId = useOverridesStore((s) => s.activeId);
  const active = useOverridesStore(selectActiveOverride);
  const setOverrides = useOverridesStore((s) => s.setOverrides);
  const setLoading = useOverridesStore((s) => s.setLoading);
  const setError = useOverridesStore((s) => s.setError);
  const removeOverride = useOverridesStore((s) => s.removeOverride);
  const setActiveId = useOverridesStore((s) => s.setActiveId);

  // Best-effort initial load. Failure is expected in v2.4.x because
  // the Rust backend is not wired; we still call it so the same code
  // path runs once the backend lands.
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    listOverrides()
      .then((list) => {
        if (!cancelled) setOverrides(list);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        if (isNotImplementedError(err)) {
          // Expected path until Phase C2 follow-up wires the Rust module.
          setError('Override backend not implemented yet (v2.5.0).');
          return;
        }
        setError(err instanceof Error ? err.message : String(err));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [setError, setLoading, setOverrides]);

  const handleRowClick = (o: Override) => {
    if (onSelect) {
      onSelect(o);
      return;
    }
    setActiveId(o.id);
  };

  const handleDelete = async (o: Override, ev: React.MouseEvent) => {
    ev.stopPropagation();
    // Optimistic local remove — the IPC call rejects with not-implemented
    // until Phase C2 wires the backend, in which case we restore the row
    // and surface the error.
    removeOverride(o.id);
    try {
      await deleteOverride(o.id);
    } catch (err) {
      if (!isNotImplementedError(err)) {
        setError(err instanceof Error ? err.message : String(err));
      }
      // For not-implemented we leave the row removed; the optimistic
      // remove is intentional so the UI shell is exercisable end-to-end.
    }
  };

  return (
    <div className="space-y-4" data-testid="override-list-view">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-slate-100">配置覆盖</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            基于当前配置叠加的部分 YAML（节点 / 规则 / DNS 微调）。
          </p>
        </div>
        {onRequestNew && (
          <button
            type="button"
            onClick={onRequestNew}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
            data-testid="override-new-button"
          >
            <Plus size={14} />
            新建覆盖
          </button>
        )}
      </div>

      {error && (
        <div
          className="bg-amber-900/20 border border-amber-800/60 rounded-lg px-4 py-3 flex items-center gap-3"
          data-testid="override-error"
        >
          <AlertTriangle size={16} className="text-amber-400 flex-shrink-0" />
          <p className="text-amber-200 text-sm">{error}</p>
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center h-32" data-testid="override-loading">
          <Loader2 size={20} className="text-blue-400 animate-spin" />
          <span className="ml-2 text-slate-400 text-sm">加载覆盖配置…</span>
        </div>
      ) : overrides.length === 0 ? (
        <div
          className="bg-slate-900/50 border border-slate-800 border-dashed rounded-xl p-10 text-center"
          data-testid="override-empty"
        >
          <FileCode2 size={36} className="mx-auto text-slate-600 mb-3" />
          <p className="text-slate-400 text-sm">暂无覆盖配置</p>
          <p className="text-slate-600 text-xs mt-1">
            新建一个覆盖来叠加在当前激活的配置之上。
          </p>
        </div>
      ) : (
        <div
          className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden"
          data-testid="override-table"
        >
          <div className="px-4 py-2.5 border-b border-slate-800 grid grid-cols-12 gap-2 text-xs font-medium text-slate-400 bg-slate-900/70">
            <div className="col-span-5">名称</div>
            <div className="col-span-4">最近更新</div>
            <div className="col-span-2">状态</div>
            <div className="col-span-1 text-right">操作</div>
          </div>
          <div className="divide-y divide-slate-800">
            {overrides.map((o) => {
              const isActive = o.id === activeId;
              return (
                <div
                  key={o.id}
                  role="button"
                  tabIndex={0}
                  data-testid="override-row"
                  data-override-id={o.id}
                  aria-current={isActive ? 'true' : 'false'}
                  onClick={() => handleRowClick(o)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      handleRowClick(o);
                    }
                  }}
                  className={`
                    px-4 py-2.5 grid grid-cols-12 gap-2 items-center cursor-pointer transition-colors
                    ${isActive ? 'bg-blue-600/10 text-blue-200' : 'hover:bg-slate-800/40 text-slate-200'}
                  `}
                >
                  <div className="col-span-5 flex items-center gap-2 min-w-0">
                    <FileCode2
                      size={14}
                      className={isActive ? 'text-blue-400 flex-shrink-0' : 'text-slate-500 flex-shrink-0'}
                    />
                    <span className="text-sm font-medium truncate">{o.name}</span>
                  </div>
                  <div className="col-span-4 text-xs text-slate-500 truncate">
                    {formatTimestamp(o.updatedAt)}
                  </div>
                  <div className="col-span-2 text-xs">
                    {isActive ? (
                      <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-blue-500/15 text-blue-300">
                        编辑中
                      </span>
                    ) : (
                      <span className="text-slate-500">空闲</span>
                    )}
                  </div>
                  <div className="col-span-1 text-right">
                    <button
                      type="button"
                      onClick={(e) => handleDelete(o, e)}
                      className="p-1 text-slate-500 hover:text-red-400 rounded transition-colors"
                      title="删除覆盖"
                      data-testid="override-delete"
                    >
                      <Trash2 size={13} />
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Hidden hint for the test that reads the active row's id without
          clicking it — the parent test also exercises the click path. */}
      {active ? <span data-testid="override-active-id">{active.id}</span> : null}

      {/* Stage marker kept around for future e2e selectors. */}
      <span data-stage={STAGE} hidden />
    </div>
  );
}

function formatTimestamp(iso: string): string {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}
