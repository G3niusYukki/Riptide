// SceneEditorView — visual editor for the Windows Scene subsystem.
//
// Mirrors the macOS `SceneEditorView` (Sources/RiptideApp/Views/Scenes/
// SceneEditorView.swift) with a process / domain / IP-set matcher
// model and a mode-override picker. The MVP keeps CRUD simple: add,
// edit, delete, plus a `scene_apply` probe row so the user can verify
// a connection tuple against the persisted rules.
//
// Three matcher kinds render side-by-side; each scene can mix and
// match (logical OR). The disabled scenes are kept on disk but
// greyed out so the user can flip them back on without re-typing.

import { useEffect, useState, useMemo } from 'react';
import {
  Plus,
  Trash2,
  Edit3,
  Power,
  Play,
  Loader2,
  AlertTriangle,
  AppWindow,
  Globe,
  Network,
  Check,
} from 'lucide-react';
import {
  sceneList,
  sceneCreate,
  sceneUpdate,
  sceneDelete,
  sceneApply,
} from '../../services/tauri';
import {
  MATCHER_KIND_LABEL,
  MODE_OVERRIDE_LABEL,
  type Matcher,
  type MatcherKind,
  type ModeOverride,
  type Scene,
} from '../../types/scene';

interface SceneEditorViewProps {
  /** Optional: bypass the IPC call (tests). */
  initialScenes?: Scene[];
}

const STAGE = 'data-testid' as const;

/** Build a blank `Scene` payload for `scene_create`. */
function blankScene(): Omit<Scene, 'id' | 'created_at' | 'updated_at'> {
  return {
    name: '',
    mode: 'system_proxy',
    enabled: true,
    matchers: [],
  };
}

export function SceneEditorView({ initialScenes }: SceneEditorViewProps = {}) {
  const [scenes, setScenes] = useState<Scene[]>(initialScenes ?? []);
  const [editing, setEditing] = useState<Scene | null>(null);
  const [loading, setLoading] = useState(initialScenes === undefined);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  // Probe row state — for `scene_apply`.
  const [probeProcess, setProbeProcess] = useState('chrome.exe');
  const [probeDomain, setProbeDomain] = useState('example.com');
  const [probeIp, setProbeIp] = useState('10.0.0.5');
  const [probeResult, setProbeResult] = useState<string | null>(null);
  const [probing, setProbing] = useState(false);

  // Initial load. When `initialScenes` is provided (tests), we skip
  // the IPC call.
  useEffect(() => {
    if (initialScenes !== undefined) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    sceneList(true)
      .then((rows) => {
        if (cancelled) return;
        // The Rust side returns `Vec<Scene>` when `full=true`. The
        // list-shape variant is `Vec<SceneSummary>`; we always ask
        // for full here.
        setScenes(rows as Scene[]);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : String(err));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialScenes]);

  const startNew = () => setEditing({ ...blankScene(), id: '', created_at: '', updated_at: '' } as Scene);
  const startEdit = (s: Scene) => setEditing({ ...s, matchers: s.matchers.map(cloneMatcher) });

  const handleSave = async () => {
    if (!editing) return;
    if (editing.name.trim() === '') {
      setError('场景名称不能为空');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const payload = {
        ...editing,
        matchers: editing.matchers.filter((m) => matcherHasValue(m)),
      };
      if (!payload.id) {
        const created = await sceneCreate(payload);
        setScenes((prev) => [...prev, created]);
      } else {
        const updated = await sceneUpdate(payload);
        setScenes((prev) => prev.map((s) => (s.id === updated.id ? updated : s)));
      }
      setEditing(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (s: Scene) => {
    if (!s.id) return;
    setError(null);
    try {
      await sceneDelete(s.id);
      setScenes((prev) => prev.filter((x) => x.id !== s.id));
      if (editing?.id === s.id) setEditing(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const handleToggleEnabled = async (s: Scene) => {
    if (!s.id) return;
    const next = { ...s, enabled: !s.enabled };
    try {
      const updated = await sceneUpdate(next);
      setScenes((prev) => prev.map((x) => (x.id === updated.id ? updated : x)));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  };

  const handleProbe = async () => {
    setProbing(true);
    setProbeResult(null);
    try {
      const r = await sceneApply(probeProcess, probeDomain, probeIp);
      if (r.matched && r.mode && r.scene_name) {
        setProbeResult(`命中「${r.scene_name}」→ 切换到 ${MODE_OVERRIDE_LABEL[r.mode]}`);
      } else {
        setProbeResult('无匹配 — 沿用当前模式');
      }
    } catch (err) {
      setProbeResult(`错误: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      setProbing(false);
    }
  };

  return (
    <div className="space-y-5" data-testid="scene-editor-view">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-slate-100">场景编辑器</h2>
          <p className="text-xs text-slate-500 mt-0.5">
            通过进程 / 域名 / IP 集三类规则,在匹配时自动覆盖代理模式。
          </p>
        </div>
        <button
          type="button"
          onClick={startNew}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50"
          data-testid="scene-new"
        >
          <Plus size={14} />
          新建场景
        </button>
      </div>

      {error && (
        <div
          className="bg-red-900/20 border border-red-800/60 rounded-lg px-4 py-3 flex items-center gap-3"
          data-testid="scene-error"
        >
          <AlertTriangle size={16} className="text-red-400 flex-shrink-0" />
          <p className="text-red-200 text-sm">{error}</p>
        </div>
      )}

      {editing ? (
        <SceneForm
          scene={editing}
          saving={saving}
          onChange={setEditing}
          onSave={handleSave}
          onCancel={() => setEditing(null)}
        />
      ) : null}

      {/* Probe row — verify a connection tuple against the saved rules. */}
      <section
        className="bg-slate-900/50 border border-slate-800 rounded-xl p-4 space-y-3"
        data-testid="scene-probe"
      >
        <div className="flex items-center gap-2 text-slate-200 text-sm font-medium">
          <Play size={14} className="text-blue-400" />
          模拟连接
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <ProbeField
            label="进程名"
            value={probeProcess}
            onChange={setProbeProcess}
            testid="scene-probe-process"
          />
          <ProbeField
            label="域名"
            value={probeDomain}
            onChange={setProbeDomain}
            testid="scene-probe-domain"
          />
          <ProbeField
            label="IP"
            value={probeIp}
            onChange={setProbeIp}
            testid="scene-probe-ip"
          />
        </div>
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={handleProbe}
            disabled={probing}
            data-testid="scene-probe-run"
            className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/40 rounded-md text-xs text-blue-200 transition-colors disabled:opacity-50"
          >
            {probing ? <Loader2 size={12} className="animate-spin" /> : <Play size={12} />}
            匹配
          </button>
          {probeResult && (
            <span className="text-xs text-slate-300" data-testid="scene-probe-result">
              {probeResult}
            </span>
          )}
        </div>
      </section>

      {loading ? (
        <div className="flex items-center justify-center h-32" data-testid="scene-loading">
          <Loader2 size={20} className="text-blue-400 animate-spin" />
          <span className="ml-2 text-slate-400 text-sm">加载场景…</span>
        </div>
      ) : scenes.length === 0 ? (
        <div
          className="bg-slate-900/50 border border-slate-800 border-dashed rounded-xl p-10 text-center"
          data-testid="scene-empty"
        >
          <Network size={36} className="mx-auto text-slate-600 mb-3" />
          <p className="text-slate-400 text-sm">暂无场景</p>
          <p className="text-slate-600 text-xs mt-1">
            新建一个场景来定义自动覆盖的规则。
          </p>
        </div>
      ) : (
        <div
          className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden"
          data-testid="scene-table"
        >
          <div className="px-4 py-2.5 border-b border-slate-800 grid grid-cols-12 gap-2 text-xs font-medium text-slate-400 bg-slate-900/70">
            <div className="col-span-3">名称</div>
            <div className="col-span-3">覆盖模式</div>
            <div className="col-span-3">匹配器</div>
            <div className="col-span-1">启用</div>
            <div className="col-span-2 text-right">操作</div>
          </div>
          <div className="divide-y divide-slate-800">
            {scenes.map((s) => (
              <SceneRow
                key={s.id}
                scene={s}
                onEdit={() => startEdit(s)}
                onDelete={() => handleDelete(s)}
                onToggle={() => handleToggleEnabled(s)}
              />
            ))}
          </div>
        </div>
      )}
      <span data-stage={STAGE} hidden />
    </div>
  );
}

// ── Row ─────────────────────────────────────────────────────────

interface SceneRowProps {
  scene: Scene;
  onEdit: () => void;
  onDelete: () => void;
  onToggle: () => void;
}

function SceneRow({ scene, onEdit, onDelete, onToggle }: SceneRowProps) {
  return (
    <div
      className="px-4 py-2.5 grid grid-cols-12 gap-2 items-center hover:bg-slate-800/40 transition-colors"
      data-testid="scene-row"
      data-scene-id={scene.id}
    >
      <div className="col-span-3 text-sm text-slate-100 font-medium truncate">
        {scene.name || <span className="text-slate-500">(未命名)</span>}
      </div>
      <div className="col-span-3 text-xs text-slate-300">
        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-blue-500/15 text-blue-300">
          {MODE_OVERRIDE_LABEL[scene.mode]}
        </span>
      </div>
      <div className="col-span-3 text-xs text-slate-400 truncate" data-testid="scene-row-kinds">
        {summarizeMatchers(scene.matchers)}
      </div>
      <div className="col-span-1">
        <button
          type="button"
          onClick={onToggle}
          className={`p-1 rounded transition-colors ${
            scene.enabled
              ? 'text-emerald-400 hover:text-emerald-300'
              : 'text-slate-500 hover:text-slate-300'
          }`}
          data-testid="scene-row-toggle"
          title={scene.enabled ? '已启用' : '已禁用'}
        >
          <Power size={13} />
        </button>
      </div>
      <div className="col-span-2 flex items-center justify-end gap-1">
        <button
          type="button"
          onClick={onEdit}
          data-testid="scene-row-edit"
          className="p-1 text-slate-500 hover:text-blue-400 rounded transition-colors"
          title="编辑"
        >
          <Edit3 size={13} />
        </button>
        <button
          type="button"
          onClick={onDelete}
          data-testid="scene-row-delete"
          className="p-1 text-slate-500 hover:text-red-400 rounded transition-colors"
          title="删除"
        >
          <Trash2 size={13} />
        </button>
      </div>
    </div>
  );
}

function summarizeMatchers(matchers: Matcher[]): React.ReactNode {
  if (matchers.length === 0) return <span className="text-slate-500">无匹配器</span>;
  const kinds = Array.from(new Set(matchers.map((m) => m.kind)));
  return kinds.map((k) => MATCHER_KIND_LABEL[k as MatcherKind]).join(' + ');
}

function cloneMatcher(m: Matcher): Matcher {
  switch (m.kind) {
    case 'process':
      return { kind: 'process', pattern: m.pattern };
    case 'domain':
      return { kind: 'domain', pattern: m.pattern };
    case 'ipset':
      return { kind: 'ipset', value: m.value };
  }
}

function matcherHasValue(m: Matcher): boolean {
  if (m.kind === 'process') return m.pattern.trim().length > 0;
  if (m.kind === 'domain') return m.pattern.trim().length > 0;
  return m.value.trim().length > 0;
}

// ── Form ───────────────────────────────────────────────────────

interface SceneFormProps {
  scene: Scene;
  saving: boolean;
  onChange: (next: Scene) => void;
  onSave: () => void;
  onCancel: () => void;
}

function SceneForm({ scene, saving, onChange, onSave, onCancel }: SceneFormProps) {
  const update = (patch: Partial<Scene>) => onChange({ ...scene, ...patch });

  const addMatcher = (kind: MatcherKind) => {
    if (kind === 'process') {
      update({ matchers: [...scene.matchers, { kind: 'process', pattern: '' }] });
    } else if (kind === 'domain') {
      update({ matchers: [...scene.matchers, { kind: 'domain', pattern: '' }] });
    } else {
      update({ matchers: [...scene.matchers, { kind: 'ipset', value: '' }] });
    }
  };

  const updateMatcher = (idx: number, value: string) => {
    const next = scene.matchers.slice();
    const m = next[idx];
    if (m.kind === 'process' || m.kind === 'domain') {
      next[idx] = { kind: m.kind, pattern: value };
    } else {
      next[idx] = { kind: 'ipset', value };
    }
    update({ matchers: next });
  };

  const removeMatcher = (idx: number) => {
    const next = scene.matchers.slice();
    next.splice(idx, 1);
    update({ matchers: next });
  };

  // Sorted kind counts for the "rendered 3 matcher kinds" gate.
  const renderedKinds = useMemo(() => {
    const set = new Set(scene.matchers.map((m) => m.kind));
    return Array.from(set).sort();
  }, [scene.matchers]);

  return (
    <section
      className="bg-slate-900/60 border border-blue-800/40 rounded-xl p-5 space-y-4"
      data-testid="scene-form"
    >
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <FormField label="场景名称" testid="scene-form-name">
          <input
            type="text"
            value={scene.name}
            onChange={(e) => update({ name: e.target.value })}
            placeholder="例如: 国内直连"
            className="w-full bg-slate-950/60 border border-slate-800 rounded-md px-3 py-1.5 text-sm text-slate-100 focus:outline-none focus:border-blue-500/60"
            data-testid="scene-form-name-input"
          />
        </FormField>

        <FormField label="匹配时覆盖为" testid="scene-form-mode">
          <select
            value={scene.mode}
            onChange={(e) => update({ mode: e.target.value as ModeOverride })}
            className="w-full bg-slate-950/60 border border-slate-800 rounded-md px-3 py-1.5 text-sm text-slate-100 focus:outline-none focus:border-blue-500/60"
            data-testid="scene-form-mode-select"
          >
            {(['off', 'system_proxy', 'tun', 'direct'] as ModeOverride[]).map((m) => (
              <option key={m} value={m}>
                {MODE_OVERRIDE_LABEL[m]}
              </option>
            ))}
          </select>
        </FormField>
      </div>

      <div>
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs font-medium text-slate-400">匹配器(任一命中即触发)</span>
          <div className="flex items-center gap-1">
            <AddMatcherButton
              icon={AppWindow}
              kind="process"
              label="进程"
              onAdd={addMatcher}
              testid="scene-form-add-process"
            />
            <AddMatcherButton
              icon={Globe}
              kind="domain"
              label="域名"
              onAdd={addMatcher}
              testid="scene-form-add-domain"
            />
            <AddMatcherButton
              icon={Network}
              kind="ipset"
              label="IP 集"
              onAdd={addMatcher}
              testid="scene-form-add-ipset"
            />
          </div>
        </div>
        <div className="space-y-2" data-testid="scene-form-matchers">
          {scene.matchers.length === 0 ? (
            <p className="text-xs text-slate-500 py-2">点击上方按钮添加匹配器。</p>
          ) : (
            scene.matchers.map((m, idx) => (
              <MatcherRow
                key={idx}
                matcher={m}
                onChange={(v) => updateMatcher(idx, v)}
                onRemove={() => removeMatcher(idx)}
              />
            ))
          )}
        </div>
        <p
          className="text-[10px] text-slate-500 mt-2"
          data-testid="scene-form-kinds-summary"
        >
          已使用匹配器种类:{' '}
          {renderedKinds.length === 0
            ? '(无)'
            : renderedKinds.map((k) => MATCHER_KIND_LABEL[k as MatcherKind]).join(' + ')}
        </p>
      </div>

      <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-800/60">
        <button
          type="button"
          onClick={onCancel}
          disabled={saving}
          data-testid="scene-form-cancel"
          className="px-3 py-1.5 text-sm text-slate-300 hover:text-slate-100 rounded-md transition-colors disabled:opacity-50"
        >
          取消
        </button>
        <button
          type="button"
          onClick={onSave}
          disabled={saving || scene.name.trim() === ''}
          data-testid="scene-form-save"
          className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-md text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500/50 disabled:opacity-50"
        >
          {saving ? <Loader2 size={13} className="animate-spin" /> : <Check size={13} />}
          保存
        </button>
      </div>
    </section>
  );
}

interface FormFieldProps {
  label: string;
  testid: string;
  children: React.ReactNode;
}

function FormField({ label, testid, children }: FormFieldProps) {
  return (
    <div data-testid={testid}>
      <label className="block text-xs font-medium text-slate-400 mb-1">{label}</label>
      {children}
    </div>
  );
}

interface AddMatcherButtonProps {
  icon: typeof Plus;
  kind: MatcherKind;
  label: string;
  onAdd: (kind: MatcherKind) => void;
  testid: string;
}

function AddMatcherButton({ icon: Icon, kind, label, onAdd, testid }: AddMatcherButtonProps) {
  return (
    <button
      type="button"
      onClick={() => onAdd(kind)}
      data-testid={testid}
      data-matcher-kind={kind}
      className="flex items-center gap-1 px-2 py-1 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded text-[11px] transition-colors"
    >
      <Icon size={11} />
      {label}
    </button>
  );
}

interface MatcherRowProps {
  matcher: Matcher;
  onChange: (value: string) => void;
  onRemove: () => void;
}

function MatcherRow({ matcher, onChange, onRemove }: MatcherRowProps) {
  const value = matcher.kind === 'ipset' ? matcher.value : matcher.pattern;
  const placeholder =
    matcher.kind === 'process'
      ? 'chrome.exe 或 * 通配'
      : matcher.kind === 'domain'
        ? 'example.com (子域自动匹配)'
        : '10.0.0.0/24 或单 IP';
  return (
    <div className="flex items-center gap-2" data-testid="scene-form-matcher" data-kind={matcher.kind}>
      <span
        className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium min-w-[60px] justify-center ${
          matcher.kind === 'process'
            ? 'bg-amber-500/15 text-amber-300'
            : matcher.kind === 'domain'
              ? 'bg-emerald-500/15 text-emerald-300'
              : 'bg-violet-500/15 text-violet-300'
        }`}
      >
        {MATCHER_KIND_LABEL[matcher.kind]}
      </span>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="flex-1 bg-slate-950/60 border border-slate-800 rounded-md px-2 py-1 text-xs text-slate-100 focus:outline-none focus:border-blue-500/60 font-mono"
        data-testid="scene-form-matcher-input"
      />
      <button
        type="button"
        onClick={onRemove}
        data-testid="scene-form-matcher-remove"
        className="p-1 text-slate-500 hover:text-red-400 rounded transition-colors"
        title="移除"
      >
        <Trash2 size={12} />
      </button>
    </div>
  );
}

interface ProbeFieldProps {
  label: string;
  value: string;
  onChange: (v: string) => void;
  testid: string;
}

function ProbeField({ label, value, onChange, testid }: ProbeFieldProps) {
  return (
    <div data-testid={testid}>
      <label className="block text-xs font-medium text-slate-400 mb-1">{label}</label>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full bg-slate-950/60 border border-slate-800 rounded-md px-2 py-1 text-xs text-slate-100 focus:outline-none focus:border-blue-500/60 font-mono"
      />
    </div>
  );
}
