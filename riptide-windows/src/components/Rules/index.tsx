import { useRules } from '../../hooks/useRules';
import { useRiptideStore } from '../../stores/riptide';
import { Shield, Globe, FileText, Loader2, AlertTriangle } from 'lucide-react';

const ruleIcons: Record<string, typeof Globe> = {
  DOMAIN: Globe,
  'DOMAIN-SUFFIX': Globe,
  'DOMAIN-KEYWORD': Globe,
  'IP-CIDR': Shield,
  'IP-CIDR6': Shield,
  GEOIP: Shield,
  GEOSITE: Shield,
  'RULE-SET': FileText,
  MATCH: Shield,
};

export function Rules() {
  const { isRunning } = useRiptideStore();
  const { data: rules = [], isLoading, isError } = useRules();

  const getPolicyColor = (policy: string) => {
    if (policy === 'DIRECT') return 'text-emerald-400';
    if (policy === 'REJECT') return 'text-red-400';
    return 'text-blue-400';
  };

  if (!isRunning) {
    return (
      <div className="space-y-5">
        <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Shield size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">启动代理以查看规则列表</p>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="space-y-5">
        <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
        <div className="flex items-center justify-center h-64">
          <Loader2 size={32} className="text-blue-400 animate-spin" />
          <span className="ml-3 text-slate-400">加载中...</span>
        </div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="space-y-5">
        <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
        <div className="bg-red-900/20 border border-red-800 rounded-xl p-6 flex items-center gap-3">
          <AlertTriangle size={20} className="text-red-400 flex-shrink-0" />
          <p className="text-red-400">加载规则数据失败，请确保 mihomo 正在运行</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
        <span className="text-sm text-slate-400">{rules.length} 条规则</span>
      </div>

      {rules.length === 0 ? (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl p-12 text-center">
          <Shield size={48} className="mx-auto text-slate-600 mb-4" />
          <p className="text-slate-500">暂无规则</p>
        </div>
      ) : (
        <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
          <div className="px-4 py-3 border-b border-slate-800 grid grid-cols-12 gap-2 text-xs font-medium text-slate-400 bg-slate-900/70">
            <div className="col-span-2">类型</div>
            <div className="col-span-5">匹配值</div>
            <div className="col-span-5">策略</div>
          </div>

          <div className="divide-y divide-slate-800 max-h-[calc(100vh-200px)] overflow-y-auto">
            {rules.map((rule, index) => {
              const Icon = ruleIcons[rule.type] || Shield;

              return (
                <div
                  key={index}
                  className="px-4 py-3 grid grid-cols-12 gap-2 items-center hover:bg-slate-800/40 transition-colors duration-150"
                >
                  <div className="col-span-2 flex items-center gap-2 min-w-0">
                    <Icon size={14} className="text-slate-400 flex-shrink-0" />
                    <span className="text-xs text-slate-300 truncate">{rule.type}</span>
                  </div>
                  <div className="col-span-5 text-xs text-slate-300 font-mono truncate" title={rule.payload}>
                    {rule.payload || '-'}
                  </div>
                  <div className={`col-span-5 text-xs font-medium ${getPolicyColor(rule.proxy)}`}>
                    {rule.proxy}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
