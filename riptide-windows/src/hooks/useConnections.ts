// React hooks for connections with real mihomo API data

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useRiptideStore } from '../stores/riptide';
import * as tauri from '../services/tauri';

// Query keys
const CONNECTION_KEYS = {
  all: ['connections'] as const,
  list: () => [...CONNECTION_KEYS.all, 'list'] as const,
};

/// Get active connections
export function useConnections() {
  const setConnections = useRiptideStore(s => s.setConnections);
  const isRunning = useRiptideStore(s => s.isRunning);
  
  const query = useQuery({
    queryKey: CONNECTION_KEYS.list(),
    queryFn: async () => {
      const connections = await tauri.getConnections();
      
      // Transform to store format
      const storeConnections = connections.map(c => ({
        id: c.id,
        host: c.metadata.host ?? c.metadata.destinationIP ?? 'unknown',
        port: parseInt(c.metadata.destinationPort) || 0,
        upload: c.upload,
        download: c.download,
        startTime: c.start,
        chains: c.chains,
        rule: c.rule,
      }));
      
      setConnections(storeConnections);
      return connections;
    },
    enabled: isRunning,
    refetchInterval: 2000, // Refresh every 2 seconds
  });

  return query;
}

/// Close a connection
export function useCloseConnection() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      await tauri.closeConnection(id);
      return id;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CONNECTION_KEYS.list() });
    },
  });
}

/// Close all connections
export function useCloseAllConnections() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async () => {
      await tauri.closeAllConnections();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CONNECTION_KEYS.list() });
    },
  });
}
