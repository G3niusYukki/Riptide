// Type definitions for Riptide Windows

export interface Profile {
  id: string;
  name: string;
  content: string;
  created_at: string;
  updated_at: string;
}

export interface Proxy {
  name: string;
  server: string;
  port: number;
  type: string;
  delay?: number;
}

export interface ProxyGroup {
  name: string;
  type: 'select' | 'url-test' | 'fallback' | 'load-balance';
  proxies: string[];
  now?: string;
  url?: string;
  interval?: number;
}

export interface Rule {
  type: string;
  value: string;
  policy: string;
}

export interface Connection {
  id: string;
  host: string;
  port: number;
  upload: number;
  download: number;
  startTime: string;
  chains: string[];
  rule?: string;
}

export interface TrafficStats {
  upload: number;
  download: number;
  uploadSpeed: number;
  downloadSpeed: number;
}

export interface AppState {
  isRunning: boolean;
  activeProfile: string | null;
  systemProxyEnabled: boolean;
  tunModeEnabled: boolean;
}
