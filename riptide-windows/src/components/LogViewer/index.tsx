import { useState, useEffect, useRef, useCallback } from 'react';
import { useRiptideStore } from '../../stores/riptide';
import { Terminal, Loader2, RefreshCw } from 'lucide-react';
import * as tauri from '../../services/tauri';

const LEVELS = ['info', 'warning', 'error', 'debug'] as const;

export function LogViewer() {
  const { isRunning } = useRiptideStore();
  const [level, setLevel] = useState<string>('info');
  const [lines, setLines] = useState(100);
  const [logText, setLogText] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);

  const fetchLogs = useCallback(async () => {
    if (!isRunning) return;
    setLoading(true);
    setError(null);
    try {
      const text = await tauri.getLogs(level, lines);
      setLogText(text);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, [isRunning, level, lines]);

  useEffect(() => {
    fetchLogs();
    if (!isRunning) {
      setLogText('');
      return;
    }
    const interval = setInterval(fetchLogs, 3000);
    return () => clearInterval(interval);
  }, [fetchLogs, isRunning]);

  useEffect(() => {
    if (autoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logText, autoScroll]);

  const handleScroll = () => {
    if (!scrollRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
    setAutoScroll(scrollHeight - scrollTop - clientHeight < 40);
  };

  if (!isRunning) {
    return (
      <div className="space-y-5">
        <h2 className="text-2xl font-bold text-slate-100">日志</h2>
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Terminal size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">启动代理以查看实时日志</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4 h-full flex flex-col">
      <div className="flex items-center justify-between flex-shrink-0">
        <h2 className="text-2xl font-bold text-slate-100">日志</h2>
        <div className="flex items-center gap-3">
          <select
            value={level}
            onChange={(e) => setLevel(e.target.value)}
            className="px-3 py-1.5 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-blue-500"
          >
            {LEVELS.map((l) => (
              <option key={l} value={l}>{l.toUpperCase()}</option>
            ))}
          </select>
          <input
            type="number"
            value={lines}
            onChange={(e) => setLines(Number(e.target.value) || 100)}
            min={10}
            max={1000}
            className="w-20 px-2 py-1.5 bg-slate-800 border border-slate-700 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-blue-500"
            title="行数"
          />
          <button
            onClick={fetchLogs}
            disabled={loading}
            className="p-2 bg-slate-800 hover:bg-slate-700 rounded-lg text-slate-400 transition-colors"
          >
            <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-900/20 border border-red-800 rounded-lg px-4 py-3 flex-shrink-0">
          <p className="text-red-400 text-sm">{error}</p>
        </div>
      )}

      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 bg-slate-950 border border-slate-800 rounded-xl p-4 font-mono text-xs overflow-auto min-h-0"
      >
        {loading && !logText ? (
          <div className="flex items-center justify-center h-full">
            <Loader2 size={24} className="text-blue-400 animate-spin" />
            <span className="ml-2 text-slate-500">加载日志中...</span>
          </div>
        ) : logText ? (
          <pre className="text-slate-300 whitespace-pre-wrap select-text">{logText}</pre>
        ) : (
          <div className="flex items-center justify-center h-full">
            <span className="text-slate-600">暂无日志</span>
          </div>
        )}
      </div>
    </div>
  );
}
