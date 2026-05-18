import { useEffect, useState } from 'react';
import { Cloud, Upload, Download, CheckCircle, Loader2 } from 'lucide-react';
import * as tauri from '../../services/tauri';

/** WebDAV sync tab — credentials, backup/restore. */
export function SyncTab() {
  const [config, setConfig] = useState<tauri.WebDAVConfigDto | null>(null);
  const [password, setPassword] = useState(''); // entered fresh each session
  const [busy, setBusy] = useState<null | 'save' | 'test' | 'backup' | 'restore'>(null);
  const [msg, setMsg] = useState<string | null>(null);

  useEffect(() => {
    tauri.webdavGetConfig().then(setConfig).catch(console.error);
  }, []);

  if (!config) return <div className="text-slate-500">加载中…</div>;

  const update = <K extends keyof tauri.WebDAVConfigDto>(k: K, v: tauri.WebDAVConfigDto[K]) =>
    setConfig({ ...config, [k]: v });

  const save = async () => {
    setBusy('save');
    setMsg(null);
    try {
      const next = await tauri.webdavSetConfig(
        config.endpoint,
        config.username,
        password,
        config.remote_path,
        config.enabled,
      );
      setConfig(next);
      setPassword('');
      setMsg('已保存。');
    } catch (e) {
      setMsg(`保存失败：${e}`);
    } finally {
      setBusy(null);
    }
  };

  const test = async () => {
    setBusy('test');
    setMsg(null);
    try {
      await tauri.webdavTestConnection();
      setMsg('连接成功。');
    } catch (e) {
      setMsg(`连接失败：${e}`);
    } finally {
      setBusy(null);
    }
  };

  const backup = async () => {
    setBusy('backup');
    setMsg(null);
    try {
      await tauri.webdavBackupNow();
      setMsg('已上传备份。');
    } catch (e) {
      setMsg(`备份失败：${e}`);
    } finally {
      setBusy(null);
    }
  };

  const restore = async () => {
    if (!confirm('恢复将覆盖本地 profiles、active.json、dns_policy.json。是否继续？')) return;
    setBusy('restore');
    setMsg(null);
    try {
      await tauri.webdavRestoreNow();
      setMsg('已恢复。重新打开 Profiles 查看。');
    } catch (e) {
      setMsg(`恢复失败：${e}`);
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-5">
        <div className="flex items-center gap-3 mb-5">
          <Cloud size={20} className="text-purple-400" />
          <h3 className="text-lg font-semibold text-slate-100">WebDAV 同步</h3>
        </div>

        <p className="text-xs text-slate-500 mb-4">
          仅支持 https:// endpoint。密码用 Windows DPAPI 加密（与当前用户/机器绑定，无法跨机迁移）。
        </p>

        <div className="space-y-3">
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">Endpoint URL</label>
            <input
              type="text"
              value={config.endpoint}
              onChange={(e) => update('endpoint', e.target.value)}
              placeholder="https://dav.example.com/Riptide/"
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs text-slate-400 mb-1.5">用户名</label>
              <input
                type="text"
                value={config.username}
                onChange={(e) => update('username', e.target.value)}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
              />
            </div>
            <div>
              <label className="block text-xs text-slate-400 mb-1.5">
                密码 {config.has_password && <span className="text-emerald-400 inline-flex items-center gap-1"><CheckCircle size={10}/>已保存</span>}
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder={config.has_password ? '保持不变留空' : ''}
                className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
              />
            </div>
          </div>
          <div>
            <label className="block text-xs text-slate-400 mb-1.5">远程路径</label>
            <input
              type="text"
              value={config.remote_path}
              onChange={(e) => update('remote_path', e.target.value)}
              className="w-full px-3 py-2 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-blue-500"
            />
          </div>
        </div>

        <div className="flex items-center gap-2 mt-5">
          <button
            onClick={save}
            disabled={busy !== null}
            className="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {busy === 'save' ? '保存中…' : '保存配置'}
          </button>
          <button
            onClick={test}
            disabled={busy !== null}
            className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {busy === 'test' ? '测试中…' : '测试连接'}
          </button>
          <button
            onClick={backup}
            disabled={busy !== null}
            className="ml-auto flex items-center gap-1.5 px-3 py-1.5 bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {busy === 'backup' ? <Loader2 size={14} className="animate-spin" /> : <Upload size={14} />}
            备份
          </button>
          <button
            onClick={restore}
            disabled={busy !== null}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-orange-600/20 hover:bg-orange-600/30 text-orange-400 rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {busy === 'restore' ? <Loader2 size={14} className="animate-spin" /> : <Download size={14} />}
            恢复
          </button>
        </div>

        {msg && <p className="mt-3 text-xs text-slate-400">{msg}</p>}
      </div>
    </div>
  );
}
