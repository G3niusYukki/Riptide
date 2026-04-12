import { Shield, Globe, FileText } from 'lucide-react';

const ruleIcons: Record<string, typeof Globe> = {
  DOMAIN: Globe,
  'DOMAIN-SUFFIX': Globe,
  'DOMAIN-KEYWORD': Globe,
  'IP-CIDR': Shield,
  'IP-CIDR6': Shield,
  GEOIP: Shield,
  'RULE-SET': FileText,
  MATCH: Shield,
};

export function Rules() {
  // TODO: Load rules from active profile and use proxies
  // const { proxies } = useRiptideStore();
  
  // TODO: Load rules from active profile
  const rules: Array<{ type: string; value: string; policy: string }> = [
    { type: 'DOMAIN', value: 'localhost', policy: 'DIRECT' },
    { type: 'DOMAIN-SUFFIX', value: 'cn', policy: 'DIRECT' },
    { type: 'GEOIP', value: 'CN', policy: 'DIRECT' },
    { type: 'MATCH', value: '', policy: 'Proxy' },
  ];

  const getPolicyColor = (policy: string) => {
    if (policy === 'DIRECT') return 'text-emerald-400';
    if (policy === 'REJECT') return 'text-red-400';
    return 'text-blue-400';
  };

  return (
    <div className="space-y-5">
      <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
      
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
        <div className="px-4 py-3 border-b border-slate-800 grid grid-cols-12 gap-2 text-xs font-medium text-slate-400 bg-slate-900/70">
          <div className="col-span-2">类型</div>
          <div className="col-span-5">值</div>
          <div className="col-span-3">策略</div>
          <div className="col-span-2 text-right">操作</div>
        </div>
        
        <div className="divide-y divide-slate-800">
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
                <div className="col-span-5 text-xs text-slate-300 font-mono truncate">
                  {rule.value}
                </div>
                <div className={`col-span-3 text-xs font-medium ${getPolicyColor(rule.policy)}`}>
                  {rule.policy}
                </div>
                <div className="col-span-2 text-right">
                  <button className="text-xs px-2.5 py-1 bg-slate-800 hover:bg-slate-700 rounded text-slate-300 transition-colors focus:outline-none focus:ring-1 focus:ring-blue-500/50">
                    编辑
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
