import { useState, useEffect, useCallback } from 'react';

export type ThemeName = 'dark' | 'light' | 'nord' | 'dracula' | 'solarized-dark';

const STORAGE_KEY = 'riptide-theme';

const THEME_LABELS: Record<ThemeName, string> = {
  dark: 'Dark',
  light: 'Light',
  nord: 'Nord',
  dracula: 'Dracula',
  'solarized-dark': 'Solarized Dark',
};

const THEME_DESCRIPTIONS: Record<ThemeName, string> = {
  dark: 'Default dark theme with slate blue tones',
  light: 'Clean light theme for bright environments',
  nord: 'Arctic, north-bluish color palette',
  dracula: 'Dark theme with vibrant purple accents',
  'solarized-dark': 'Precision colors for machines and people',
};

export function useTheme() {
  const [theme, setThemeState] = useState<ThemeName>(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored && isValidTheme(stored)) {
      return stored;
    }
    // Detect system preference
    if (window.matchMedia('(prefers-color-scheme: light)').matches) {
      return 'light';
    }
    return 'dark';
  });

  const setTheme = useCallback((newTheme: ThemeName) => {
    setThemeState(newTheme);
    localStorage.setItem(STORAGE_KEY, newTheme);
    document.documentElement.setAttribute('data-theme', newTheme);
  }, []);

  useEffect(() => {
    // Apply theme on mount
    document.documentElement.setAttribute('data-theme', theme);

    // Listen for system theme changes
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handleChange = (e: MediaQueryListEvent) => {
      // Only auto-switch if user hasn't manually set a theme
      const stored = localStorage.getItem(STORAGE_KEY);
      if (!stored) {
        setThemeState(e.matches ? 'dark' : 'light');
        document.documentElement.setAttribute('data-theme', e.matches ? 'dark' : 'light');
      }
    };

    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, [theme]);

  const toggleTheme = useCallback(() => {
    const themes: ThemeName[] = ['dark', 'light', 'nord', 'dracula', 'solarized-dark'];
    const currentIndex = themes.indexOf(theme);
    const nextIndex = (currentIndex + 1) % themes.length;
    setTheme(themes[nextIndex]);
  }, [theme, setTheme]);

  return {
    theme,
    setTheme,
    toggleTheme,
    themeLabel: THEME_LABELS[theme],
    themeDescription: THEME_DESCRIPTIONS[theme],
    availableThemes: Object.keys(THEME_LABELS) as ThemeName[],
    getThemeLabel: (name: ThemeName) => THEME_LABELS[name],
    getThemeDescription: (name: ThemeName) => THEME_DESCRIPTIONS[name],
  };
}

function isValidTheme(value: string): value is ThemeName {
  return ['dark', 'light', 'nord', 'dracula', 'solarized-dark'].includes(value as ThemeName);
}
