import { X, CheckCircle, AlertCircle, Info } from 'lucide-react';
import { useToastStore } from '../../stores/toast';

const iconMap = {
  success: CheckCircle,
  error: AlertCircle,
  info: Info,
};

const colorMap = {
  success: 'border-emerald-600 bg-emerald-900/30',
  error: 'border-red-600 bg-red-900/30',
  info: 'border-blue-600 bg-blue-900/30',
};

export function ToastContainer() {
  const { toasts, removeToast } = useToastStore();

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      {toasts.map((toast) => {
        const Icon = iconMap[toast.type];
        return (
          <div
            key={toast.id}
            className={`flex items-start gap-3 px-4 py-3 rounded-lg border shadow-lg animate-slideIn ${colorMap[toast.type]}`}
          >
            <Icon size={18} className="flex-shrink-0 mt-0.5 text-slate-200" />
            <p className="text-sm text-slate-200 flex-1">{toast.message}</p>
            <button
              onClick={() => removeToast(toast.id)}
              className="text-slate-400 hover:text-slate-200 flex-shrink-0"
            >
              <X size={14} />
            </button>
          </div>
        );
      })}
    </div>
  );
}
