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

// Mihomo API Types
export interface ProxyInfo {
  name: string;
  type: string;
  alive?: boolean;
  delay?: number;
  history?: DelayHistory[];
}

export interface DelayHistory {
  time: string;
  delay: number;
}

export interface ProxyGroupDetail {
  name: string;
  group_type: string;
  proxies: string[];
  now?: string;
  url?: string;
  interval?: number;
  tolerance?: number;
  delay?: number;
}

export interface ConnectionMetadata {
  network: string;
  type: string;
  sourceIP: string;
  destinationIP?: string;
  host?: string;
  sourcePort: string;
  destinationPort: string;
}

export interface ConnectionInfo {
  id: string;
  metadata: ConnectionMetadata;
  upload: number;
  download: number;
  start: string;
  chains: string[];
  rule?: string;
}

export interface TrafficData {
  up: number;
  down: number;
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
