import { useState, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { Play, Trash2, FileCode2, Loader2, AlertCircle, CheckCircle2 } from 'lucide-react';
import { scriptEval, scriptListLoaded, scriptUnload } from '../../services/tauri';

interface EvalResult {
  output: string;
  isError: boolean;
}

export function ScriptEditorView() {
  const { t } = useTranslation();
  const [code, setCode] = useState('// SurgeScript-compatible JavaScript\n// Available globals: $request, $done, $persistentStore, $notification\n\nfunction handleRequestModify(request) {\n  // Modify request.headers and return them\n  return request;\n}\n');
  const [result, setResult] = useState<EvalResult | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [loadedScripts, setLoadedScripts] = useState<string[]>([]);

  const handleEval = useCallback(async () => {
    setIsRunning(true);
    setResult(null);
    try {
      const output = await scriptEval(code);
      setResult({ output, isError: false });
      // Refresh loaded scripts list
      const scripts = await scriptListLoaded();
      setLoadedScripts(scripts);
    } catch (err) {
      setResult({
        output: String(err),
        isError: true,
      });
    } finally {
      setIsRunning(false);
    }
  }, [code]);

  const handleUnload = useCallback(async (name: string) => {
    try {
      await scriptUnload(name);
      const scripts = await scriptListLoaded();
      setLoadedScripts(scripts);
    } catch {
      // ignore unload errors
    }
  }, []);

  const handleClear = useCallback(() => {
    setResult(null);
  }, []);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <FileCode2 className="w-5 h-5 text-blue-400" />
          <h2 className="text-lg font-semibold text-white">
            {t('scriptEditor.title', 'Script Editor')}
          </h2>
        </div>
        <div className="flex items-center gap-2">
          {result && (
            <button
              onClick={handleClear}
              className="px-3 py-1.5 text-xs rounded bg-zinc-700 text-zinc-300 hover:bg-zinc-600 transition-colors"
            >
              {t('scriptEditor.clear', 'Clear')}
            </button>
          )}
          <button
            onClick={handleEval}
            disabled={isRunning || !code.trim()}
            className="flex items-center gap-1.5 px-4 py-1.5 text-sm rounded bg-blue-600 text-white hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {isRunning ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Play className="w-4 h-4" />
            )}
            {t('scriptEditor.run', 'Run')}
          </button>
        </div>
      </div>

      {/* Description */}
      <p className="text-sm text-zinc-400">
        {t(
          'scriptEditor.description',
          'Write and test SurgeScript-compatible JavaScript. Scripts can modify HTTP requests and responses via $request, $done, and $persistentStore globals.',
        )}
      </p>

      {/* Code editor (plain textarea — CodeMirror integration comes later) */}
      <div className="relative">
        <textarea
          value={code}
          onChange={(e) => setCode(e.target.value)}
          spellCheck={false}
          className="w-full h-64 p-4 font-mono text-sm bg-zinc-900 text-zinc-100 border border-zinc-700 rounded-lg resize-y focus:outline-none focus:border-blue-500 transition-colors"
          placeholder={t('scriptEditor.placeholder', '// Enter JavaScript code here...')}
        />
      </div>

      {/* Result panel */}
      {result && (
        <div
          className={`p-4 rounded-lg border ${
            result.isError
              ? 'bg-red-950/30 border-red-800'
              : 'bg-emerald-950/30 border-emerald-800'
          }`}
        >
          <div className="flex items-center gap-2 mb-2">
            {result.isError ? (
              <AlertCircle className="w-4 h-4 text-red-400" />
            ) : (
              <CheckCircle2 className="w-4 h-4 text-emerald-400" />
            )}
            <span
              className={`text-sm font-medium ${
                result.isError ? 'text-red-300' : 'text-emerald-300'
              }`}
            >
              {result.isError
                ? t('scriptEditor.error', 'Error')
                : t('scriptEditor.success', 'Success')}
            </span>
          </div>
          <pre className="text-xs text-zinc-300 overflow-x-auto whitespace-pre-wrap break-all">
            {result.output}
          </pre>
        </div>
      )}

      {/* Loaded scripts */}
      {loadedScripts.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-medium text-zinc-300">
            {t('scriptEditor.loadedScripts', 'Loaded Scripts')}
          </h3>
          <div className="flex flex-wrap gap-2">
            {loadedScripts.map((name) => (
              <div
                key={name}
                className="flex items-center gap-1.5 px-3 py-1 bg-zinc-800 rounded-full text-xs text-zinc-300"
              >
                <FileCode2 className="w-3 h-3" />
                <span>{name}</span>
                <button
                  onClick={() => handleUnload(name)}
                  className="ml-1 text-zinc-500 hover:text-red-400 transition-colors"
                  title={t('scriptEditor.unload', 'Unload')}
                >
                  <Trash2 className="w-3 h-3" />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
