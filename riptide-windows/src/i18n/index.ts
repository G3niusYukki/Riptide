import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';
import zhCN from './locales/zh-CN.json';
import enUS from './locales/en-US.json';
import faIR from './locales/fa-IR.json';
import ruRU from './locales/ru-RU.json';
import jaJP from './locales/ja-JP.json';

// fa-IR / ru-RU / ja-JP are seeded with English strings for now — replace
// with native translations as community contributions come in. The keys
// match en-US 1:1 so the fallback path is a no-op once translated.
const savedLang = localStorage.getItem('riptide-lang') || 'zh-CN';

export const SUPPORTED_LANGUAGES: { code: string; label: string }[] = [
  { code: 'zh-CN', label: '简体中文' },
  { code: 'en-US', label: 'English' },
  { code: 'fa-IR', label: 'فارسی' },
  { code: 'ru-RU', label: 'Русский' },
  { code: 'ja-JP', label: '日本語' },
];

i18next.use(initReactI18next).init({
  resources: {
    'zh-CN': { translation: zhCN },
    'en-US': { translation: enUS },
    'fa-IR': { translation: faIR },
    'ru-RU': { translation: ruRU },
    'ja-JP': { translation: jaJP },
  },
  lng: savedLang,
  fallbackLng: 'en-US',
  interpolation: { escapeValue: false },
});

export default i18next;
