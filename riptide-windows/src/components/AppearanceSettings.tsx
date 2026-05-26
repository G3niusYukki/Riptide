import React from 'react';
import { useTheme, ThemeName } from '../hooks/useTheme';

const THEME_PREVIEWS: Record<ThemeName, { bg: string; text: string; accent: string }> = {
  dark: { bg: '#0f172a', text: '#f1f5f9', accent: '#3b82f6' },
  light: { bg: '#ffffff', text: '#0f172a', accent: '#3b82f6' },
  nord: { bg: '#2e3440', text: '#eceff4', accent: '#88c0d0' },
  dracula: { bg: '#282a36', text: '#f8f8f2', accent: '#bd93f9' },
  'solarized-dark': { bg: '#002b36', text: '#839496', accent: '#268bd2' },
};

export function AppearanceSettings() {
  const { theme, setTheme, availableThemes, getThemeLabel, getThemeDescription } = useTheme();

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-lg font-medium text-primary">Appearance</h3>
        <p className="text-sm text-secondary mt-1">
          Customize the look and feel of Riptide
        </p>
      </div>

      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-primary mb-3">
            Theme
          </label>
          <div className="grid grid-cols-2 gap-3">
            {availableThemes.map((themeName) => (
              <ThemeCard
                key={themeName}
                name={themeName}
                label={getThemeLabel(themeName)}
                description={getThemeDescription(themeName)}
                preview={THEME_PREVIEWS[themeName]}
                isSelected={theme === themeName}
                onSelect={() => setTheme(themeName)}
              />
            ))}
          </div>
        </div>
      </div>

      <div className="pt-4 border-t border-primary">
        <p className="text-xs text-muted">
          Theme preference is saved locally and will persist across sessions.
        </p>
      </div>
    </div>
  );
}

interface ThemeCardProps {
  name: ThemeName;
  label: string;
  description: string;
  preview: { bg: string; text: string; accent: string };
  isSelected: boolean;
  onSelect: () => void;
}

function ThemeCard({ name, label, description, preview, isSelected, onSelect }: ThemeCardProps) {
  return (
    <button
      onClick={onSelect}
      className={`
        relative p-4 rounded-lg border-2 transition-all duration-200
        ${isSelected
          ? 'border-accent-primary bg-accent-bg'
          : 'border-border-primary hover:border-border-secondary bg-bg-secondary'
        }
      `}
    >
      {/* Theme preview */}
      <div
        className="w-full h-16 rounded-md mb-3 flex items-center justify-center"
        style={{ backgroundColor: preview.bg }}
      >
        <div className="flex space-x-2">
          <div
            className="w-3 h-3 rounded-full"
            style={{ backgroundColor: preview.accent }}
          />
          <div
            className="w-8 h-2 rounded-full"
            style={{ backgroundColor: preview.text, opacity: 0.6 }}
          />
          <div
            className="w-6 h-2 rounded-full"
            style={{ backgroundColor: preview.text, opacity: 0.4 }}
          />
        </div>
      </div>

      {/* Theme info */}
      <div className="text-left">
        <h4 className="font-medium text-primary">{label}</h4>
        <p className="text-xs text-secondary mt-1">{description}</p>
      </div>

      {/* Selected indicator */}
      {isSelected && (
        <div className="absolute top-2 right-2">
          <svg
            className="w-5 h-5 text-accent-primary"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fillRule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
              clipRule="evenodd"
            />
          </svg>
        </div>
      )}
    </button>
  );
}
