// Tauri IPC service wrappers

import { invoke } from '@tauri-apps/api/core';

// Proxy commands
export const startProxy = () => invoke<void>('start_proxy');
export const stopProxy = () => invoke<void>('stop_proxy');
export const restartProxy = () => invoke<void>('restart_proxy');
export const getProxyStatus = () => invoke<boolean>('get_proxy_status');
export const testProxyDelay = (name: string, url?: string) => 
  invoke<number>('test_proxy_delay', { name, url });

// Config commands
export const getProfiles = () => invoke<Profile[]>('get_profiles');
export const addProfile = (name: string, content: string) => 
  invoke<void>('add_profile', { name, content });
export const removeProfile = (id: string) => 
  invoke<void>('remove_profile', { id });
export const updateProfile = (id: string, content: string) => 
  invoke<void>('update_profile', { id, content });
export const importProfileFromUrl = (url: string) => 
  invoke<string>('import_profile_from_url', { url });
export const getActiveProfile = () => invoke<string | null>('get_active_profile');
export const setActiveProfile = (id: string) => 
  invoke<void>('set_active_profile', { id });

// System commands
export const enableSystemProxy = (httpPort: number, socksPort?: number) => 
  invoke<void>('enable_system_proxy', { httpPort, socksPort });
export const disableSystemProxy = () => invoke<void>('disable_system_proxy');
export const getSystemProxyStatus = () => invoke<boolean>('get_system_proxy_status');
export const installTunService = () => invoke<void>('install_tun_service');
export const uninstallTunService = () => invoke<void>('uninstall_tun_service');
export const startTunService = () => invoke<void>('start_tun_service');
export const stopTunService = () => invoke<void>('stop_tun_service');

import type { Profile } from '../types';
