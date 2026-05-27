// Tauri IPC service wrappers

import { invoke } from '@tauri-apps/api/core';
import type {
  Profile,
  ProxyInfo,
  ProxyGroupDetail,
  ConnectionInfo,
  TrafficData,
  RuleInfo,
  ProfileMetadata,
  RewriteRule,
} from '../types';

// Proxy commands
export const startProxy = () => invoke<void>('start_proxy');
export const stopProxy = () => invoke<void>('stop_proxy');
export const restartProxy = () => invoke<void>('restart_proxy');
export const getProxyStatus = () => invoke<boolean>('get_proxy_status');
export const testProxyDelay = (name: string, url?: string) => 
  invoke<number>('test_proxy_delay', { name, url });
export const getProxyGroups = () => 
  invoke<ProxyGroupDetail[]>('get_proxy_groups');
export const getAllProxies = () => 
  invoke<ProxyInfo[]>('get_all_proxies');
export const switchProxy = (group: string, proxyName: string) => 
  invoke<void>('switch_proxy', { group, proxyName });
export const testGroupDelay = (group: string) => 
  invoke<Record<string, number>>('test_group_delay', { group });

// Connection commands
export const getConnections = () =>
  invoke<ConnectionInfo[]>('get_connections');
export const closeConnection = (id: string) =>
  invoke<void>('close_connection', { id });
export const closeAllConnections = () =>
  invoke<void>('close_all_connections');
export const getTraffic = () =>
  invoke<TrafficData>('get_traffic');
export const getRules = () =>
  invoke<RuleInfo[]>('get_rules');

// Config commands (disk-backed)
export const getProfiles = () => invoke<Profile[]>('list_profiles');
export const addProfile = (name: string, content: string) =>
  invoke<Profile>('create_profile', { name, content });
export const removeProfile = (id: string) =>
  invoke<void>('delete_profile', { id });
export const updateProfile = (id: string, content: string) =>
  invoke<void>('update_profile', { id, content });
export const importProfileFromUrl = (url: string, name?: string) =>
  invoke<Profile>('import_profile_from_url', { url, name });
export const importProfileFromFile = (path: string) =>
  invoke<Profile>('import_profile_from_file', { path });
export const importShareUri = (uri: string) =>
  invoke<Profile>('import_share_uri', { uri });
export const exportProfile = (id: string, path: string) =>
  invoke<void>('export_profile', { id, path });
export const validateConfig = (content: string) =>
  invoke<{ valid: boolean; message?: string; proxy_count?: number; group_count?: number }>(
    'validate_config',
    { content },
  );
export const getActiveProfile = () => invoke<string | null>('get_active_profile');
export const setActiveProfile = (id: string) =>
  invoke<void>('set_active_profile', { id });
export const refreshProfile = (id: string) =>
  invoke<Profile>('refresh_profile', { id });
export const setProfileSubscription = (
  id: string,
  url: string | null,
  intervalSecs: number | null,
) =>
  invoke<void>('set_profile_subscription', {
    id,
    url,
    intervalSecs,
  });
export const getProfileMetadata = (id: string) =>
  invoke<ProfileMetadata>('get_profile_metadata', { id });

// Per-proxy editor (in-profile CRUD)
//
// Field names mirror the Rust ClashRawProxy struct's serde representation:
// — kebab-case for fields marked with #[serde(rename)] (e.g. "skip-cert-verify")
// — snake_case for plain fields ("alter_id" stays snake_case in JSON because
//   only "alterId" gets the rename, etc.)
// Keep new fields in sync with config/parser.rs.
export interface ClashProxy {
  name: string;
  type?: string;
  server?: string;
  port?: number;
  udp?: boolean;
  network?: string;

  // Shadowsocks
  cipher?: string;
  password?: string;
  plugin?: string;
  'plugin-opts'?: Record<string, unknown>;

  // VMess / VLESS
  uuid?: string;
  alterId?: number;
  security?: string;
  flow?: string;

  // TLS-ish
  'skip-cert-verify'?: boolean;
  sni?: string;
  alpn?: string[];
  fingerprint?: string;
  'client-fingerprint'?: string;

  // Hysteria2
  ports?: string;
  'hop-interval'?: number;
  'ca-str'?: string;
  ca?: string;
  obfs?: string;
  'obfs-password'?: string;

  // TUIC
  'congestion-controller'?: string;
  'udp-relay-mode'?: string;
  'heartbeat-interval'?: number;
  'disable-sni'?: boolean;
  'reduce-rtt'?: boolean;
  'request-version'?: number;
  'max-udp-relay-packet-size'?: number;
  'fast-open'?: boolean;
  'max-open-streams'?: number;

  // WebSocket / gRPC / H2
  'ws-path'?: string;
  'ws-headers'?: Record<string, string>;
  'grpc-service-name'?: string;
  'h2-host'?: string[];

  // Reality (VLESS/XTLS)
  'reality-opts'?: { public_key?: string; 'short-id'?: string; 'spider-x'?: string };
  pbk?: string;
  sid?: string;
  spx?: string;

  // HTTP / SOCKS5
  username?: string;
  headers?: Record<string, string>;
  tls?: boolean;
  'udp-over-tcp'?: boolean;

  // Snell
  version?: number;

  // AnyTLS — session pooling controls (mihomo native)
  'idle-session-check-interval'?: number;
  'idle-session-timeout'?: number;
  'min-idle-session'?: number;
}

export const listProfileProxies = (profileId: string) =>
  invoke<ClashProxy[]>('list_profile_proxies', { profileId });
export const addProfileProxy = (profileId: string, proxy: ClashProxy) =>
  invoke<void>('add_profile_proxy', { profileId, proxy });
export const updateProfileProxy = (
  profileId: string,
  originalName: string,
  proxy: ClashProxy,
) => invoke<void>('update_profile_proxy', { profileId, originalName, proxy });
export const deleteProfileProxy = (profileId: string, name: string) =>
  invoke<void>('delete_profile_proxy', { profileId, name });

// System commands
export const enableSystemProxy = (httpPort: number, socksPort?: number) =>
  invoke<void>('enable_system_proxy', { httpPort, socksPort });
export const disableSystemProxy = () => invoke<void>('disable_system_proxy');
export const getSystemProxyStatus = () => invoke<boolean>('get_system_proxy_status');

// TUN service (Windows service install/start/stop)
export const installTunService = () => invoke<void>('install_tun_service');
export const uninstallTunService = () => invoke<void>('uninstall_tun_service');
export const startTunService = () => invoke<void>('start_tun_service');
export const stopTunService = () => invoke<void>('stop_tun_service');
export type TunServiceStatus =
  | 'not_installed'
  | 'stopped'
  | 'start_pending'
  | 'running'
  | 'stop_pending'
  | 'paused'
  | 'pause_pending'
  | 'continue_pending'
  | 'unknown';
export const getTunServiceStatus = () => invoke<TunServiceStatus>('get_tun_service_status');
export const isElevated = () => invoke<boolean>('is_elevated');

// TUN mode (mihomo-backed)
export interface TunOptions {
  device: string;
  stack: string;
  auto_route: boolean;
  auto_detect_interface: boolean;
  strict_route: boolean;
  mtu: number;
  dns_hijack: string[];
}
export const startTunMode = () => invoke<void>('start_tun_mode');
export const stopTunMode = () => invoke<void>('stop_tun_mode');
export const getTunStatus = () => invoke<{
  status: string;
  running: boolean;
  adapter_name?: string;
  interface_ip?: string;
  gateway?: string;
}>('get_tun_status');
export const getTunOptions = () => invoke<TunOptions>('get_tun_options');
export const setTunOptions = (options: TunOptions) =>
  invoke<void>('set_tun_options', { options });

// mihomo binary lifecycle
export const downloadMihomo = () => invoke<string>('download_mihomo');

// WARP — anonymous registration that saves the result as a Clash profile.
export const registerWarpProfile = (name?: string) =>
  invoke<Profile>('register_warp_profile', { name });

// Mode coordinator
export type AppMode = 'off' | 'system_proxy' | 'tun';
export const modeCurrent = () => invoke<AppMode>('mode_current');
export const modeSwitchToSystemProxy = (httpPort: number, socksPort?: number) =>
  invoke<void>('mode_switch_to_system_proxy', { httpPort, socksPort });
export const modeSwitchToTun = () => invoke<void>('mode_switch_to_tun');
export const modeSwitchOff = () => invoke<void>('mode_switch_off');

// Geo assets
export interface GeoAsset {
  name: string;
  installed: boolean;
  size_bytes?: number;
  last_modified?: string;
}
export const getGeoAssets = () => invoke<GeoAsset[]>('get_geo_assets');
export const downloadGeoAssets = () => invoke<void>('download_geo_assets');

// DNS policy
export interface DnsPolicy {
  enable_override: boolean;
  enable?: boolean;
  listen?: string;
  enhanced_mode?: string; // "fake-ip" | "redir-host"
  fake_ip_range?: string;
  fake_ip_filter: string[];
  default_nameserver: string[];
  nameserver: string[];
  fallback: string[];
  nameserver_policy: Record<string, string>;
  respect_rules?: boolean;
}
export const getDnsPolicy = () => invoke<DnsPolicy>('get_dns_policy');
export const setDnsPolicy = (policy: DnsPolicy) =>
  invoke<void>('set_dns_policy', { policy });

// Rewrite rules
export const getRewriteRules = () => invoke<RewriteRule[]>('get_rewrite_rules');
export const setRewriteRules = (rules: RewriteRule[]) =>
  invoke<void>('set_rewrite_rules', { rules });
export const addRewriteRule = (rule: RewriteRule) =>
  invoke<void>('add_rewrite_rule', { rule });
export const deleteRewriteRule = (id: string) =>
  invoke<void>('delete_rewrite_rule', { id });
export const toggleRewriteRule = (id: string, enabled: boolean) =>
  invoke<void>('toggle_rewrite_rule', { id, enabled });

// WebDAV sync
export interface WebDAVConfigDto {
  endpoint: string;
  username: string;
  has_password: boolean;
  remote_path: string;
  enabled: boolean;
}
export const webdavGetConfig = () => invoke<WebDAVConfigDto>('webdav_get_config');
export const webdavSetConfig = (
  endpoint: string,
  username: string,
  password: string,
  remotePath: string,
  enabled: boolean,
) =>
  invoke<WebDAVConfigDto>('webdav_set_config', {
    endpoint,
    username,
    password,
    remotePath,
    enabled,
  });
export const webdavTestConnection = () => invoke<void>('webdav_test_connection');
export const webdavBackupNow = () => invoke<void>('webdav_backup_now');
export const webdavRestoreNow = () => invoke<void>('webdav_restore_now');

// Kill switch
export interface KillSwitchState {
  enabled: boolean;
  armed: boolean;
}
export const getKillSwitchState = () => invoke<KillSwitchState>('get_kill_switch_state');
export const setKillSwitchEnabled = (enabled: boolean) =>
  invoke<void>('set_kill_switch_enabled', { enabled });
export const killSwitchRelease = () => invoke<void>('kill_switch_release');

// Diagnostics
export interface DiagnosticReport {
  riptide_version: string;
  os: string;
  mode: string;
  mihomo_path: string;
  mihomo_installed: boolean;
  mihomo_version?: string;
  active_profile?: {
    name: string;
    node_count?: number;
    last_updated?: string;
    has_subscription: boolean;
  };
  tun_service_status: string;
  kill_switch: { enabled: boolean; armed: boolean };
  geo_assets: { name: string; installed: boolean; size_bytes?: number }[];
  log_tail: string;
}
export const collectDiagnosticReport = () =>
  invoke<DiagnosticReport>('collect_diagnostic_report');

// Hotkey commands
export const getHotkeys = () => invoke<string[]>('get_hotkeys');

// Update check
export interface UpdateInfo {
  current_version: string;
  latest_version: string;
  update_available: boolean;
  release_url: string;
}
export const checkUpdate = () => invoke<UpdateInfo>('check_update');

// Log commands
export const getLogs = (level?: string, lines?: number) =>
  invoke<string>('get_logs', { level, lines });
