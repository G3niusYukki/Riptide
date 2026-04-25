import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';
import zhCN from './locales/zh-CN.json';
import enUS from './locales/en-US.json';

const savedLang = localStorage.getItem('riptide-lang') || 'zh-CN';

i18next.use(initReactI18next).init({
  resources: {
    'zh-CN': { translation: zhCN },
    'en-US': { translation: enUS },
  },
  lng: savedLang,
  fallbackLng: 'zh-CN',
  interpolation: { escapeValue: false },
});

export default i18next;
