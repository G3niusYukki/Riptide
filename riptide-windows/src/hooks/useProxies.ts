// React hooks for proxy operations with real mihomo API data

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { useRiptideStore } from '../stores/riptide';
import * as tauri from '../services/tauri';
import type { ProxyInfo } from '../types';

// Query keys
const PROXY_KEYS = {
  all: ['proxies'] as const,
  groups: () => [...PROXY_KEYS.all, 'groups'] as const,
  group: (name: string) => [...PROXY_KEYS.groups(), name] as const,
  list: () => [...PROXY_KEYS.all, 'list'] as const,
  delay: (name: string) => [...PROXY_KEYS.all, 'delay', name] as const,
};

/// Get all proxy groups
export function useProxyGroups() {
  const setProxyGroups = useRiptideStore(s => s.setProxyGroups);
  
  const query = useQuery({
    queryKey: PROXY_KEYS.groups(),
    queryFn: async () => {
      const groups = await tauri.getProxyGroups();
      // Transform to store format
      const storeGroups = groups.map(g => ({
        name: g.name,
        type: g.type as 'select' | 'url-test' | 'fallback' | 'load-balance',
        proxies: g.proxies,
        now: g.now,
        url: g.url,
        interval: g.interval,
      }));
      setProxyGroups(storeGroups);
      return groups;
    },
    enabled: useRiptideStore.getState().isRunning,
    refetchInterval: 5000, // Refresh every 5 seconds
  });

  return query;
}

/// Get all individual proxies
export function useAllProxies() {
  const setProxies = useRiptideStore(s => s.setProxies);
  
  const query = useQuery({
    queryKey: PROXY_KEYS.list(),
    queryFn: async () => {
      const proxies = await tauri.getAllProxies();
      // Transform to store format
      const storeProxies = proxies.map(p => ({
        name: p.name,
        server: '', // Not provided by API
        port: 0,
        type: p.type,
        delay: p.delay,
      }));
      setProxies(storeProxies);
      return proxies;
    },
    enabled: useRiptideStore.getState().isRunning,
    refetchInterval: 5000,
  });

  return query;
}

/// Test proxy delay
export function useTestDelay() {
  const queryClient = useQueryClient();
  const proxies = useRiptideStore(s => s.proxies);
  const setProxies = useRiptideStore(s => s.setProxies);
  
  return useMutation({
    mutationFn: async ({ name, url }: { name: string; url?: string }) => {
      const delay = await tauri.testProxyDelay(name, url);
      return { name, delay };
    },
    onSuccess: ({ name, delay }) => {
      // Update local cache
      queryClient.setQueryData<ProxyInfo[]>(PROXY_KEYS.list(), (old) => {
        if (!old) return old;
        return old.map(p => p.name === name ? { ...p, delay } : p);
      });
      
      // Update store
      const updatedProxies = proxies.map(p => 
        p.name === name ? { ...p, delay: delay ?? undefined } : p
      );
      setProxies(updatedProxies);
    },
  });
}

/// Switch proxy in a group
export function useSwitchProxy() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ group, proxyName }: { group: string; proxyName: string }) => {
      await tauri.switchProxy(group, proxyName);
      return { group, proxyName };
    },
    onSuccess: () => {
      // Invalidate groups to refresh current selection
      queryClient.invalidateQueries({ queryKey: PROXY_KEYS.groups() });
    },
  });
}

/// Test all proxies in a group
export function useTestGroupDelay() {
  return useMutation({
    mutationFn: async (group: string) => {
      const results = await tauri.testGroupDelay(group);
      return results;
    },
  });
}

/// Combined hook that loads all proxy data
export function useProxyData() {
  const isRunning = useRiptideStore(s => s.isRunning);
  
  const groupsQuery = useProxyGroups();
  const proxiesQuery = useAllProxies();
  
  // Auto-refresh when proxy starts/stops
  useEffect(() => {
    if (isRunning) {
      groupsQuery.refetch();
      proxiesQuery.refetch();
    }
  }, [isRunning, groupsQuery.refetch, proxiesQuery.refetch]);

  return {
    groups: groupsQuery.data ?? [],
    proxies: proxiesQuery.data ?? [],
    isLoading: groupsQuery.isLoading || proxiesQuery.isLoading,
    isError: groupsQuery.isError || proxiesQuery.isError,
    error: groupsQuery.error || proxiesQuery.error,
    refetch: () => {
      groupsQuery.refetch();
      proxiesQuery.refetch();
    },
  };
}
