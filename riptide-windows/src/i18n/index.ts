import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';
import zhCN from './locales/zh-CN.json';
import enUS from './locales/en-US.json';
import faIR from './locales/fa-IR.json';
import ruRU from './locales/ru-RU.json';
import jaJP from './locales/ja-JP.json';
import koKR from './locales/ko-KR.json';
import ptBR from './locales/pt-BR.json';
import viVN from './locales/vi-VN.json';

const savedLang = localStorage.getItem('riptide-lang') || 'zh-CN';

export const SUPPORTED_LANGUAGES: { code: string; label: string }[] = [
  { code: 'zh-CN', label: '简体中文' },
  { code: 'en-US', label: 'English' },
  { code: 'ja-JP', label: '日本語' },
  { code: 'ko-KR', label: '한국어' },
  { code: 'ru-RU', label: 'Русский' },
  { code: 'fa-IR', label: 'فارسی' },
  { code: 'pt-BR', label: 'Português' },
  { code: 'vi-VN', label: 'Tiếng Việt' },
];

i18next.use(initReactI18next).init({
  resources: {
    'zh-CN': { translation: zhCN },
    'en-US': { translation: enUS },
    'ja-JP': { translation: jaJP },
    'ko-KR': { translation: koKR },
    'ru-RU': { translation: ruRU },
    'fa-IR': { translation: faIR },
    'pt-BR': { translation: ptBR },
    'vi-VN': { translation: viVN },
  },
  lng: savedLang,
  fallbackLng: 'en-US',
  interpolation: { escapeValue: false },
});

export default i18next;
