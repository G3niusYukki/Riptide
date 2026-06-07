// OverrideApplyView — preview + apply the active override on the active profile.
//
// Phase C2 UI shell: the preview pane and the "Apply" button both call
// the not-implemented `previewOverride` / `applyOverride` IPC wrappers.
// The component catches the rejection and renders an explicit
// "backend pending" banner, plus the Apply button is disabled until
// the wrapper returns a successful resolution. The merge itself (and
// the diff rendering) is intentionally local-stub: we render the
// override's rawYAML verbatim in a CodeMirror read-only view so the
// operator can eyeball it, but we never claim the merge is final.

import { useEffect, useMemo, useState } from 'react';
import { Play, Eye, AlertTriangle, Loader2, FileCode2, Layers } from 'lucide-react';
import { YamlViewer } from '../YamlEditor';
import {
  useOverridesStore,
  selectActiveOverride,
} from '../../stores/overrides';
import {
  applyOverride,
  isNotImplementedError,
  previewOverride,
} from '../../services/tauri';
import type { ApplyResult, Override } from '../../types/override';

type ApplyState =
  | { kind: 'idle' }
  | { kind: 'previewing' }
  | { kind: 'preview-error'; message: string }
  | { kind: 'applying' }
  | { kind: 'apply-error'; message: string }
  | { kind: 'apply-success'; result: ApplyResult };

export function OverrideApplyView() {
  const active = useOverridesStore(selectActiveOverride);
  const setError = useOverridesStore((s) => s.setError);
  const [applyState, setApplyState] = useState<ApplyState>({ kind: 'idle' });

  useEffect(() => {
    // Reset transient state when the active override changes — the
    // preview/result panels are tied 1:1 to the active override.
    setApplyState({ kind: 'idle' });
  }, [active?.id]);

  const handlePreview = async () => {
    if (!active) return;
    setApplyState({ kind: 'previewing' });
    try {
      const result = await previewOverride(active.id, null);
      setApplyState({ kind: 'apply-success', result });
    } catch (err) {
      if (isNotImplementedError(err)) {
        setApplyState({
          kind: 'preview-error',
          message:
            '后端尚未实现 — 预览需等 Phase C2 后续 task 把 Rust Override 存储模块接入。',
        });
        return;
      }
      setApplyState({ kind: 'preview-error', message: extractMessage(err) });
    }
  };

  const handleApply = async () => {
    if (!active) return;
    setApplyState({ kind: 'applying' });
    try {
      const result = await applyOverride(active.id, null);
      setApplyState({ kind: 'apply-success', result });
    } catch (err) {
      if (isNotImplementedError(err)) {
        setApplyState({
          kind: 'apply-error',
          message:
            '后端尚未实现 — Apply 需等 Phase C2 后续 task 把 Rust Override 存储模块接入。',
        });
        return;
      }
      setApplyState({ kind: 'apply-error', message: extractMessage(err) });
      setError(extractMessage(err));
    }
  };

  const applyDisabled = useMemo(() => {
    if (!active) return true;
    if (applyState.kind === 'applying') return true;
    if (applyState.kind === 'previewing') return true;
    // Apply requires a successful preview first — without it, the
    // user is firing blind. The mock backend never returns a preview
    // result, so this stays disabled until Phase C2 wires the Rust
    // module and a real preview lands.
    if (applyState.kind !== 'apply-success') return true;
    return false;
  }, [active, applyState]);

  if (!active) {
    return (
      <div className="space-y-4" data-testid="override-apply-view">
        <h2 className="text-xl font-bold text-slate-100">预览 & 应用</h2>
        <div
          className="bg-slate-900/50 border border-slate-800 border-dashed rounded-xl p-10 text-center"
          data-testid="override-apply-empty"
        >
          <Layers size={36} className="mx-auto text-slate-600 mb-3" />
          <p className="text-slate-400 text-sm">先在列表中选择一个覆盖配置</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4" data-testid="override-apply-view">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-slate-100">预览 & 应用</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            当前覆盖:<span className="text-slate-300 font-medium">{active.name}</span>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handlePreview}
            disabled={!active || applyState.kind === 'previewing' || applyState.kind === 'applying'}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 disabled:cursor-not-allowed"
            data-testid="override-preview"
          >
            {applyState.kind === 'previewing' ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Eye size={14} />
            )}
            预览
          </button>
          <button
            type="button"
            onClick={handleApply}
            disabled={applyDisabled}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 disabled:cursor-not-allowed"
            data-testid="override-apply"
            aria-disabled={applyDisabled}
          >
            {applyState.kind === 'applying' ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Play size={14} />
            )}
            {applyState.kind === 'applying' ? '应用中…' : '应用'}
          </button>
        </div>
      </div>

      <PendingBanner state={applyState} />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <section
          className="bg-slate-900/50 border border-slate-800 rounded-xl p-4"
          data-testid="override-raw-section"
        >
          <h3 className="text-sm font-semibold text-slate-200 mb-2 flex items-center gap-2">
            <FileCode2 size={14} className="text-slate-500" />
            覆盖 YAML (只读)
          </h3>
          <YamlViewer value={active.rawYAML} height="260px" />
        </section>
        <section
          className="bg-slate-900/50 border border-slate-800 rounded-xl p-4"
          data-testid="override-preview-section"
        >
          <h3 className="text-sm font-semibold text-slate-200 mb-2 flex items-center gap-2">
            <Layers size={14} className="text-slate-500" />
            合并结果预览
          </h3>
          {applyState.kind === 'apply-success' ? (
            <div className="space-y-2">
              <p className="text-xs text-slate-400" data-testid="override-touched">
                触及: {applyState.result.touched.length === 0
                  ? '(无)'
                  : applyState.result.touched.join(', ')}
              </p>
              <p className="text-xs text-slate-400" data-testid="override-removed">
                移除: {applyState.result.removed.length === 0
                  ? '(无)'
                  : applyState.result.removed.join(', ')}
              </p>
              <YamlViewer value={applyState.result.mergedYAML} height="220px" />
            </div>
          ) : (
            <div className="h-[260px] flex items-center justify-center text-slate-600 text-xs">
              {applyState.kind === 'previewing'
                ? '生成预览中…'
                : applyState.kind === 'applying'
                ? '应用中…'
                : '点击"预览"以生成合并后的 YAML。'}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}

function PendingBanner({ state }: { state: ApplyState }) {
  if (state.kind !== 'preview-error' && state.kind !== 'apply-error') return null;
  return (
    <div
      className="bg-amber-900/20 border border-amber-800/60 rounded-lg px-4 py-3 flex items-center gap-3"
      data-testid="override-apply-pending"
    >
      <AlertTriangle size={16} className="text-amber-400 flex-shrink-0" />
      <p className="text-amber-200 text-sm">{state.message}</p>
    </div>
  );
}

function extractMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

// Re-export the override type so the consumer of this module can type
// their handlers without re-importing from `types/override`.
export type { Override };
