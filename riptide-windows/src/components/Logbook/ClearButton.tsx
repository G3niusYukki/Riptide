// Clear button + built-in confirm dialog (Phase C C1).
//
// We use the browser's `window.confirm()` for the destructive step —
// it matches what `useLogbookClear.confirmAndClear` already does, and
// the hook is the canonical Phase B surface. The component wraps the
// hook so a future swap to a Tailwind-styled modal only touches this
// file.

import { useState } from 'react';
import { Trash2, Loader2 } from 'lucide-react';
import { useLogbookClear } from '../../hooks/useLogbook';

export interface ClearButtonProps {
  /** Optional message override. Default: "Clear all logbook entries?" */
  confirmMessage?: string;
  /** Fired after the backend reports a non-zero removed count. */
  onCleared?: (count: number) => void;
}

export function ClearButton({ confirmMessage, onCleared }: ClearButtonProps) {
  const { confirmAndClear, isPending, error } = useLogbookClear();
  const [lastError, setLastError] = useState<string | null>(null);

  const handleClick = async () => {
    setLastError(null);
    try {
      const result = await confirmAndClear(
        {},
        confirmMessage ?? 'Clear all logbook entries? This cannot be undone.',
      );
      // `confirmAndClear` returns null when the user cancels.
      if (result && typeof result.removed === 'number') {
        onCleared?.(result.removed);
      }
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
        data-testid="logbook-clear-button"
        className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-800 hover:bg-red-500/20 hover:text-red-300 border border-slate-700 hover:border-red-500/30 rounded-md text-xs text-slate-300 transition-colors disabled:opacity-50"
      >
        {isPending ? <Loader2 size={12} className="animate-spin" /> : <Trash2 size={12} />}
        Clear
      </button>
      {(error || lastError) && (
        <p className="text-[10px] text-red-400 max-w-[200px] text-right">
          {String(error ?? lastError)}
        </p>
      )}
    </div>
  );
}
