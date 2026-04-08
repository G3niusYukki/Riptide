import { useRiptideStore } from '../../stores/riptide';
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
  const { proxies } = useRiptideStore();
  
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
    <div className="space-y-6">
      <h2 className="text-2xl font-bold text-slate-100">规则列表</h2>
      
      <div className="bg-slate-900/50 border border-slate-800 rounded-xl overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-800 grid grid-cols-12 gap-4 text-sm font-medium text-slate-400">
          <div className="col-span-2">类型</div>
          <div className="col-span-5">值</div>
          <div className="col-span-3">策略</div>
          <div className="col-span-2">操作</div>
        </div>
        
        <div className="divide-y divide-slate-800">
          {rules.map((rule, index) => {
            const Icon = ruleIcons[rule.type] || Shield;
            
            return (
              <div 
                key={index}
                className="px-6 py-4 grid grid-cols-12 gap-4 items-center hover:bg-slate-800/30 transition-colors"
              >
                <div className="col-span-2 flex items-center gap-2">
                  <Icon size={16} className="text-slate-400" />
                  <span className="text-sm text-slate-300">{rule.type}</span>
                </div>
                <div className="col-span-5 text-sm text-slate-300 font-mono truncate">
                  {rule.value}
                </div>
                <div className={`col-span-3 text-sm font-medium ${getPolicyColor(rule.policy)}`}>
                  {rule.policy}
                </div>
                <div className="col-span-2">
                  <button className="text-xs px-3 py-1.5 bg-slate-800 hover:bg-slate-700 rounded text-slate-300 transition-colors">
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
