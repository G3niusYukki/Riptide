// OverrideEditorView — YAML editor for the active Override.
//
// Phase C2 UI shell: the editor binds to the `activeId` slice in
// `useOverridesStore`, reuses the shared `YamlEditor` CodeMirror
// component (see `components/YamlEditor.tsx`), and calls the
// not-implemented `createOverride` / `updateOverride` IPC wrappers on
// save. The `isNotImplementedError` predicate is what tests assert on
// to prove the save call reached the wrapper surface.

import { useEffect, useMemo, useState } from 'react';
import { Save, RotateCcw, AlertTriangle, CheckCircle2, Loader2 } from 'lucide-react';
import { YamlEditor } from '../YamlEditor';
import {
  useOverridesStore,
  selectActiveOverride,
} from '../../stores/overrides';
import {
  createOverride,
  isNotImplementedError,
  updateOverride,
} from '../../services/tauri';
import type { Override, OverrideDraft } from '../../types/override';

interface OverrideEditorViewProps {
  /**
   * If set, "Save" creates a new override (passes name + rawYAML).
   * Otherwise the editor updates the currently-active override.
   */
  createMode?: boolean;
  onSaved?: (override: Override) => void;
}

type SaveState =
  | { kind: 'idle' }
  | { kind: 'saving' }
  | { kind: 'success'; message: string }
  | { kind: 'error'; message: string };

export function OverrideEditorView({ createMode = false, onSaved }: OverrideEditorViewProps) {
  const active = useOverridesStore(selectActiveOverride);
  const upsertOverride = useOverridesStore((s) => s.upsertOverride);

  const [draft, setDraft] = useState<OverrideDraft>(initialDraft(createMode));
  const [saveState, setSaveState] = useState<SaveState>({ kind: 'idle' });
  const [dirty, setDirty] = useState(false);

  // Sync the local draft when the active override changes, or when
  // createMode flips on (e.g. user clicks "New" from the list view).
  useEffect(() => {
    if (createMode) {
      setDraft(initialDraft(true));
      setDirty(false);
      setSaveState({ kind: 'idle' });
      return;
    }
    if (active) {
      setDraft({
        name: active.name,
        rawYAML: active.rawYAML,
        meta: parseMeta(active.rawYAML),
      });
      setDirty(false);
      setSaveState({ kind: 'idle' });
    }
  }, [active, createMode]);

  const headline = useMemo(() => {
    if (createMode) return '新建覆盖';
    if (!active) return '未选择覆盖';
    return `编辑：${active.name}`;
  }, [active, createMode]);

  const handleSave = async () => {
    if (!draft.name.trim() || !draft.rawYAML.trim()) return;
    setSaveState({ kind: 'saving' });
    try {
      let saved: Override;
      if (createMode || !active) {
        saved = await createOverride(draft.name, draft.rawYAML);
      } else {
        saved = await updateOverride(active.id, draft.name, draft.rawYAML);
      }
      upsertOverride(saved);
      setDirty(false);
      setSaveState({
        kind: 'success',
        message: createMode ? '已新建（mock 写入）' : '已保存（mock 写入）',
      });
      onSaved?.(saved);
    } catch (err) {
      if (isNotImplementedError(err)) {
        setSaveState({
          kind: 'error',
          message:
            '后端尚未实现 — 此为 UI shell,Rust Override 存储模块在 v2.5.0 (Phase C2 后续 task) 落地。',
        });
        return;
      }
      setSaveState({ kind: 'error', message: err instanceof Error ? err.message : String(err) });
    }
  };

  const handleReset = () => {
    if (createMode || !active) {
      setDraft(initialDraft(true));
    } else {
      setDraft({
        name: active.name,
        rawYAML: active.rawYAML,
        meta: parseMeta(active.rawYAML),
      });
    }
    setDirty(false);
    setSaveState({ kind: 'idle' });
  };

  const isSaving = saveState.kind === 'saving';
  const canSave =
    draft.name.trim().length > 0 && draft.rawYAML.trim().length > 0 && !isSaving;

  return (
    <div className="space-y-4" data-testid="override-editor-view">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-slate-100">{headline}</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            {createMode
              ? '填写名称与 YAML 后保存到 mock 后端(尚未实现)。'
              : '修改后保存,会调用 mock update 包装器(尚未实现)。'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleReset}
            disabled={isSaving || !dirty}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 disabled:cursor-not-allowed"
            data-testid="override-reset"
          >
            <RotateCcw size={14} />
            重置
          </button>
          <button
            type="button"
            onClick={handleSave}
            disabled={!canSave}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50 disabled:cursor-not-allowed"
            data-testid="override-save"
          >
            {isSaving ? <Loader2 size={14} className="animate-spin" /> : <Save size={14} />}
            {isSaving ? '保存中…' : '保存'}
          </button>
        </div>
      </div>

      {!createMode && !active ? (
        <div
          className="bg-slate-900/50 border border-slate-800 border-dashed rounded-xl p-10 text-center"
          data-testid="override-editor-empty"
        >
          <p className="text-slate-400 text-sm">从列表中选择一项,或点击"新建覆盖"。</p>
        </div>
      ) : (
        <div className="space-y-3" data-testid="override-editor-form">
          <div>
            <label
              htmlFor="override-name"
              className="block text-xs font-medium text-slate-300 mb-1"
            >
              名称
            </label>
            <input
              id="override-name"
              type="text"
              value={draft.name}
              onChange={(e) => {
                setDraft((d) => ({ ...d, name: e.target.value }));
                setDirty(true);
              }}
              placeholder="my-dns-override"
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30"
              data-testid="override-name"
            />
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label htmlFor="override-yaml" className="block text-xs font-medium text-slate-300">
                YAML
              </label>
              <span
                className={`text-[10px] ${
                  draft.meta.replace ? 'text-amber-300' : 'text-slate-500'
                }`}
                data-testid="override-meta-flag"
              >
                meta.replace = {String(draft.meta.replace ?? false)}
              </span>
            </div>
            <div data-testid="override-yaml-editor">
              <YamlEditor
                value={draft.rawYAML}
                onChange={(v) => {
                  setDraft((d) => ({ ...d, rawYAML: v, meta: parseMeta(v) }));
                  setDirty(true);
                }}
                height="320px"
              />
            </div>
          </div>
        </div>
      )}

      {saveState.kind === 'error' && (
        <div
          className="bg-red-900/20 border border-red-800 rounded-lg px-4 py-3 flex items-center gap-3"
          data-testid="override-save-error"
        >
          <AlertTriangle size={16} className="text-red-400 flex-shrink-0" />
          <p className="text-red-300 text-sm">{saveState.message}</p>
        </div>
      )}
      {saveState.kind === 'success' && (
        <div
          className="bg-emerald-900/20 border border-emerald-800 rounded-lg px-4 py-3 flex items-center gap-3"
          data-testid="override-save-success"
        >
          <CheckCircle2 size={16} className="text-emerald-400 flex-shrink-0" />
          <p className="text-emerald-300 text-sm">{saveState.message}</p>
        </div>
      )}

      {/* Reserved hook for future "delete from here" affordance. */}
      <span hidden aria-hidden="true" data-testid="override-editor-ping">
        ready
      </span>
    </div>
  );
}

function initialDraft(createMode: boolean): OverrideDraft {
  if (!createMode) {
    return { name: '', rawYAML: '', meta: {} };
  }
  const seed = `# Override YAML — applied on top of the active profile.
# Use meta.replace: true to switch list-merge from "append" to
# "replace-by-name". The \`removed:\` directive drops named entries
# from any list-section.
#
# Example:
# meta:
#   replace: false
# dns:
#   enable: true
#   enhanced-mode: fake-ip
`;
  return { name: '', rawYAML: seed, meta: parseMeta(seed) };
}

function parseMeta(yaml: string): { replace?: boolean } {
  // Tiny line-based peek — full YAML parse happens on the Rust side.
  // We only care about whether `meta.replace: true` was set.
  const lines = yaml.split(/\r?\n/);
  let inMeta = false;
  for (const line of lines) {
    if (/^\s*meta\s*:\s*$/.test(line)) {
      inMeta = true;
      continue;
    }
    if (inMeta) {
      const m = line.match(/^\s+replace\s*:\s*(true|false)\s*$/);
      if (m) return { replace: m[1] === 'true' };
      // End of meta block on a non-indented sibling key.
      if (/^\S/.test(line)) inMeta = false;
    }
  }
  return {};
}
