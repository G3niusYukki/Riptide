import { useQuery } from '@tanstack/react-query';
import * as tauri from '../services/tauri';
import { useRiptideStore } from '../stores/riptide';
import type { RuleInfo } from '../types';

const RULE_KEYS = {
  all: ['rules'] as const,
  list: () => [...RULE_KEYS.all, 'list'] as const,
};

export function useRules() {
  const isRunning = useRiptideStore((s) => s.isRunning);

  return useQuery<RuleInfo[]>({
    queryKey: RULE_KEYS.list(),
    queryFn: () => tauri.getRules(),
    enabled: isRunning,
    refetchInterval: 10_000,
    staleTime: 5_000,
  });
}
