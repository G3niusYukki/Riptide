// Filter bar above the Logbook table.
//
// Three independent axes (level / category / date range). Each axis
// has a "clear" affordance. Date inputs use the browser's native
// `type="date"` (yyyy-mm-dd) and we convert to inclusive ISO 8601
// bounds at submit time so the user picks a calendar day, not a
// timestamp.

import type { LogCategory, LogLevel } from '../../services/tauri';
import type { LogbookFilters as StoreFilters } from '../../stores/logbook';
import { X } from 'lucide-react';

export interface LogbookFiltersProps {
  filters: StoreFilters;
  onChange: (patch: Partial<StoreFilters>) => void;
}

const LEVELS: LogLevel[] = ['debug', 'info', 'warning', 'error'];

// The Rust writer only emits the five known categories from the
// catchup plan §C1 (mode / subscription / service / sysproxy /
// recovery), but the LogCategory union is open (string & {}) so
// callers can also see custom values.
const CATEGORIES: LogCategory[] = ['mode', 'subscription', 'service', 'sysproxy', 'recovery'];

export function LogbookFilters({ filters, onChange }: LogbookFiltersProps) {
  const hasAny = Boolean(filters.level || filters.category || filters.from || filters.to);

  const clearAll = () => {
    onChange({ level: undefined, category: undefined, from: undefined, to: undefined });
  };

  return (
    <div
      className="flex flex-wrap items-end gap-3 bg-slate-900/40 border border-slate-800 rounded-xl p-3"
      data-testid="logbook-filters"
    >
      <div className="flex flex-col gap-1">
        <label className="text-[10px] uppercase tracking-wider text-slate-500">Level</label>
        <select
          data-testid="filter-level"
          value={filters.level ?? ''}
          onChange={(e) =>
            onChange({ level: (e.target.value || undefined) as LogLevel | undefined })
          }
          className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500 min-w-[110px]"
        >
          <option value="">All</option>
          {LEVELS.map((l) => (
            <option key={l} value={l}>
              {l}
            </option>
          ))}
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-[10px] uppercase tracking-wider text-slate-500">Category</label>
        <select
          data-testid="filter-category"
          value={filters.category ?? ''}
          onChange={(e) =>
            onChange({ category: (e.target.value || undefined) as LogCategory | undefined })
          }
          className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500 min-w-[140px]"
        >
          <option value="">All</option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-[10px] uppercase tracking-wider text-slate-500">From</label>
        <input
          data-testid="filter-from"
          type="date"
          value={filters.from ? filters.from.slice(0, 10) : ''}
          onChange={(e) => {
            const v = e.target.value;
            onChange({ from: v ? `${v}T00:00:00.000Z` : undefined });
          }}
          className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500"
        />
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-[10px] uppercase tracking-wider text-slate-500">To</label>
        <input
          data-testid="filter-to"
          type="date"
          value={filters.to ? filters.to.slice(0, 10) : ''}
          onChange={(e) => {
            const v = e.target.value;
            onChange({ to: v ? `${v}T23:59:59.999Z` : undefined });
          }}
          className="px-2.5 py-1.5 bg-slate-800 border border-slate-700 rounded-md text-xs text-slate-100 focus:outline-none focus:border-blue-500"
        />
      </div>

      {hasAny && (
        <button
          onClick={clearAll}
          className="ml-auto flex items-center gap-1 px-2.5 py-1.5 bg-slate-800 hover:bg-slate-700 rounded-md text-xs text-slate-300 transition-colors"
        >
          <X size={12} /> Clear filters
        </button>
      )}
    </div>
  );
}
