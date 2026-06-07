// Export button + JSONL snapshot download (Phase C C1).
//
// Calls `logbookExport` with the active from/to filter and a
// destination path. We compute a sensible default path locally (the
// Tauri save dialog plugin is not yet wired; Phase D adds it) — a
// `riptide-logbook-<utc-date>.jsonl` filename in the current working
// directory, which the Rust `logbook_export` then writes.
//
// For testability the path-generation helper is exported as
// `defaultExportPath` so the test can assert on the timestamp suffix
// shape without coupling to wall-clock time.

import { useState } from 'react';
import { Download, Loader2 } from 'lucide-react';
import { useLogbookExport } from '../../hooks/useLogbook';
import type { LogbookFilters as StoreFilters } from '../../stores/logbook';

export interface ExportButtonProps {
  filters: StoreFilters;
  /** Optional override for the destination path generator (tests). */
  pathFor?: (filters: StoreFilters) => string;
  /** Fired after the backend reports the number of written entries. */
  onExported?: (count: number) => void;
}

/** Build the default export filename. Exported for unit tests. */
export function defaultExportPath(filters: StoreFilters, now: Date = new Date()): string {
  const stamp = now.toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const tag =
    filters.from || filters.to
      ? `-from_${(filters.from ?? '').slice(0, 10)}_to_${(filters.to ?? '').slice(0, 10)}`
      : '';
  return `riptide-logbook-${stamp}${tag}.jsonl`;
}

export function ExportButton({ filters, pathFor, onExported }: ExportButtonProps) {
  const { mutateAsync, isPending, error } = useLogbookExport();
  const [lastError, setLastError] = useState<string | null>(null);

  const handleClick = async () => {
    setLastError(null);
    try {
      const dest = (pathFor ?? defaultExportPath)(filters);
      const result = await mutateAsync({
        from: filters.from,
        to: filters.to,
        destPath: dest,
      });
      onExported?.(result.written);
    } catch (e) {
      setLastError(String(e));
    }
  };

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={handleClick}
        disabled={isPending}
        data-testid="logbook-export-button"
        className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600/20 hover:bg-blue-600/30 border border-blue-500/40 rounded-md text-xs text-blue-200 transition-colors disabled:opacity-50"
      >
        {isPending ? <Loader2 size={12} className="animate-spin" /> : <Download size={12} />}
        Export JSONL
      </button>
      {(error || lastError) && (
        <p className="text-[10px] text-red-400 max-w-[200px] text-right">
          {String(error ?? lastError)}
        </p>
      )}
    </div>
  );
}
