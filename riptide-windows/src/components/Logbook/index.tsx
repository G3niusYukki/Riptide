// Logbook main page (Phase C C1).
//
// Mirrors the macOS `LogbookViewModel` mental model: a top filter bar
// (level + category + from/to) and a main table of entries below.
// The data side lives in `useLogbook` (TanStack Query) which mirrors
// results into the Zustand store. This page is the read-side
// subscriber — it pulls the latest entries via the hook and renders
// the table.

import { useMemo } from 'react';
import { useLogbook } from '../../hooks/useLogbook';
import { useLogbookStore, type LogbookFilters as StoreFilters } from '../../stores/logbook';
import { LogbookFilters } from './LogbookFilters';
import { LogEntryRow } from './LogEntryRow';
import { ClearButton } from './ClearButton';
import { ExportButton } from './ExportButton';
import { useToastStore } from '../../stores/toast';
import { FileText, Loader2 } from 'lucide-react';
import type { LogEntry } from '../../services/tauri';

const PAGE_LIMIT = 500;

export function LogbookView() {
  const filters = useLogbookStore((s) => s.filters);
  const setFilter = useLogbookStore((s) => s.setFilter);
  const addToast = useToastStore((s) => s.addToast);

  // Drive the query off the store filters so the URL/route doesn't
  // need to track them. The hook auto-refetches on focus + on filter
  // change (different queryKey per filter tuple).
  const query = useLogbook({
    limit: PAGE_LIMIT,
    level: filters.level,
    category: filters.category,
    from: filters.from,
    to: filters.to,
  });

  const entries: LogEntry[] = query.data ?? [];

  // Defensive client-side filter pass: the Rust backend already
  // filters by the same fields, but this guards against transient
  // queryKey mismatches when filters change in quick succession.
  const visibleEntries = useMemo(() => {
    if (entries.length === 0) return entries;
    return entries.filter((entry) => {
      if (filters.level && entry.level !== filters.level) return false;
      if (filters.category && entry.category !== filters.category) return false;
      if (filters.from && entry.ts < filters.from) return false;
      if (filters.to && entry.ts > filters.to) return false;
      return true;
    });
  }, [entries, filters]);

  const handleFilterChange = (patch: Partial<StoreFilters>) => {
    setFilter(patch);
  };

  return (
    <div className="space-y-4 h-full flex flex-col">
      <div className="flex items-center justify-between flex-shrink-0">
        <div>
          <h2 className="text-2xl font-bold text-slate-100">Logbook</h2>
          <p className="text-xs text-slate-500 mt-1">
            Persistent diagnostic event journal · JSONL per UTC day
          </p>
        </div>
        <div className="flex items-center gap-2">
          <ExportButton filters={filters} />
          <ClearButton onCleared={(count) => addToast(`Cleared ${count} entries`, 'success')} />
        </div>
      </div>

      <LogbookFilters filters={filters} onChange={handleFilterChange} />

      {query.error && (
        <div className="bg-red-900/20 border border-red-800 rounded-lg px-4 py-3 flex-shrink-0">
          <p className="text-red-400 text-sm">Failed to load logbook: {String(query.error)}</p>
        </div>
      )}

      <div
        className="flex-1 bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden min-h-0 flex flex-col"
        data-testid="logbook-table-wrapper"
      >
        {query.isLoading ? (
          <div className="flex items-center justify-center flex-1 text-slate-500">
            <Loader2 size={20} className="animate-spin mr-2" />
            Loading logbook…
          </div>
        ) : visibleEntries.length === 0 ? (
          <div className="flex flex-col items-center justify-center flex-1 text-slate-500 py-12">
            <FileText size={36} className="mb-3 text-slate-700" />
            <p className="text-sm">No log entries</p>
            <p className="text-xs text-slate-600 mt-1">
              Mode switches, subscription refreshes, and recovery events land here automatically.
            </p>
          </div>
        ) : (
          <div className="overflow-auto flex-1">
            <table className="w-full text-sm" data-testid="logbook-table">
              <thead className="bg-slate-900/80 sticky top-0 z-10">
                <tr className="text-left text-[11px] uppercase tracking-wider text-slate-500 border-b border-slate-800">
                  <th className="px-3 py-2 font-medium">Time</th>
                  <th className="px-3 py-2 font-medium w-20">Level</th>
                  <th className="px-3 py-2 font-medium w-28">Category</th>
                  <th className="px-3 py-2 font-medium">Message</th>
                </tr>
              </thead>
              <tbody data-testid="logbook-rows">
                {visibleEntries.map((entry, idx) => (
                  <LogEntryRow key={`${entry.ts}-${idx}`} entry={entry} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between text-[11px] text-slate-500 flex-shrink-0">
        <span>
          {visibleEntries.length} {visibleEntries.length === 1 ? 'entry' : 'entries'}
          {query.isFetching && !query.isLoading ? ' · refreshing…' : ''}
        </span>
        <span>
          Showing up to {PAGE_LIMIT} most recent
        </span>
      </div>
    </div>
  );
}
