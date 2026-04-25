// Zustand store for global state management

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { Profile, Proxy, ProxyGroup, Connection, TrafficStats, AppState } from '../types';

interface RiptideState extends AppState {
  // Profiles
  profiles: Profile[];
  setProfiles: (profiles: Profile[]) => void;
  addProfile: (profile: Profile) => void;
  removeProfile: (id: string) => void;

  // Proxies
  proxies: Proxy[];
  setProxies: (proxies: Proxy[]) => void;
  proxyGroups: ProxyGroup[];
  setProxyGroups: (groups: ProxyGroup[]) => void;
  selectedProxy: string | null;
  setSelectedProxy: (name: string | null) => void;

  // Connections
  connections: Connection[];
  setConnections: (connections: Connection[]) => void;

  // Traffic
  traffic: TrafficStats;
  setTraffic: (traffic: TrafficStats) => void;

  // App state
  setIsRunning: (running: boolean) => void;
  setActiveProfile: (id: string | null) => void;
  setSystemProxyEnabled: (enabled: boolean) => void;
  setTunModeEnabled: (enabled: boolean) => void;
  setAutoStart: (enabled: boolean) => void;
  setSilentStart: (enabled: boolean) => void;
}

export const useRiptideStore = create<RiptideState>()(
  persist(
    (set) => ({
      // Initial state
      isRunning: false,
      activeProfile: null,
      systemProxyEnabled: false,
      tunModeEnabled: false,
      autoStart: false,
      silentStart: false,
      profiles: [],
      proxies: [],
      proxyGroups: [],
      selectedProxy: null,
      connections: [],
      traffic: {
        upload: 0,
        download: 0,
        uploadSpeed: 0,
        downloadSpeed: 0,
      },
      
      // Actions
      setProfiles: (profiles) => set({ profiles }),
      addProfile: (profile) => set((state) => ({ 
        profiles: [...state.profiles, profile] 
      })),
      removeProfile: (id) => set((state) => ({ 
        profiles: state.profiles.filter((p) => p.id !== id) 
      })),
      
      setProxies: (proxies) => set({ proxies }),
      setProxyGroups: (groups) => set({ proxyGroups: groups }),
      setSelectedProxy: (name) => set({ selectedProxy: name }),
      
      setConnections: (connections) => set({ connections }),
      setTraffic: (traffic) => set({ traffic }),
      
      setIsRunning: (running) => set({ isRunning: running }),
      setActiveProfile: (id) => set({ activeProfile: id }),
      setSystemProxyEnabled: (enabled) => set({ systemProxyEnabled: enabled }),
      setTunModeEnabled: (enabled) => set({ tunModeEnabled: enabled }),
      setAutoStart: (enabled) => set({ autoStart: enabled }),
      setSilentStart: (enabled) => set({ silentStart: enabled }),
    }),
    {
      name: 'riptide-storage',
      partialize: (state) => ({
        activeProfile: state.activeProfile,
        selectedProxy: state.selectedProxy,
        autoStart: state.autoStart,
        silentStart: state.silentStart,
      }),
    }
  )
);
