// NodeQRSheet — show every node in a profile as a scannable QR code.
//
// The sheet lives inside a `NodeEditor` modal (or any caller that hands
// it the list of proxies) and turns each proxy into a `ss://…`,
// `vmess://…`, `vless://…`, `trojan://…`, `hysteria2://…`, or
// `tuic://…` share URI via the Rust `serialize_proxies_to_uris` command
// (or — when the Rust side falls back — by iterating
// `listProfileProxies` and calling `serialize_proxy_to_uri` per entry).
//
// UX:
//   * QR grid — one canvas per node. Empty list shows a friendly hint.
//   * Copy All — all URIs, one per line, to the clipboard.
//   * Save All as PNGs — triggers a separate `<a download>` per node.
//     We chose sequential downloads (rather than JSZip) to keep the
//     dependency surface small; modern browsers queue them fine.
//   * Errors during serialization are surfaced inline rather than
//     throwing — a partial render with an error banner is more useful
//     than a blank sheet.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { X, Copy, Download, AlertCircle, RefreshCw } from 'lucide-react';
import QRCode from 'qrcode';
import * as tauri from '../../services/tauri';
import type { ClashProxy } from '../../services/tauri';
import { useToastStore } from '../../stores/toast';

interface NodeQRSheetProps {
  profileId: string;
  profileName: string;
  /** Proxies the parent has already fetched. When provided, the sheet
   *  skips its own `listProfileProxies` call. */
  proxies?: ClashProxy[];
  onClose: () => void;
}

interface SerializedEntry {
  name: string;
  uri: string;
}

const QR_SIZE = 168;

export function NodeQRSheet({ profileId, profileName, proxies, onClose }: NodeQRSheetProps) {
  const [entries, setEntries] = useState<SerializedEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAndSerialize = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // 1) Resolve the proxy list. We accept it from props (so the
      //    NodeEditor can hand us its already-loaded list and skip an
      //    extra IPC round-trip) or pull it ourselves.
      const list = proxies ?? (await tauri.listProfileProxies(profileId));

      if (list.length === 0) {
        setEntries([]);
        return;
      }

      // 2) Turn each proxy into a share URI. The Rust side's
      //    `serialize_proxies_to_uris` is currently a stub that requires
      //    AppState wiring, so we go through the per-proxy command.
      const out: SerializedEntry[] = [];
      for (const p of list) {
        try {
          const uri = await tauri.serializeProxyToUri(p);
          out.push({ name: p.name || '(unnamed)', uri });
        } catch (e) {
          // Surface the bad node inline rather than failing the whole
          // sheet — the user can still export the rest.
          out.push({
            name: p.name || '(unnamed)',
            uri: '',
          });
          // Stash a synthetic error so the banner lists which nodes failed.
          setError((prev) =>
            prev
              ? `${prev}\n${p.name || '(unnamed)'}: ${String(e)}`
              : `Failed to serialize ${p.name || '(unnamed)'}: ${String(e)}`,
          );
        }
      }
      setEntries(out);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [profileId, proxies]);

  useEffect(() => {
    void fetchAndSerialize();
  }, [fetchAndSerialize]);

  const validEntries = useMemo(() => entries.filter((e) => e.uri !== ''), [entries]);
  const empty = !loading && entries.length === 0;

  return (
    <div
      className="fixed inset-0 bg-black/70 flex items-center justify-center z-[60] backdrop-blur-sm"
      data-testid="node-qr-sheet"
    >
      <div className="bg-slate-900 border border-slate-800 rounded-xl w-full max-w-4xl shadow-2xl max-h-[90vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-3 border-b border-slate-800">
          <div className="min-w-0">
            <h3 className="text-base font-semibold text-slate-100 truncate">
              分享节点 · {profileName}
            </h3>
            <p className="text-[11px] text-slate-500 mt-0.5">
              {validEntries.length} / {entries.length} 个节点可分享
            </p>
          </div>
          <div className="flex items-center gap-1">
            <button
              onClick={() => void fetchAndSerialize()}
              className="text-slate-400 hover:text-slate-200 transition-colors p-1"
              title="重新生成"
            >
              <RefreshCw size={14} />
            </button>
            <button
              onClick={onClose}
              className="text-slate-500 hover:text-slate-200 transition-colors p-1"
              title="关闭"
            >
              <X size={16} />
            </button>
          </div>
        </div>

        {error && (
          <div
            className="mx-5 mt-3 px-3 py-2 text-xs text-red-300 bg-red-950/40 border border-red-900/60 rounded whitespace-pre-line"
            data-testid="node-qr-sheet-error"
          >
            {error}
          </div>
        )}

        <div className="flex-1 overflow-y-auto p-5">
          {loading ? (
            <p className="text-xs text-slate-500">生成二维码中…</p>
          ) : empty ? (
            <p
              className="text-xs text-slate-500"
              data-testid="node-qr-sheet-empty"
            >
              No nodes to share
            </p>
          ) : (
            <div
              className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3"
              data-testid="node-qr-grid"
            >
              {entries.map((e) => (
                <NodeQRCard key={e.name} entry={e} />
              ))}
            </div>
          )}
        </div>

        <div className="flex items-center justify-end gap-2 px-5 py-3 border-t border-slate-800">
          <CopyAllButton entries={validEntries} disabled={validEntries.length === 0} />
          <SaveAllButton entries={validEntries} disabled={validEntries.length === 0} />
        </div>
      </div>
    </div>
  );
}

function NodeQRCard({ entry }: { entry: SerializedEntry }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    if (!canvasRef.current) return;
    if (!entry.uri) return;
    QRCode.toCanvas(canvasRef.current, entry.uri, {
      width: QR_SIZE,
      margin: 1,
      errorCorrectionLevel: 'M',
      color: {
        dark: '#e2e8f0',
        light: '#0f172a',
      },
    }).catch(() => {
      // We don't surface canvas errors here — the parent error banner
      // already covers URI serialization issues. A blank canvas is
      // enough of a signal.
    });
  }, [entry.uri]);

  return (
    <div
      className="flex flex-col items-center gap-2 bg-slate-950/40 border border-slate-800 rounded-lg p-3"
      data-testid="node-qr-card"
      data-node-name={entry.name}
    >
      <div className="bg-slate-900 rounded p-2">
        {entry.uri ? (
          <canvas
            ref={canvasRef}
            width={QR_SIZE}
            height={QR_SIZE}
            data-testid="node-qr-canvas"
          />
        ) : (
          <div
            className="flex items-center justify-center text-[10px] text-red-400"
            style={{ width: QR_SIZE, height: QR_SIZE }}
            data-testid="node-qr-card-error"
          >
            <AlertCircle size={16} className="mr-1" />
            生成失败
          </div>
        )}
      </div>
      <p
        className="text-[11px] text-slate-200 font-medium truncate w-full text-center"
        title={entry.name}
      >
        {entry.name}
      </p>
      <p
        className="text-[10px] text-slate-500 font-mono truncate w-full text-center"
        title={entry.uri}
      >
        {entry.uri ? entry.uri.split('://')[0] + '://…' : '—'}
      </p>
    </div>
  );
}

function CopyAllButton({
  entries,
  disabled,
}: {
  entries: SerializedEntry[];
  disabled: boolean;
}) {
  const addToast = useToastStore((s) => s.addToast);
  const handleClick = async () => {
    if (entries.length === 0) return;
    const text = entries.map((e) => e.uri).join('\n');
    try {
      await navigator.clipboard.writeText(text);
      addToast(`已复制 ${entries.length} 个 URI 到剪贴板`, 'success');
    } catch (e) {
      addToast(`复制失败：${String(e)}`, 'error');
    }
  };
  return (
    <button
      onClick={() => void handleClick()}
      disabled={disabled}
      data-testid="node-qr-copy-all"
      className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-slate-200 hover:text-white bg-slate-800 hover:bg-slate-700 rounded-lg font-medium disabled:opacity-50 disabled:cursor-not-allowed"
    >
      <Copy size={13} />
      Copy All URIs
    </button>
  );
}

function SaveAllButton({
  entries,
  disabled,
}: {
  entries: SerializedEntry[];
  disabled: boolean;
}) {
  const addToast = useToastStore((s) => s.addToast);
  const handleClick = async () => {
    if (entries.length === 0) return;
    try {
      for (const e of entries) {
        // Render to a one-off data URL so we can hand it to a
        // standalone `<a download>` element. The grid's canvas is
        // sized for the in-sheet display; for downloads we generate
        // a 512-px PNG for legibility when scanned.
        const dataUrl = await QRCode.toDataURL(e.uri, {
          width: 512,
          margin: 2,
          errorCorrectionLevel: 'M',
        });
        const a = document.createElement('a');
        a.href = dataUrl;
        a.download = `${sanitizeFilename(e.name)}.png`;
        document.body.appendChild(a);
        a.click();
        a.remove();
      }
      addToast(`已下载 ${entries.length} 个 PNG`, 'success');
    } catch (e) {
      addToast(`下载失败：${String(e)}`, 'error');
    }
  };
  return (
    <button
      onClick={() => void handleClick()}
      disabled={disabled}
      data-testid="node-qr-save-all"
      className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-white bg-blue-600 hover:bg-blue-500 rounded-lg font-medium disabled:opacity-50 disabled:cursor-not-allowed"
    >
      <Download size={13} />
      Save All as PNGs
    </button>
  );
}

function sanitizeFilename(name: string): string {
  return name.replace(/[\\/:*?"<>|]/g, '_').slice(0, 80) || 'node';
}
