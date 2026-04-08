// React hooks for traffic statistics with real mihomo API data

import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import { useRiptideStore } from '../stores/riptide';
import * as tauri from '../services/tauri';

// Query keys
const TRAFFIC_KEYS = {
  all: ['traffic'] as const,
  stats: () => [...TRAFFIC_KEYS.all, 'stats'] as const,
};

/// Get traffic statistics with speed calculation
export function useTraffic() {
  const setTraffic = useRiptideStore(s => s.setTraffic);
  const isRunning = useRiptideStore(s => s.isRunning);
  
  // Keep track of previous values for speed calculation
  const prevValues = useRef<{ up: number; down: number; time: number } | null>(null);
  
  const query = useQuery({
    queryKey: TRAFFIC_KEYS.stats(),
    queryFn: async () => {
      const data = await tauri.getTraffic();
      const now = Date.now();
      
      // Calculate speeds
      let uploadSpeed = 0;
      let downloadSpeed = 0;
      
      if (prevValues.current) {
        const timeDiff = (now - prevValues.current.time) / 1000; // seconds
        if (timeDiff > 0) {
          uploadSpeed = Math.max(0, (data.up - prevValues.current.up) / timeDiff);
          downloadSpeed = Math.max(0, (data.down - prevValues.current.down) / timeDiff);
        }
      }
      
      // Update previous values
      prevValues.current = { up: data.up, down: data.down, time: now };
      
      // Update store
      setTraffic({
        upload: data.up,
        download: data.down,
        uploadSpeed,
        downloadSpeed,
      });
      
      return {
        ...data,
        uploadSpeed,
        downloadSpeed,
      };
    },
    enabled: isRunning,
    refetchInterval: 1000, // Refresh every second
  });

  // Reset on stop
  useEffect(() => {
    if (!isRunning) {
      prevValues.current = null;
      setTraffic({
        upload: 0,
        download: 0,
        uploadSpeed: 0,
        downloadSpeed: 0,
      });
    }
  }, [isRunning, setTraffic]);

  return query;
}
