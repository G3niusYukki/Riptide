// Single row in the Logbook table. Kept small and side-effect free so
// tests can render it standalone and the parent table stays readable.

import { format } from 'date-fns';
import type { LogEntry, LogLevel } from '../../services/tauri';

const LEVEL_COLOR: Record<LogLevel, string> = {
  info: 'bg-blue-500/15 text-blue-300 border-blue-500/30',
  warning: 'bg-yellow-500/15 text-yellow-300 border-yellow-500/30',
  error: 'bg-red-500/15 text-red-300 border-red-500/30',
  debug: 'bg-slate-500/15 text-slate-300 border-slate-500/30',
};

export interface LogEntryRowProps {
  entry: LogEntry;
}

export function LogEntryRow({ entry }: LogEntryRowProps) {
  // The Rust side emits millisecond-precision UTC ISO 8601. `format`
  // expects a Date; new Date(iso) handles the trailing Z. We render in
  // the viewer's local timezone (date-fns default), which is what the
  // macOS Logbook does too.
  const ts = format(new Date(entry.ts), 'yyyy-MM-dd HH:mm:ss');

  return (
    <tr
      className="border-b border-slate-800/60 hover:bg-slate-800/30 transition-colors"
      data-testid="logbook-row"
      data-level={entry.level}
      data-category={entry.category}
    >
      <td className="px-3 py-1.5 font-mono text-[11px] text-slate-400 whitespace-nowrap">
        {ts}
      </td>
      <td className="px-3 py-1.5">
        <span
          className={`inline-flex items-center px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide rounded border ${LEVEL_COLOR[entry.level]}`}
        >
          {entry.level}
        </span>
      </td>
      <td className="px-3 py-1.5 text-slate-400 text-xs font-mono">{entry.category}</td>
      <td className="px-3 py-1.5 text-slate-200 break-words">{entry.message}</td>
    </tr>
  );
}
