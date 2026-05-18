import { useEffect, useMemo, useState } from 'react';
import { X, Plus, Trash2, Edit3, Save, ArrowLeft } from 'lucide-react';
import * as tauri from '../../services/tauri';
import type { ClashProxy } from '../../services/tauri';

const PROTOCOL_OPTIONS: { value: string; label: string }[] = [
  { value: 'ss', label: 'Shadowsocks' },
  { value: 'vmess', label: 'VMess' },
  { value: 'vless', label: 'VLESS' },
  { value: 'trojan', label: 'Trojan' },
  { value: 'hysteria2', label: 'Hysteria2' },
  { value: 'tuic', label: 'TUIC' },
  { value: 'anytls', label: 'AnyTLS' },
  { value: 'snell', label: 'Snell' },
  { value: 'socks5', label: 'SOCKS5' },
  { value: 'http', label: 'HTTP' },
];

const FINGERPRINT_OPTIONS = ['', 'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', 'random'];
const SS_CIPHERS = [
  'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm',
  '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305',
  'chacha20-ietf-poly1305', 'xchacha20-ietf-poly1305',
  'rc4-md5',
];

function emptyProxy(type = 'ss'): ClashProxy {
  return { name: '', type, server: '', port: 443, udp: true };
}

interface Props {
  profileId: string;
  profileName: string;
  onClose: () => void;
}

export function NodeEditor({ profileId, profileName, onClose }: Props) {
  const [proxies, setProxies] = useState<ClashProxy[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Editor state. `editing` is the *original* name when editing an existing
  // proxy (so rename works); null when adding new; undefined when on list view.
  const [editing, setEditing] = useState<string | null | undefined>(undefined);
  const [draft, setDraft] = useState<ClashProxy>(emptyProxy());
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    void reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profileId]);

  async function reload() {
    setLoading(true);
    setError(null);
    try {
      const list = await tauri.listProfileProxies(profileId);
      setProxies(list);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }

  function startAdd() {
    setDraft(emptyProxy());
    setEditing(null);
  }
  function startEdit(p: ClashProxy) {
    setDraft({ ...p });
    setEditing(p.name);
  }
  function cancelEdit() {
    setEditing(undefined);
  }

  async function handleSave() {
    if (!draft.name.trim()) {
      setError('节点名称不能为空');
      return;
    }
    if (!draft.type) {
      setError('协议类型不能为空');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const cleaned = pruneProxy(draft);
      if (editing === null) {
        await tauri.addProfileProxy(profileId, cleaned);
      } else if (editing) {
        await tauri.updateProfileProxy(profileId, editing, cleaned);
      }
      setEditing(undefined);
      await reload();
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(name: string) {
    if (!confirm(`确认删除节点 "${name}"？`)) return;
    try {
      await tauri.deleteProfileProxy(profileId, name);
      await reload();
    } catch (e) {
      setError(String(e));
    }
  }

  const onListView = editing === undefined;

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 backdrop-blur-sm">
      <div className="bg-slate-900 border border-slate-800 rounded-xl w-full max-w-3xl shadow-2xl max-h-[88vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-3 border-b border-slate-800">
          <div className="flex items-center gap-2 min-w-0">
            {!onListView && (
              <button
                onClick={cancelEdit}
                className="text-slate-400 hover:text-slate-200 transition-colors p-1"
                title="返回列表"
              >
                <ArrowLeft size={16} />
              </button>
            )}
            <h3 className="text-base font-semibold text-slate-100 truncate">
              节点编辑器 · {profileName}
            </h3>
          </div>
          <button
            onClick={onClose}
            className="text-slate-500 hover:text-slate-200 transition-colors p-1"
            title="关闭"
          >
            <X size={16} />
          </button>
        </div>

        {error && (
          <div className="mx-5 mt-3 px-3 py-2 text-xs text-red-300 bg-red-950/40 border border-red-900/60 rounded">
            {error}
          </div>
        )}

        <div className="flex-1 overflow-y-auto p-5">
          {onListView ? (
            <ListView
              proxies={proxies}
              loading={loading}
              onAdd={startAdd}
              onEdit={startEdit}
              onDelete={handleDelete}
            />
          ) : (
            <FormView draft={draft} onChange={setDraft} />
          )}
        </div>

        {!onListView && (
          <div className="flex items-center justify-end gap-2 px-5 py-3 border-t border-slate-800">
            <button
              onClick={cancelEdit}
              className="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors rounded"
            >
              取消
            </button>
            <button
              onClick={handleSave}
              disabled={saving}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium disabled:opacity-50"
            >
              <Save size={13} />
              {saving ? '保存中…' : editing === null ? '添加' : '保存'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function ListView({
  proxies,
  loading,
  onAdd,
  onEdit,
  onDelete,
}: {
  proxies: ClashProxy[];
  loading: boolean;
  onAdd: () => void;
  onEdit: (p: ClashProxy) => void;
  onDelete: (name: string) => void;
}) {
  return (
    <>
      <div className="flex items-center justify-between mb-3">
        <p className="text-xs text-slate-500">{proxies.length} 个节点</p>
        <button
          onClick={onAdd}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-medium"
        >
          <Plus size={13} />
          新建节点
        </button>
      </div>

      {loading ? (
        <p className="text-xs text-slate-500">加载中…</p>
      ) : proxies.length === 0 ? (
        <p className="text-xs text-slate-500">此配置暂无节点，点击右上角“新建节点”添加。</p>
      ) : (
        <div className="space-y-1.5">
          {proxies.map((p) => (
            <div
              key={p.name}
              className="flex items-center justify-between gap-3 bg-slate-950/40 border border-slate-800 rounded-lg px-3 py-2 hover:border-slate-700 transition-colors"
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 text-sm text-slate-100 truncate">
                  <span className="font-medium">{p.name}</span>
                  <span className="text-[10px] px-1.5 py-0.5 bg-slate-800 text-slate-400 rounded uppercase">
                    {p.type || '?'}
                  </span>
                </div>
                <p className="text-[11px] text-slate-500 truncate font-mono">
                  {p.server ?? '-'}:{p.port ?? '-'}
                </p>
              </div>
              <div className="flex items-center gap-1">
                <button
                  onClick={() => onEdit(p)}
                  className="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded transition-colors"
                  title="编辑"
                >
                  <Edit3 size={13} />
                </button>
                <button
                  onClick={() => onDelete(p.name)}
                  className="p-1.5 text-slate-400 hover:text-red-400 hover:bg-slate-800 rounded transition-colors"
                  title="删除"
                >
                  <Trash2 size={13} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}

function FormView({
  draft,
  onChange,
}: {
  draft: ClashProxy;
  onChange: (next: ClashProxy) => void;
}) {
  const set = useMemo(
    () =>
      <K extends keyof ClashProxy>(key: K) =>
      (value: ClashProxy[K]) =>
        onChange({ ...draft, [key]: value }),
    [draft, onChange],
  );

  return (
    <div className="space-y-4">
      <Section title="通用">
        <Row>
          <Field label="名称" required>
            <input
              value={draft.name}
              onChange={(e) => set('name')(e.target.value)}
              className={inputCls}
              placeholder="My Node"
            />
          </Field>
          <Field label="协议" required>
            <select
              value={draft.type ?? 'ss'}
              onChange={(e) => onChange({ ...draft, type: e.target.value })}
              className={inputCls}
            >
              {PROTOCOL_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </Field>
        </Row>
        <Row>
          <Field label="服务器">
            <input
              value={draft.server ?? ''}
              onChange={(e) => set('server')(e.target.value)}
              className={inputCls}
              placeholder="example.com"
            />
          </Field>
          <Field label="端口">
            <input
              type="number"
              value={draft.port ?? ''}
              onChange={(e) =>
                set('port')(e.target.value === '' ? undefined : Number(e.target.value))
              }
              className={inputCls}
              placeholder="443"
            />
          </Field>
          <Field label="UDP">
            <select
              value={String(draft.udp ?? true)}
              onChange={(e) => set('udp')(e.target.value === 'true')}
              className={inputCls}
            >
              <option value="true">启用</option>
              <option value="false">禁用</option>
            </select>
          </Field>
        </Row>
      </Section>

      {draft.type === 'ss' && <ShadowsocksFields draft={draft} set={set} onChange={onChange} />}
      {draft.type === 'vmess' && <VmessFields draft={draft} set={set} onChange={onChange} />}
      {draft.type === 'vless' && <VlessFields draft={draft} set={set} onChange={onChange} />}
      {draft.type === 'trojan' && <TrojanFields draft={draft} set={set} />}
      {draft.type === 'hysteria2' && <Hysteria2Fields draft={draft} set={set} />}
      {draft.type === 'tuic' && <TuicFields draft={draft} set={set} />}
      {draft.type === 'anytls' && <AnyTlsFields draft={draft} set={set} />}
      {(draft.type === 'socks5' || draft.type === 'http') && (
        <HttpSocksFields draft={draft} set={set} />
      )}
      {draft.type === 'snell' && <SnellFields draft={draft} set={set} />}
    </div>
  );
}

// ============ Per-protocol field groups ============

type SetterFn = <K extends keyof ClashProxy>(key: K) => (value: ClashProxy[K]) => void;

function ShadowsocksFields({
  draft,
  set,
  onChange,
}: {
  draft: ClashProxy;
  set: SetterFn;
  onChange: (next: ClashProxy) => void;
}) {
  const plugin = draft.plugin ?? '';
  const pluginOpts = (draft['plugin-opts'] ?? {}) as Record<string, unknown>;
  const setPluginOpt = (key: string, value: unknown) => {
    const next = { ...pluginOpts };
    if (value === undefined || value === '' || value === null) {
      delete next[key];
    } else {
      next[key] = value;
    }
    onChange({
      ...draft,
      'plugin-opts': Object.keys(next).length ? next : undefined,
    });
  };
  return (
    <>
      <Section title="Shadowsocks">
        <Row>
          <Field label="加密方式">
            <select
              value={draft.cipher ?? 'aes-256-gcm'}
              onChange={(e) => set('cipher')(e.target.value)}
              className={inputCls}
            >
              {SS_CIPHERS.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
          <Field label="密码">
            <input
              type="password"
              value={draft.password ?? ''}
              onChange={(e) => set('password')(e.target.value)}
              className={inputCls}
            />
          </Field>
        </Row>
      </Section>

      <Section title="插件">
        <Row>
          <Field label="Plugin">
            <select
              value={plugin}
              onChange={(e) => {
                const v = e.target.value;
                if (v) {
                  onChange({ ...draft, plugin: v });
                } else {
                  // Clearing plugin also clears its options.
                  const next = { ...draft };
                  delete next.plugin;
                  delete next['plugin-opts'];
                  onChange(next);
                }
              }}
              className={inputCls}
            >
              <option value="">（无）</option>
              <option value="obfs">simple-obfs</option>
              <option value="v2ray-plugin">v2ray-plugin</option>
              <option value="shadow-tls">shadow-tls</option>
              <option value="restls">restls</option>
            </select>
          </Field>
        </Row>
        {plugin === 'shadow-tls' && (
          <Row>
            <Field label="ShadowTLS host">
              <input
                value={(pluginOpts.host as string | undefined) ?? ''}
                onChange={(e) => setPluginOpt('host', e.target.value)}
                className={inputCls}
                placeholder="cloud.tencent.com"
              />
            </Field>
            <Field label="ShadowTLS 密码">
              <input
                type="password"
                value={(pluginOpts.password as string | undefined) ?? ''}
                onChange={(e) => setPluginOpt('password', e.target.value)}
                className={inputCls}
              />
            </Field>
            <Field label="协议版本">
              <select
                value={String((pluginOpts.version as number | undefined) ?? 3)}
                onChange={(e) => setPluginOpt('version', Number(e.target.value))}
                className={inputCls}
              >
                <option value="1">1</option>
                <option value="2">2</option>
                <option value="3">3</option>
              </select>
            </Field>
          </Row>
        )}
        {plugin === 'obfs' && (
          <Row>
            <Field label="混淆模式">
              <select
                value={(pluginOpts.mode as string | undefined) ?? 'http'}
                onChange={(e) => setPluginOpt('mode', e.target.value)}
                className={inputCls}
              >
                <option value="http">http</option>
                <option value="tls">tls</option>
              </select>
            </Field>
            <Field label="混淆 host">
              <input
                value={(pluginOpts.host as string | undefined) ?? ''}
                onChange={(e) => setPluginOpt('host', e.target.value)}
                className={inputCls}
              />
            </Field>
          </Row>
        )}
        {plugin === 'v2ray-plugin' && (
          <Row>
            <Field label="传输模式">
              <select
                value={(pluginOpts.mode as string | undefined) ?? 'websocket'}
                onChange={(e) => setPluginOpt('mode', e.target.value)}
                className={inputCls}
              >
                <option value="websocket">websocket</option>
              </select>
            </Field>
            <Field label="Host">
              <input
                value={(pluginOpts.host as string | undefined) ?? ''}
                onChange={(e) => setPluginOpt('host', e.target.value)}
                className={inputCls}
              />
            </Field>
            <Field label="Path">
              <input
                value={(pluginOpts.path as string | undefined) ?? ''}
                onChange={(e) => setPluginOpt('path', e.target.value)}
                className={inputCls}
                placeholder="/"
              />
            </Field>
          </Row>
        )}
      </Section>
    </>
  );
}

function VmessFields({
  draft,
  set,
  onChange,
}: {
  draft: ClashProxy;
  set: SetterFn;
  onChange: (next: ClashProxy) => void;
}) {
  return (
    <>
      <Section title="VMess">
        <Row>
          <Field label="UUID">
            <input
              value={draft.uuid ?? ''}
              onChange={(e) => set('uuid')(e.target.value)}
              className={inputCls}
              placeholder="00000000-0000-0000-0000-000000000000"
            />
          </Field>
          <Field label="AlterID">
            <input
              type="number"
              value={draft.alterId ?? 0}
              onChange={(e) => set('alterId')(Number(e.target.value))}
              className={inputCls}
            />
          </Field>
          <Field label="加密">
            <select
              value={draft.cipher ?? 'auto'}
              onChange={(e) => set('cipher')(e.target.value)}
              className={inputCls}
            >
              {['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none'].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </Field>
        </Row>
        <Row>
          <Field label="TLS">
            <select
              value={String(draft.tls ?? false)}
              onChange={(e) => set('tls')(e.target.value === 'true')}
              className={inputCls}
            >
              <option value="false">禁用</option>
              <option value="true">启用</option>
            </select>
          </Field>
          <Field label="SNI">
            <input
              value={draft.sni ?? ''}
              onChange={(e) => set('sni')(e.target.value)}
              className={inputCls}
            />
          </Field>
          <Field label="跳过证书验证">
            <select
              value={String(draft['skip-cert-verify'] ?? false)}
              onChange={(e) =>
                onChange({ ...draft, 'skip-cert-verify': e.target.value === 'true' })
              }
              className={inputCls}
            >
              <option value="false">否</option>
              <option value="true">是</option>
            </select>
          </Field>
        </Row>
      </Section>
      <TransportFields draft={draft} set={set} onChange={onChange} />
    </>
  );
}

function VlessFields({
  draft,
  set,
  onChange,
}: {
  draft: ClashProxy;
  set: SetterFn;
  onChange: (next: ClashProxy) => void;
}) {
  const isReality = draft.security === 'reality';
  return (
    <>
      <Section title="VLESS">
        <Row>
          <Field label="UUID">
            <input
              value={draft.uuid ?? ''}
              onChange={(e) => set('uuid')(e.target.value)}
              className={inputCls}
            />
          </Field>
          <Field label="Flow">
            <select
              value={draft.flow ?? ''}
              onChange={(e) => set('flow')(e.target.value || undefined)}
              className={inputCls}
            >
              <option value="">（无）</option>
              <option value="xtls-rprx-vision">xtls-rprx-vision</option>
              <option value="xtls-rprx-direct">xtls-rprx-direct</option>
            </select>
          </Field>
          <Field label="安全">
            <select
              value={draft.security ?? 'tls'}
              onChange={(e) => set('security')(e.target.value || undefined)}
              className={inputCls}
            >
              <option value="">none</option>
              <option value="tls">tls</option>
              <option value="reality">reality</option>
            </select>
          </Field>
        </Row>
        <Row>
          <Field label="SNI">
            <input
              value={draft.sni ?? ''}
              onChange={(e) => set('sni')(e.target.value)}
              className={inputCls}
            />
          </Field>
          <Field label="Fingerprint">
            <select
              value={draft.fingerprint ?? ''}
              onChange={(e) => set('fingerprint')(e.target.value || undefined)}
              className={inputCls}
            >
              {FINGERPRINT_OPTIONS.map((f) => (
                <option key={f} value={f}>
                  {f === '' ? '（默认）' : f}
                </option>
              ))}
            </select>
          </Field>
          <Field label="跳过证书验证">
            <select
              value={String(draft['skip-cert-verify'] ?? false)}
              onChange={(e) =>
                onChange({ ...draft, 'skip-cert-verify': e.target.value === 'true' })
              }
              className={inputCls}
            >
              <option value="false">否</option>
              <option value="true">是</option>
            </select>
          </Field>
        </Row>
      </Section>

      {isReality && (
        <Section title="Reality">
          <Row>
            <Field label="Public Key (pbk)">
              <input
                value={draft.pbk ?? ''}
                onChange={(e) => set('pbk')(e.target.value)}
                className={inputCls}
              />
            </Field>
            <Field label="Short ID (sid)">
              <input
                value={draft.sid ?? ''}
                onChange={(e) => set('sid')(e.target.value)}
                className={inputCls}
              />
            </Field>
            <Field label="SpiderX (spx)">
              <input
                value={draft.spx ?? ''}
                onChange={(e) => set('spx')(e.target.value)}
                className={inputCls}
              />
            </Field>
          </Row>
        </Section>
      )}

      <TransportFields draft={draft} set={set} onChange={onChange} />
    </>
  );
}

function TrojanFields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title="Trojan">
      <Row>
        <Field label="密码">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="SNI">
          <input
            value={draft.sni ?? ''}
            onChange={(e) => set('sni')(e.target.value)}
            className={inputCls}
          />
        </Field>
      </Row>
      <Row>
        <Field label="Fingerprint">
          <select
            value={draft.fingerprint ?? ''}
            onChange={(e) => set('fingerprint')(e.target.value || undefined)}
            className={inputCls}
          >
            {FINGERPRINT_OPTIONS.map((f) => (
              <option key={f} value={f}>
                {f === '' ? '（默认）' : f}
              </option>
            ))}
          </select>
        </Field>
        <Field label="跳过证书验证">
          <select
            value={String(draft['skip-cert-verify'] ?? false)}
            onChange={(e) => set('skip-cert-verify')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
        <Field label="ALPN (逗号分隔)">
          <input
            value={(draft.alpn ?? []).join(',')}
            onChange={(e) =>
              set('alpn')(
                e.target.value
                  .split(',')
                  .map((s) => s.trim())
                  .filter(Boolean),
              )
            }
            className={inputCls}
            placeholder="h2,http/1.1"
          />
        </Field>
      </Row>
    </Section>
  );
}

function Hysteria2Fields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title="Hysteria2">
      <Row>
        <Field label="密码">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="SNI">
          <input
            value={draft.sni ?? ''}
            onChange={(e) => set('sni')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="跳过证书验证">
          <select
            value={String(draft['skip-cert-verify'] ?? false)}
            onChange={(e) => set('skip-cert-verify')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
      </Row>
      <Row>
        <Field label="端口跳跃范围">
          <input
            value={draft.ports ?? ''}
            onChange={(e) => set('ports')(e.target.value || undefined)}
            className={inputCls}
            placeholder="20000-50000"
          />
        </Field>
        <Field label="跳跃间隔(秒)">
          <input
            type="number"
            value={draft['hop-interval'] ?? ''}
            onChange={(e) =>
              set('hop-interval')(e.target.value === '' ? undefined : Number(e.target.value))
            }
            className={inputCls}
            placeholder="30"
          />
        </Field>
        <Field label="混淆">
          <select
            value={draft.obfs ?? ''}
            onChange={(e) => set('obfs')(e.target.value || undefined)}
            className={inputCls}
          >
            <option value="">（无）</option>
            <option value="salamander">salamander</option>
          </select>
        </Field>
      </Row>
      {draft.obfs && (
        <Row>
          <Field label="混淆密码">
            <input
              type="password"
              value={draft['obfs-password'] ?? ''}
              onChange={(e) => set('obfs-password')(e.target.value)}
              className={inputCls}
            />
          </Field>
        </Row>
      )}
    </Section>
  );
}

function TuicFields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title="TUIC">
      <Row>
        <Field label="UUID">
          <input
            value={draft.uuid ?? ''}
            onChange={(e) => set('uuid')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="密码">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="请求版本">
          <select
            value={String(draft['request-version'] ?? 5)}
            onChange={(e) => set('request-version')(Number(e.target.value))}
            className={inputCls}
          >
            <option value="5">5</option>
            <option value="4">4</option>
          </select>
        </Field>
      </Row>
      <Row>
        <Field label="SNI">
          <input
            value={draft.sni ?? ''}
            onChange={(e) => set('sni')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="拥塞控制">
          <select
            value={draft['congestion-controller'] ?? 'bbr'}
            onChange={(e) => set('congestion-controller')(e.target.value)}
            className={inputCls}
          >
            <option value="bbr">bbr</option>
            <option value="cubic">cubic</option>
            <option value="new_reno">new_reno</option>
          </select>
        </Field>
        <Field label="UDP 中继">
          <select
            value={draft['udp-relay-mode'] ?? 'native'}
            onChange={(e) => set('udp-relay-mode')(e.target.value)}
            className={inputCls}
          >
            <option value="native">native</option>
            <option value="quic">quic</option>
          </select>
        </Field>
      </Row>
      <Row>
        <Field label="跳过证书验证">
          <select
            value={String(draft['skip-cert-verify'] ?? false)}
            onChange={(e) => set('skip-cert-verify')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
        <Field label="禁用 SNI">
          <select
            value={String(draft['disable-sni'] ?? false)}
            onChange={(e) => set('disable-sni')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
        <Field label="reduce-rtt">
          <select
            value={String(draft['reduce-rtt'] ?? false)}
            onChange={(e) => set('reduce-rtt')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
      </Row>
    </Section>
  );
}

function HttpSocksFields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title={draft.type === 'http' ? 'HTTP' : 'SOCKS5'}>
      <Row>
        <Field label="用户名">
          <input
            value={draft.username ?? ''}
            onChange={(e) => set('username')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="密码">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="TLS">
          <select
            value={String(draft.tls ?? false)}
            onChange={(e) => set('tls')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
      </Row>
    </Section>
  );
}

function SnellFields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title="Snell">
      <Row>
        <Field label="PSK">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="协议版本">
          <select
            value={String(draft.version ?? 3)}
            onChange={(e) => set('version')(Number(e.target.value))}
            className={inputCls}
          >
            <option value="1">1</option>
            <option value="2">2</option>
            <option value="3">3</option>
            <option value="4">4</option>
          </select>
        </Field>
        <Field label="混淆">
          <select
            value={draft.obfs ?? ''}
            onChange={(e) => set('obfs')(e.target.value || undefined)}
            className={inputCls}
          >
            <option value="">（无）</option>
            <option value="http">http</option>
            <option value="tls">tls</option>
          </select>
        </Field>
      </Row>
    </Section>
  );
}

function AnyTlsFields({ draft, set }: { draft: ClashProxy; set: SetterFn }) {
  return (
    <Section title="AnyTLS">
      <Row>
        <Field label="密码">
          <input
            type="password"
            value={draft.password ?? ''}
            onChange={(e) => set('password')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="SNI">
          <input
            value={draft.sni ?? ''}
            onChange={(e) => set('sni')(e.target.value)}
            className={inputCls}
          />
        </Field>
        <Field label="Client Fingerprint">
          <select
            value={draft['client-fingerprint'] ?? ''}
            onChange={(e) => set('client-fingerprint')(e.target.value || undefined)}
            className={inputCls}
          >
            {FINGERPRINT_OPTIONS.map((f) => (
              <option key={f} value={f}>
                {f === '' ? '（默认）' : f}
              </option>
            ))}
          </select>
        </Field>
      </Row>
      <Row>
        <Field label="跳过证书验证">
          <select
            value={String(draft['skip-cert-verify'] ?? false)}
            onChange={(e) => set('skip-cert-verify')(e.target.value === 'true')}
            className={inputCls}
          >
            <option value="false">否</option>
            <option value="true">是</option>
          </select>
        </Field>
        <Field label="ALPN (逗号分隔)">
          <input
            value={(draft.alpn ?? []).join(',')}
            onChange={(e) =>
              set('alpn')(
                e.target.value
                  .split(',')
                  .map((s) => s.trim())
                  .filter(Boolean),
              )
            }
            className={inputCls}
            placeholder="h2,http/1.1"
          />
        </Field>
      </Row>
      <Row>
        <Field label="空闲会话检测(秒)">
          <input
            type="number"
            value={draft['idle-session-check-interval'] ?? ''}
            onChange={(e) =>
              set('idle-session-check-interval')(
                e.target.value === '' ? undefined : Number(e.target.value),
              )
            }
            className={inputCls}
            placeholder="30"
          />
        </Field>
        <Field label="空闲会话超时(秒)">
          <input
            type="number"
            value={draft['idle-session-timeout'] ?? ''}
            onChange={(e) =>
              set('idle-session-timeout')(
                e.target.value === '' ? undefined : Number(e.target.value),
              )
            }
            className={inputCls}
            placeholder="30"
          />
        </Field>
        <Field label="最小空闲会话数">
          <input
            type="number"
            value={draft['min-idle-session'] ?? ''}
            onChange={(e) =>
              set('min-idle-session')(
                e.target.value === '' ? undefined : Number(e.target.value),
              )
            }
            className={inputCls}
            placeholder="0"
          />
        </Field>
      </Row>
    </Section>
  );
}

// Common transport (WS / gRPC) used by VMess + VLESS.
function TransportFields({
  draft,
  set,
  onChange,
}: {
  draft: ClashProxy;
  set: SetterFn;
  onChange: (next: ClashProxy) => void;
}) {
  const network = draft.network ?? 'tcp';
  return (
    <Section title="传输">
      <Row>
        <Field label="网络">
          <select
            value={network}
            onChange={(e) => set('network')(e.target.value || undefined)}
            className={inputCls}
          >
            {['tcp', 'ws', 'grpc', 'h2', 'quic'].map((n) => (
              <option key={n} value={n}>
                {n}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Client Fingerprint">
          <select
            value={draft['client-fingerprint'] ?? ''}
            onChange={(e) =>
              onChange({
                ...draft,
                'client-fingerprint': e.target.value || undefined,
              })
            }
            className={inputCls}
          >
            {FINGERPRINT_OPTIONS.map((f) => (
              <option key={f} value={f}>
                {f === '' ? '（默认）' : f}
              </option>
            ))}
          </select>
        </Field>
      </Row>
      {network === 'ws' && (
        <Row>
          <Field label="WebSocket 路径">
            <input
              value={draft['ws-path'] ?? ''}
              onChange={(e) =>
                onChange({ ...draft, 'ws-path': e.target.value || undefined })
              }
              className={inputCls}
              placeholder="/"
            />
          </Field>
          <Field label="Host Header">
            <input
              value={draft['ws-headers']?.Host ?? ''}
              onChange={(e) => {
                const host = e.target.value;
                onChange({
                  ...draft,
                  'ws-headers': host ? { ...(draft['ws-headers'] ?? {}), Host: host } : undefined,
                });
              }}
              className={inputCls}
            />
          </Field>
        </Row>
      )}
      {network === 'grpc' && (
        <Row>
          <Field label="gRPC Service Name">
            <input
              value={draft['grpc-service-name'] ?? ''}
              onChange={(e) =>
                onChange({
                  ...draft,
                  'grpc-service-name': e.target.value || undefined,
                })
              }
              className={inputCls}
            />
          </Field>
        </Row>
      )}
    </Section>
  );
}

// ============ Layout primitives ============

const inputCls =
  'w-full px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-blue-500 focus:ring-1 focus:ring-blue-500/30';

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-slate-950/40 border border-slate-800 rounded-lg p-3">
      <h4 className="text-[11px] uppercase tracking-wide text-slate-500 font-semibold mb-2">
        {title}
      </h4>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

function Row({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">{children}</div>;
}

function Field({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[10px] text-slate-400">
        {label}
        {required && <span className="text-red-400 ml-0.5">*</span>}
      </span>
      {children}
    </label>
  );
}

// Strip empty strings / nullish so we don't write garbage keys back to YAML.
function pruneProxy(p: ClashProxy): ClashProxy {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(p)) {
    if (v === '' || v === null || v === undefined) continue;
    if (Array.isArray(v) && v.length === 0) continue;
    if (typeof v === 'object' && !Array.isArray(v) && Object.keys(v as object).length === 0) continue;
    out[k] = v;
  }
  return out as unknown as ClashProxy;
}
