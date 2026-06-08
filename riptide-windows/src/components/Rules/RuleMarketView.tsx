import { useState, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { Package, CheckCircle2, Download, Shield, Globe, Ban, Wifi, Sparkles } from 'lucide-react';
import { useToastStore } from '../../stores/toast';

interface RuleSetMeta {
  id: string;
  name: string;
  description: string;
  category: 'privacy' | 'routing' | 'media';
  count: number;
}

const BUNDLED_RULESETS: RuleSetMeta[] = [
  {
    id: 'reject-ads',
    name: 'ruleset.reject-ads.name',
    description: 'ruleset.reject-ads.description',
    category: 'privacy',
    count: 50,
  },
  {
    id: 'cn-domain',
    name: 'ruleset.cn-domain.name',
    description: 'ruleset.cn-domain.description',
    category: 'routing',
    count: 50,
  },
  {
    id: 'geoip-cn',
    name: 'ruleset.geoip-cn.name',
    description: 'ruleset.geoip-cn.description',
    category: 'routing',
    count: 8000,
  },
  {
    id: 'apple-services',
    name: 'ruleset.apple-services.name',
    description: 'ruleset.apple-services.description',
    category: 'routing',
    count: 38,
  },
];

const categoryIcons: Record<string, typeof Shield> = {
  privacy: Ban,
  routing: Globe,
  media: Wifi,
};

const categoryColors: Record<string, string> = {
  privacy: 'text-red-400',
  routing: 'text-blue-400',
  media: 'text-purple-400',
};

interface RuleMarketViewProps {
  /** Override bundled list for testing. Omit to use the default. */
  bundledRuleSets?: RuleSetMeta[];
}

export function RuleMarketView({ bundledRuleSets }: RuleMarketViewProps = {}) {
  const { t } = useTranslation();
  const addToast = useToastStore((s) => s.addToast);
  const [installed, setInstalled] = useState<Record<string, true>>({});
  const ruleSets = bundledRuleSets ?? BUNDLED_RULESETS;

  const handleInstall = useCallback(
    (id: string) => {
      if (installed[id]) return;
      addToast(t('rules.market.installPending'), 'info');
      setInstalled((prev) => ({ ...prev, [id]: true }));
    },
    [installed, addToast, t],
  );

  return (
    <div className="space-y-5" data-testid="rule-market">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Sparkles size={24} className="text-amber-400" />
          <h2 className="text-2xl font-bold text-slate-100">{t('rules.market.title')}</h2>
        </div>
        <span className="text-sm text-slate-400">
          {ruleSets.length} {t('rules.market.available')}
        </span>
      </div>

      <p className="text-sm text-slate-400">{t('rules.market.description')}</p>

      {/* Rule-set list */}
      <div className="space-y-3" data-testid="rule-market-list">
        {ruleSets.length === 0 ? (
          <div
            className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center"
            data-testid="rule-market-empty"
          >
            <Package size={48} className="mx-auto text-slate-600 mb-4" />
            <p className="text-slate-500">{t('rules.market.empty')}</p>
          </div>
        ) : (
          ruleSets.map((rs) => {
            const Icon = categoryIcons[rs.category] || Shield;
            const color = categoryColors[rs.category] || 'text-slate-400';
            const isInstalled = !!installed[rs.id];

            return (
              <div
                key={rs.id}
                data-testid="rule-market-item"
                className="flex items-center gap-4 bg-slate-900/50 border border-slate-800 hover:border-slate-700 rounded-xl px-4 py-3 transition-colors"
              >
                <Icon size={20} className={`${color} flex-shrink-0`} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-slate-100">{t(rs.name)}</p>
                  <p className="text-xs text-slate-500 truncate">{t(rs.description)}</p>
                </div>
                <span className="text-xs text-slate-500 tabular-nums flex-shrink-0">
                  {rs.count.toLocaleString()} {t('rules.market.rules')}
                </span>
                {isInstalled ? (
                  <span
                    data-testid="rule-installed-badge"
                    className="flex items-center gap-1 text-xs text-emerald-400 flex-shrink-0"
                  >
                    <CheckCircle2 size={14} />
                    {t('rules.market.installed')}
                  </span>
                ) : (
                  <button
                    data-testid="rule-install-btn"
                    onClick={() => handleInstall(rs.id)}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-400 bg-blue-400/10 hover:bg-blue-400/20 border border-blue-400/30 rounded-lg transition-colors flex-shrink-0"
                  >
                    <Download size={12} />
                    {t('rules.market.install')}
                  </button>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
