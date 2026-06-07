// Settings/AppearanceTab.tsx
//
// Phase C10.1 + C10.2 — Appearance settings tab.
//
// Layout (3 stacked cards, mirrors macOS `AppearanceSettingsView` in
// `Sources/RiptideApp/Views/AppearanceSettingsView.swift`):
//   1. **主题 (Theme)** — 3-mode segmented control: 跟随系统 / 浅色 / 深色.
//      Backed by the shared `useTheme` hook so the value survives reloads
//      (persisted via the riptide Zustand store).
//   2. **字体 (Font)** — preview text using the global typography tokens
//      (`--font-sans` / `--font-size-base` / `--font-weight-*`). Read-only
//      in the MVP; the goal of C10.2 is to *visualise* the existing
//      design tokens so users see the same family on every screen.
//   3. **间距 (Spacing) / 圆角 (Radius)** — visual scale (sm / md / lg)
//      rendered with the `--space-*` and `--radius-*` CSS variables,
//      proving the token switch is wired all the way through.
//
// C10.2 also adds the 3 token blocks (`--space-*`, `--radius-*`,
// `--font-*`) to `styles/tokens.css` and exposes them as
// `--font-sans`, `--radius-sm|md|lg`, `--space-1..6` so this view can
// pick them up directly. Existing CSS custom properties (e.g.
// `--bg-primary`) are unchanged.

import { Sun, Moon, Monitor, Type, Ruler, Square } from 'lucide-react';
import { useTheme, type ThemeMode } from '../../hooks/useTheme';

interface ModeOption {
  id: ThemeMode;
  label: string;
  description: string;
  Icon: typeof Sun;
  testid: string;
}

const MODE_OPTIONS: ModeOption[] = [
  {
    id: 'system',
    label: '跟随系统',
    description: '与 Windows 系统设置同步',
    Icon: Monitor,
    testid: 'appearance-mode-system',
  },
  {
    id: 'light',
    label: '浅色',
    description: '明亮环境下的高对比度配色',
    Icon: Sun,
    testid: 'appearance-mode-light',
  },
  {
    id: 'dark',
    label: '深色',
    description: '默认深色主题,适合长时间使用',
    Icon: Moon,
    testid: 'appearance-mode-dark',
  },
];

/** Visual scale for `--space-*` (used in the spacing card). */
const SPACING_SAMPLE: Array<{ token: string; label: string; px: number }> = [
  { token: '--space-1', label: 'xs', px: 4 },
  { token: '--space-2', label: 'sm', px: 8 },
  { token: '--space-3', label: 'md', px: 12 },
  { token: '--space-4', label: 'lg', px: 16 },
  { token: '--space-5', label: 'xl', px: 24 },
  { token: '--space-6', label: '2xl', px: 32 },
];

const RADIUS_SAMPLE: Array<{ token: string; label: string; px: number }> = [
  { token: '--radius-sm', label: '小 (sm)', px: 4 },
  { token: '--radius-md', label: '中 (md)', px: 8 },
  { token: '--radius-lg', label: '大 (lg)', px: 12 },
];

export function AppearanceTab() {
  const { theme, resolvedTheme, setTheme } = useTheme();

  return (
    <div className="space-y-6" data-testid="appearance-tab">
      {/* Card 1: Theme mode selector (3-option segmented control). */}
      <section
        className="bg-slate-900/50 border border-slate-800 rounded-xl p-5"
        data-testid="appearance-theme-card"
      >
        <header className="flex items-center gap-3 mb-4">
          {resolvedTheme === 'dark' ? (
            <Moon size={20} className="text-blue-400" />
          ) : (
            <Sun size={20} className="text-amber-400" />
          )}
          <div>
            <h3 className="text-lg font-semibold text-slate-100">主题</h3>
            <p className="text-xs text-slate-500 mt-1">
              选择应用外观。当前生效:
              <span
                className="ml-1 font-mono text-blue-300"
                data-testid="appearance-resolved-theme"
              >
                {resolvedTheme === 'dark' ? '深色' : '浅色'}
              </span>
              {theme === 'system' && <span className="ml-1 text-slate-500">(跟随系统)</span>}
            </p>
          </div>
        </header>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2" role="radiogroup" aria-label="主题模式">
          {MODE_OPTIONS.map(({ id, label, description, Icon, testid }) => {
            const selected = theme === id;
            return (
              <button
                key={id}
                type="button"
                role="radio"
                aria-checked={selected}
                data-testid={testid}
                onClick={() => setTheme(id)}
                className={[
                  'flex flex-col items-start gap-1.5 p-3 rounded-lg border text-left transition-colors',
                  selected
                    ? 'border-blue-500 bg-blue-500/10 ring-1 ring-blue-500/40'
                    : 'border-slate-700 hover:border-slate-500 bg-slate-800/40',
                ].join(' ')}
              >
                <span className="flex items-center gap-2">
                  <Icon
                    size={16}
                    className={selected ? 'text-blue-300' : 'text-slate-400'}
                  />
                  <span className="text-sm font-medium text-slate-100">{label}</span>
                </span>
                <span className="text-[11px] text-slate-500 leading-relaxed">{description}</span>
              </button>
            );
          })}
        </div>
      </section>

      {/* Card 2: Typography preview (font family / size / weight tokens). */}
      <section
        className="bg-slate-900/50 border border-slate-800 rounded-xl p-5"
        data-testid="appearance-font-card"
      >
        <header className="flex items-center gap-3 mb-4">
          <Type size={20} className="text-emerald-400" />
          <div>
            <h3 className="text-lg font-semibold text-slate-100">字体</h3>
            <p className="text-xs text-slate-500 mt-1">
              全局使用 Segoe UI 栈,通过
              <code className="mx-1 px-1 py-0.5 rounded bg-slate-800 text-slate-300 font-mono text-[10px]">
                --font-sans
              </code>
              统一引用。
            </p>
          </div>
        </header>

        <div className="space-y-2.5" style={{ fontFamily: 'var(--font-sans)' }}>
          <p className="text-2xl font-semibold text-slate-100" data-testid="appearance-font-sample-xl">
            The quick brown fox
          </p>
          <p className="text-base text-slate-200" data-testid="appearance-font-sample-base">
            一只敏捷的棕色狐狸跃过懒狗。
          </p>
          <p className="text-sm text-slate-400" data-testid="appearance-font-sample-sm">
            0123456789 · Proxies · Profiles · Rules · Logs
          </p>
          <p className="text-xs text-slate-500 font-mono" data-testid="appearance-font-sample-mono">
            monospace: const theme = useTheme();
          </p>
        </div>
      </section>

      {/* Card 3: Spacing + Radius token preview. */}
      <section
        className="bg-slate-900/50 border border-slate-800 rounded-xl p-5"
        data-testid="appearance-tokens-card"
      >
        <header className="flex items-center gap-3 mb-4">
          <Ruler size={20} className="text-violet-400" />
          <div>
            <h3 className="text-lg font-semibold text-slate-100">间距 · 圆角</h3>
            <p className="text-xs text-slate-500 mt-1">
              间距 / 圆角 token 在所有面板、卡片、按钮间共享,避免散落的魔数。
            </p>
          </div>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
          {/* Spacing scale */}
          <div data-testid="appearance-spacing-scale">
            <p className="text-xs text-slate-400 mb-2 flex items-center gap-1.5">
              <Ruler size={12} /> 间距 (--space-*)
            </p>
            <ul className="space-y-1.5">
              {SPACING_SAMPLE.map((s) => (
                <li key={s.token} className="flex items-center gap-3 text-xs">
                  <span
                    className="inline-block bg-blue-500/30 border border-blue-500/50"
                    style={{ width: `${s.px}px`, height: '10px' }}
                    aria-hidden
                  />
                  <span className="font-mono text-slate-300 w-20">{s.token}</span>
                  <span className="text-slate-500">{s.label}</span>
                  <span className="text-slate-600 ml-auto">{s.px}px</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Radius scale */}
          <div data-testid="appearance-radius-scale">
            <p className="text-xs text-slate-400 mb-2 flex items-center gap-1.5">
              <Square size={12} /> 圆角 (--radius-*)
            </p>
            <div className="flex flex-wrap gap-3">
              {RADIUS_SAMPLE.map((r) => (
                <div
                  key={r.token}
                  className="flex flex-col items-center gap-1.5"
                  data-testid={`appearance-radius-${r.token.replace('--radius-', '')}`}
                >
                  <div
                    className="w-14 h-14 bg-violet-500/30 border border-violet-500/50"
                    style={{ borderRadius: `var(${r.token})` }}
                    aria-hidden
                  />
                  <span className="text-[10px] font-mono text-slate-300">{r.token}</span>
                  <span className="text-[10px] text-slate-500">{r.px}px</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
